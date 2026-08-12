import SwiftUI
import PhotosUI
import UIKit

struct TeamsView: View {
    @Environment(AppState.self) private var appState

    @State private var path = NavigationPath()
    @State private var teams: [Team] = []
    @State private var unreadThreads: [CommentThread] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var showingCreateTeam = false
    @State private var newTeamName = ""
    @State private var teamToRename: Team?
    @State private var renameText = ""
    @State private var teamToDelete: Team?
    @State private var photoTeam: Team?
    @State private var showTeamPhotoPicker = false
    @State private var teamPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .penpotPageBackground()
                .navigationTitle("Dashboard")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { newTeamName = ""; showingCreateTeam = true } label: {
                            AppIcon.add.image
                        }
                        .accessibilityLabel("New Team")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Log Out", role: .destructive) {
                                appState.logout()
                            }
                        } label: {
                            AppIcon.more.image
                        }
                        .accessibilityLabel("Account options")
                    }
                }
                .task { await load() }
                .refreshable { await load() }
                .alert("New Team", isPresented: $showingCreateTeam) {
                    TextField("Team name", text: $newTeamName)
                    Button("Cancel", role: .cancel) {}
                    Button("Create") { Task { await createTeam() } }
                } message: {
                    Text("Enter a name for the new team.")
                }
                .alert("Rename Team", isPresented: renameAlert, presenting: teamToRename) { team in
                    TextField("Name", text: $renameText)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") { Task { await rename(team) } }
                }
                .alert("Something went wrong", isPresented: actionErrorAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(actionError ?? "")
                }
                .photosPicker(isPresented: $showTeamPhotoPicker,
                              selection: $teamPhotoItem, matching: .images)
                .onChange(of: teamPhotoItem) { _, item in
                    if let item { Task { await uploadTeamPhoto(item) } }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && teams.isEmpty {
            LoadingView(message: "Loading teams…")
        } else if let errorMessage, teams.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if teams.isEmpty {
            EmptyStateView(title: "No teams", icon: .teams)
        } else {
            // Hand-built cards rather than a List: this screen is a menu, and Penpot's
            // outlined panel can't be drawn behind a List section (see PenpotCard).
            // Deleting a team lives in the context menu; swiping is restored by
            // penpotSwipeActions.
            ScrollView {
                VStack(spacing: 16) {
                    PenpotCard {
                        NavigationLink { SettingsView() } label: {
                            PenpotCardRow { profileRow }
                        }
                        .buttonStyle(.plain)
                    }

                    PenpotCard {
                        NavigationLink {
                            CommentsInboxView(teams: teams, threads: $unreadThreads)
                        } label: {
                            PenpotCardRow {
                                AppIcon.comments.label("Comments")
                            } trailing: {
                                if !unreadThreads.isEmpty {
                                    Text("\(unreadThreads.count)")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    PenpotCard {
                        ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                            NavigationLink(value: team) {
                                PenpotCardRow {
                                    HStack(spacing: 12) {
                                        avatar(
                                            photoID: team.photoId,
                                            fallbackSymbol: "cube.fill",
                                            fallbackAsset: team.isDefault == true ? "PenpotLogo" : nil,
                                            initials: team.isDefault == true ? nil : team.displayName,
                                            size: 28)
                                        Text(team.displayName)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { teamMenu(team) }
                            .penpotSwipeActions(id: team.id) {
                                // Same gate as teamMenu: the server rejects deleting the
                                // default team, so it must not be swipeable either.
                                if team.isDefault != true {
                                    PenpotSwipeAction("Delete", icon: .delete,
                                                      isDestructive: true) { teamToDelete = team }
                                }
                            }
                            // Attached to the row (not the screen) so the dialog's popover
                            // anchors to the team it will delete.
                            .confirmationDialog("Delete Team", isPresented: deleteDialog(for: team)) {
                                Button("Delete", role: .destructive) { Task { await delete(team) } }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("“\(team.displayName)” and all of its projects and files will be deleted.")
                            }
                            if index < teams.count - 1 {
                                PenpotCardDivider()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationDestination(for: Team.self) { team in
                TeamDashboardView(team: team, onTeamGone: {
                    // The user left this team: pop everything and refresh the list so no
                    // screen of a team they no longer belong to stays on the stack.
                    path = NavigationPath()
                    Task { await load() }
                })
            }
        }
    }

    /// Label only — the surrounding card row supplies the navigation link and chevron.
    private var profileRow: some View {
        HStack(spacing: 12) {
            avatar(photoID: appState.profile?.photoId, fallbackSymbol: "person.fill",
                   initials: appState.profile?.displayName ?? SessionStore.email, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.profile?.displayName ?? SessionStore.email ?? "Account")
                    .font(.workSans(.headline))
                if let email = appState.profile?.email {
                    Text(email).font(.workSans(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// A Penpot avatar (profile or team — both are served like any media id), falling back to a
    /// glyph, or to an initial letter when `initials` is supplied.
    private func avatar(photoID: String?, fallbackSymbol: String, fallbackAsset: String? = nil,
                        initials: String? = nil, size: CGFloat) -> some View {
        PenpotAvatar(photoID: photoID, baseURL: appState.client?.baseURL,
                     fallbackSymbol: fallbackSymbol, fallbackAsset: fallbackAsset,
                     initials: initials, size: size)
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            teams = try await client.teams()
            if let first = teams.first {
                await appState.resolveProfileIfNeeded(teamID: first.id)
            }
            // Only drives the unread badge — a failure here must not blank the team list.
            unreadThreads = (try? await client.unreadCommentThreads(teams: teams)) ?? []
        } catch {
            handle(error)
        }
        isLoading = false
    }

    /// Rename and delete are hidden for the default team — the server rejects both.
    /// Photo changes additionally need admin/owner rights (a violation would 404).
    @ViewBuilder
    private func teamMenu(_ team: Team) -> some View {
        if team.isDefault != true {
            Button { startRename(team) } label: { AppIcon.edit.label("Rename") }
            if team.permissions?.isAdminOrOwner == true {
                Button { photoTeam = team; showTeamPhotoPicker = true } label: {
                    AppIcon.image.label("Change Photo")
                }
                .disabled(isUploadingPhoto)
            }
            Button(role: .destructive) { teamToDelete = team } label: {
                AppIcon.delete.destructiveLabel("Delete")
            }
        }
    }

    /// Mirrors ProfileSettingsView's avatar flow; the response already carries the new
    /// photoId, but a full reload keeps every row (and permissions) fresh in one go.
    private func uploadTeamPhoto(_ item: PhotosPickerItem) async {
        guard let client = appState.client, let team = photoTeam else { return }
        isUploadingPhoto = true
        defer {
            isUploadingPhoto = false
            teamPhotoItem = nil
            photoTeam = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.9) else {
                actionError = .appLocalized("Couldn’t read that image.")
                return
            }
            try await client.updateTeamPhoto(teamID: team.id, data: jpeg,
                                             mimeType: "image/jpeg", filename: "team.jpg")
            await load()
        } catch { handleActionError(error) }
    }

    private var actionErrorAlert: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }
    private var renameAlert: Binding<Bool> {
        Binding(get: { teamToRename != nil }, set: { if !$0 { teamToRename = nil } })
    }
    private func deleteDialog(for team: Team) -> Binding<Bool> {
        Binding(get: { teamToDelete == team }, set: { if !$0 { teamToDelete = nil } })
    }

    private func createTeam() async {
        let name = newTeamName.trimmingCharacters(in: .whitespaces)
        guard let client = appState.client, !name.isEmpty else { return }
        do {
            try await client.createTeam(name: name)
            await load()
        } catch { handleActionError(error) }
    }

    private func startRename(_ team: Team) {
        renameText = team.name
        teamToRename = team
    }

    private func rename(_ team: Team) async {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard let client = appState.client, !name.isEmpty else { return }
        do {
            try await client.renameTeam(id: team.id, name: name)
            await load()
        } catch { handleActionError(error) }
    }

    private func delete(_ team: Team) async {
        guard let client = appState.client else { return }
        do {
            try await client.deleteTeam(id: team.id)
            await load()
        } catch { handleActionError(error) }
    }

    private func handleActionError(_ error: Error) {
        if case PenpotError.unauthorized = error {
            appState.logout()
            return
        }
        actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func handle(_ error: Error) {
        if case PenpotError.unauthorized = error {
            appState.logout()
            return
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

extension Team: Hashable {
    static func == (lhs: Team, rhs: Team) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
