import SwiftUI

/// A team's dashboard as a menu of sub-screens, mirroring Penpot's web sidebar:
/// Projects, Drafts, Sources (Fonts, Libraries), and Pinned Projects.
struct TeamDashboardView: View {
    @Environment(AppState.self) private var appState
    let team: Team
    /// Called when the current user is no longer a member of `team` (left it via the
    /// members screen), so the owner of the navigation stack can pop and refresh.
    var onTeamGone: (() -> Void)? = nil

    @State private var projects: [Project] = []
    /// nil until loaded (or when the fetch failed) — the row then shows no count.
    @State private var memberCount: Int?
    /// nil until loaded (or on servers without the trash API) — the row then shows no count.
    @State private var deletedCount: Int?
    /// Font FAMILIES (matching the grouped Fonts screen), not individual variants.
    @State private var fontCount: Int?
    @State private var libraryCount: Int?
    @State private var templateCount: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// Active (non-deleted) projects in API order.
    private var activeProjects: [Project] { projects.filter { $0.deletedAt == nil } }
    private var defaultProject: Project? { activeProjects.first(where: \.isDefaultProject) }
    private var regularProjects: [Project] { activeProjects.filter { !$0.isDefaultProject } }
    private var pinnedProjects: [Project] { regularProjects.filter(\.isPinnedFlag) }

    // Search lives on its own pushed screen (TeamSearchView): a searchable drawer
    // attached here ghost-painted over the menu during the dashboard push, and
    // attaching it conditionally broke the nav bar when popping back from a result.
    var body: some View {
        content
            .navigationTitle(team.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TeamSearchView(team: team, projects: activeProjects)
                    } label: {
                        AppIcon.search.image
                    }
                    .accessibilityLabel("Search files")
                }
            }
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

                // The default "Your Penpot" team is personal — the server rejects
                // invitations for it and the web app shows no members page either.
                if team.isDefault != true {
                    NavigationLink {
                        TeamMembersView(team: team, onTeamLeft: onTeamGone)
                    } label: {
                        // Penpot's single-user glyph, not SF person.3: the SF symbol is much
                        // wider than the 18pt Penpot assets and breaks the row rhythm.
                        sourceRow(count: memberCount) { AppIcon.user.label("Members") }
                    }
                }
            }

            Section("Sources") {
                NavigationLink {
                    FontsView(team: team)
                } label: {
                    sourceRow(count: fontCount) { AppIcon.text.label("Fonts") }
                }
                NavigationLink {
                    LibrariesView(team: team)
                } label: {
                    sourceRow(count: libraryCount) { AppIcon.library.label("Libraries") }
                }
                NavigationLink {
                    TemplatesView(team: team)
                } label: {
                    sourceRow(count: templateCount) { AppIcon.template.label("Templates") }
                }
            }

            Section {
                NavigationLink {
                    DeletedFilesView(team: team, onChanged: { await load() })
                } label: {
                    sourceRow(count: deletedCount) { AppIcon.delete.label("Recently Deleted") }
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

    /// Like ``countRow`` but tolerating a not-(yet-)loaded count — the row then shows
    /// just its label.
    @ViewBuilder
    private func sourceRow<L: View>(count: Int?, @ViewBuilder label: @escaping () -> L) -> some View {
        if let count {
            countRow(count: count, label: label)
        } else {
            label()
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            // The counts are garnish — a failing fetch (flaky connection, trash needs
            // Penpot ≥ 2.12) must not blank the menu.
            async let loadedProjects = client.projects(teamID: team.id)
            async let loadedDeleted = try? client.deletedFiles(teamID: team.id)
            async let loadedFonts = try? client.fontVariants(teamID: team.id)
            async let loadedLibraries = try? client.sharedLibraries(teamID: team.id)
            async let loadedTemplates = try? client.builtinTemplates()
            if team.isDefault != true {
                // No members row for the personal team — skip the extra request there.
                async let loadedMembers = try? client.teamMembers(teamID: team.id)
                memberCount = await loadedMembers?.count
            }
            projects = try await loadedProjects
            deletedCount = await loadedDeleted?.count
            // Families, not variants — the Fonts screen groups by family.
            fontCount = await loadedFonts.map { variants in
                Set(variants.map { $0.fontId ?? $0.fontFamily }).count
            }
            libraryCount = await loadedLibraries?.count
            templateCount = await loadedTemplates?.count
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
