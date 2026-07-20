import SwiftUI

struct TeamsView: View {
    @Environment(AppState.self) private var appState

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

    var body: some View {
        NavigationStack {
            content
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
            List {
                Section { profileRow }
                Section {
                    NavigationLink {
                        CommentsInboxView(teams: teams, threads: $unreadThreads)
                    } label: {
                        AppIcon.comments.label("Comments")
                    }
                    .badge(unreadThreads.count)
                }
                Section {
                    ForEach(teams) { team in
                        NavigationLink(value: team) {
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
                        .swipeActions(edge: .trailing) {
                            if team.isDefault != true {
                                Button(role: .destructive) { teamToDelete = team } label: {
                                    AppIcon.delete.label("Delete")
                                }
                            }
                        }
                        .contextMenu { teamMenu(team) }
                        // Attached to the row (not the screen) so the dialog's popover
                        // anchors to the team it will delete.
                        .confirmationDialog("Delete Team", isPresented: deleteDialog(for: team)) {
                            Button("Delete", role: .destructive) { Task { await delete(team) } }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("“\(team.displayName)” and all of its projects and files will be deleted.")
                        }
                    }
                }
            }
            .contentMargins(.top, 16, for: .scrollContent)
            .navigationDestination(for: Team.self) { team in
                TeamDashboardView(team: team)
            }
        }
    }

    private var profileRow: some View {
        NavigationLink {
            SettingsView()
        } label: {
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
            .padding(.vertical, 4)
        }
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
    @ViewBuilder
    private func teamMenu(_ team: Team) -> some View {
        if team.isDefault != true {
            Button { startRename(team) } label: { AppIcon.edit.label("Rename") }
            Button(role: .destructive) { teamToDelete = team } label: {
                AppIcon.delete.label("Delete")
            }
        }
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
