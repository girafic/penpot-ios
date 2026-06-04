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
                            if let name = appState.profile?.displayName {
                                Text(name)
                            }
                            Button("Log Out", role: .destructive) {
                                appState.logout()
                            }
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
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
            List(teams) { team in
                NavigationLink(value: team) {
                    Label(team.name, systemImage: team.isDefault == true ? "star" : "person.3")
                }
            }
            .navigationDestination(for: Team.self) { team in
                ProjectsFilesView(team: team)
            }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            teams = try await client.teams()
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
