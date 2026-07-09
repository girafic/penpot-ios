import SwiftUI

struct TeamsView: View {
    @Environment(AppState.self) private var appState

    @State private var teams: [Team] = []
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
                Section("Teams") {
                    ForEach(teams) { team in
                        NavigationLink(value: team) {
                            Label(team.name, systemImage: team.isDefault == true ? "star" : "person.3")
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
        HStack(spacing: 12) {
            avatar(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.profile?.displayName ?? SessionStore.email ?? "Account")
                    .font(.headline)
                if let email = appState.profile?.email {
                    Text(email).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// The user's Penpot avatar (served like any media id), falling back to a person glyph.
    @ViewBuilder
    private func avatar(size: CGFloat) -> some View {
        if let photoId = appState.profile?.photoId, let baseURL = appState.client?.baseURL {
            RemoteImage(mediaID: photoId, baseURL: baseURL, contentMode: .fill) {
                Circle().fill(.quaternary).overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.secondary))
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
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
