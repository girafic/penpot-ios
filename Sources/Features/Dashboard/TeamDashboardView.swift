import SwiftUI

/// A team's dashboard as a menu of sub-screens, mirroring Penpot's web sidebar:
/// Projects, Drafts, Sources (Fonts, Libraries), and Pinned Projects.
struct TeamDashboardView: View {
    @Environment(AppState.self) private var appState
    let team: Team

    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// Active (non-deleted) projects in API order.
    private var activeProjects: [Project] { projects.filter { $0.deletedAt == nil } }
    private var defaultProject: Project? { activeProjects.first(where: \.isDefaultProject) }
    private var regularProjects: [Project] { activeProjects.filter { !$0.isDefaultProject } }
    private var pinnedProjects: [Project] { regularProjects.filter(\.isPinnedFlag) }

    var body: some View {
        content
            .navigationTitle(team.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && projects.isEmpty {
            LoadingView(message: "Loading projects…")
        } else if let errorMessage, projects.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else {
            menu
        }
    }

    private var menu: some View {
        List {
            Section {
                NavigationLink {
                    ProjectsListView(team: team, onProjectsChanged: { await load() })
                } label: {
                    countRow(count: regularProjects.count) {
                        AppIcon.folder.label("Projects")
                    }
                }

                if let drafts = defaultProject {
                    NavigationLink {
                        ProjectFilesView(project: drafts)
                    } label: {
                        countRow(count: drafts.fileCount) {
                            AppIcon.document.label("Drafts")
                        }
                    }
                }
            }

            Section("Sources") {
                NavigationLink {
                    FontsView(team: team)
                } label: {
                    AppIcon.text.label("Fonts")
                }
                NavigationLink {
                    LibrariesView(team: team)
                } label: {
                    AppIcon.library.label("Libraries")
                }
                NavigationLink {
                    TemplatesView(team: team)
                } label: {
                    AppIcon.template.label("Templates")
                }
            }

            Section {
                NavigationLink {
                    DeletedFilesView(team: team, onChanged: { await load() })
                } label: {
                    AppIcon.delete.label("Recently Deleted")
                }
            }

            Section("Pinned Projects") {
                if pinnedProjects.isEmpty {
                    Text("Pinned projects will appear here")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pinnedProjects) { project in
                        NavigationLink {
                            ProjectFilesView(project: project)
                        } label: {
                            countRow(count: project.fileCount) {
                                Label {
                                    Text(project.name)
                                } icon: {
                                    AppIcon.pin.image
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// A row whose count sits at the trailing edge so the NavigationLink's
    /// disclosure chevron is drawn *after* the number (`label … 5 >`).
    private func countRow<L: View>(count: Int, @ViewBuilder label: () -> L) -> some View {
        HStack {
            label()
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            projects = try await client.projects(teamID: team.id)
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
