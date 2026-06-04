import SwiftUI

/// Lists a team's projects, each with its files shown as cards.
struct ProjectsFilesView: View {
    @Environment(AppState.self) private var appState
    let team: Team

    @State private var sections: [ProjectSection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    struct ProjectSection: Identifiable {
        let project: Project
        var files: [FileListItem]
        var id: String { project.id }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        content
            .navigationTitle(team.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .navigationDestination(for: FileListItem.self) { file in
                FileViewerView(file: file)
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && sections.isEmpty {
            LoadingView(message: "Loading projects…")
        } else if let errorMessage, sections.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if sections.allSatisfy({ $0.files.isEmpty }) {
            EmptyStateView(title: "No files", systemImage: "doc",
                           description: "This team has no files yet.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        if !section.files.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.project.name)
                                    .font(.headline)
                                    .padding(.horizontal)
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(section.files) { file in
                                        NavigationLink(value: file) {
                                            FileCardView(file: file, baseURL: appState.client?.baseURL)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            let projects = try await client.projects(teamID: team.id)
            var newSections: [ProjectSection] = []
            try await withThrowingTaskGroup(of: (Project, [FileListItem]).self) { group in
                for project in projects {
                    group.addTask {
                        let files = try await client.projectFiles(projectID: project.id)
                        return (project, files)
                    }
                }
                for try await (project, files) in group {
                    newSections.append(ProjectSection(project: project, files: files))
                }
            }
            // Preserve the project order returned by the API.
            let order = Dictionary(uniqueKeysWithValues: projects.enumerated().map { ($0.element.id, $0.offset) })
            sections = newSections.sorted { (order[$0.project.id] ?? 0) < (order[$1.project.id] ?? 0) }
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

extension FileListItem: Hashable {
    static func == (lhs: FileListItem, rhs: FileListItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
