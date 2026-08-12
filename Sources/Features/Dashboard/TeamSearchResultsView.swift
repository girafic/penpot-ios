import SwiftUI

/// Results of a team-wide file search (`search-files`), shown in place of the team
/// dashboard menu while a search term is entered. Previous results keep rendering while
/// a refined term is in flight so the list doesn't flicker on every keystroke.
struct TeamSearchResultsView: View {
    @Environment(AppState.self) private var appState
    let team: Team
    /// The team's active projects, used to label each result with its containing project.
    let projects: [Project]
    let term: String
    /// Client-side narrowing; a binding so the empty state can offer "Reset filters".
    @Binding var filters: SearchFilters
    /// Called when the user opens a result — feeds the search history.
    var onResultOpened: () -> Void = {}

    /// nil until the first search for this screen resolved.
    @State private var results: [FileListItem]?
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        content
            .task(id: term) { await search() }
    }

    @ViewBuilder
    private var content: some View {
        if let results {
            let visible = filters.apply(results)
            if visible.isEmpty && !isSearching {
                if results.isEmpty {
                    EmptyStateView(title: "No results", icon: .document,
                                   description: "Try a different search term.")
                } else {
                    // Matches exist — the active filters hide them.
                    EmptyStateView(title: "No results", icon: .document) {
                        Button("Reset filters") { filters = SearchFilters() }
                            .buttonStyle(.penpot(.secondary, size: .compact))
                    }
                }
            } else {
                resultsList(visible)
            }
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) { Task { await search(debounce: false) } }
        } else {
            LoadingView(message: "Searching…")
        }
    }

    private func resultsList(_ files: [FileListItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if isSearching {
                    ProgressView()
                        .padding(.top, 4)
                }
                ForEach(files) { file in
                    NavigationLink {
                        FileViewerView(file: file)
                    } label: {
                        FileRowView(file: file, baseURL: appState.client?.baseURL,
                                    subtitle: projectName(for: file))
                    }
                    .buttonStyle(.plain)
                    // Rides along with the push without swallowing it — just a signal
                    // that this term earned a history entry.
                    .simultaneousGesture(TapGesture().onEnded { onResultOpened() })
                }
            }
            .padding()
        }
    }

    private func projectName(for file: FileListItem) -> String? {
        guard let project = projects.first(where: { $0.id == file.projectId }) else { return nil }
        return project.isDefaultProject ? .appLocalized("Drafts") : project.name
    }

    private func search(debounce: Bool = true) async {
        guard let client = appState.client else { return }
        if debounce {
            // Task identity (`.task(id: term)`) is the debounce: each keystroke cancels
            // the previous task while it sleeps here.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await client.searchFiles(teamID: team.id, term: term)
            guard !Task.isCancelled else { return }
            // The server returns creation order and omits `teamId` — re-stamp with the
            // current team (the viewer's canvas needs it) and sort by last modified.
            results = found
                .map { FileListItem(id: $0.id, name: $0.name, projectId: $0.projectId,
                                    teamId: team.id, modifiedAt: $0.modifiedAt,
                                    isShared: $0.isShared, thumbnailId: $0.thumbnailId) }
                .sorted { PenpotDate.sortKey($0.modifiedAt) > PenpotDate.sortKey($1.modifiedAt) }
            errorMessage = nil
        } catch is CancellationError {
            // A newer keystroke superseded this search — never paint it as an error.
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else if results == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
