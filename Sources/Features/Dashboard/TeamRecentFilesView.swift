import SwiftUI

/// The full "recent files" list of a team, pushed from the dashboard's Show All row.
/// Seeded with the already-loaded rows (no loading flash); pull-to-refresh re-fetches.
struct TeamRecentFilesView: View {
    @Environment(AppState.self) private var appState
    let team: Team
    let initialFiles: [FileListItem]
    /// Active projects, used to label rows with their containing project.
    let projects: [Project]

    @State private var files: [FileListItem] = []
    @State private var errorMessage: String?

    var body: some View {
        content
            .navigationTitle("Recent Files")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if files.isEmpty { files = initialFiles } }
            .refreshable { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, files.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await reload() } }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(files) { file in
                        NavigationLink {
                            FileViewerView(file: file)
                        } label: {
                            FileRowView(file: file, baseURL: appState.client?.baseURL,
                                        subtitle: projectName(for: file))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private func projectName(for file: FileListItem) -> String? {
        guard let project = projects.first(where: { $0.id == file.projectId }) else { return nil }
        return project.isDefaultProject ? .appLocalized("Drafts") : project.name
    }

    private func reload() async {
        guard let client = appState.client else { return }
        do {
            files = try await client.recentFiles(teamID: team.id)
            errorMessage = nil
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else if files.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
