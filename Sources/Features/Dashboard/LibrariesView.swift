import SwiftUI

/// A team's shared libraries (`get-team-shared-files`) as file cards. Tapping one opens it.
struct LibrariesView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    let team: Team

    @State private var libraries: [FileListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        content
            .navigationTitle("Libraries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FilesLayoutToggle()
                }
            }
            .task { await load() }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && libraries.isEmpty {
            LoadingView(message: "Loading libraries…")
        } else if let errorMessage, libraries.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if libraries.isEmpty {
            EmptyStateView(title: "No shared libraries", icon: .library,
                           description: "Shared libraries for this team will appear here.")
        } else {
            ScrollView {
                switch settings.filesLayout {
                case .grid:
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(libraries) { file in
                            NavigationLink {
                                FileViewerView(file: file)
                            } label: {
                                FileCardView(file: file, baseURL: appState.client?.baseURL)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                case .list:
                    LazyVStack(spacing: 12) {
                        ForEach(libraries) { file in
                            NavigationLink {
                                FileViewerView(file: file)
                            } label: {
                                FileRowView(file: file, baseURL: appState.client?.baseURL)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            libraries = try await client.sharedLibraries(teamID: team.id)
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }
}
