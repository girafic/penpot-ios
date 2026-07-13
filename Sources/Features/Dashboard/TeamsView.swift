import SwiftUI

struct TeamsView: View {
    @Environment(AppState.self) private var appState

    @State private var teams: [Team] = []
    @State private var unreadThreads: [CommentThread] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Teams")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Log Out", role: .destructive) {
                                appState.logout()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Account options")
                    }
                }
                .task { await load() }
                .refreshable { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && teams.isEmpty {
            LoadingView(message: "Loading teams…")
        } else if let errorMessage, teams.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if teams.isEmpty {
            EmptyStateView(title: "No teams", systemImage: "person.3")
        } else {
            List {
                Section { profileRow }
                Section {
                    NavigationLink {
                        CommentsInboxView(teams: teams, threads: $unreadThreads)
                    } label: {
                        Label("Comments", systemImage: "bubble.left.and.bubble.right")
                    }
                    .badge(unreadThreads.count)
                }
                Section("Teams") {
                    ForEach(teams) { team in
                        NavigationLink(value: team) {
                            HStack(spacing: 12) {
                                avatar(
                                    photoID: team.photoId,
                                    fallbackSymbol: team.isDefault == true ? "cube.fill" : "person.3.fill",
                                    size: 28)
                                Text(team.displayName)
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: Team.self) { team in
                ProjectsFilesView(team: team)
            }
        }
    }

    private var profileRow: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: 12) {
                avatar(photoID: appState.profile?.photoId, fallbackSymbol: "person.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.profile?.displayName ?? SessionStore.email ?? "Account")
                        .font(.headline)
                    if let email = appState.profile?.email {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// A Penpot avatar (profile or team — both are served like any media id), falling back to a glyph.
    private func avatar(photoID: String?, fallbackSymbol: String, size: CGFloat) -> some View {
        PenpotAvatar(photoID: photoID, baseURL: appState.client?.baseURL,
                     fallbackSymbol: fallbackSymbol, size: size)
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
