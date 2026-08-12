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
    /// The team's recently modified files; empty hides the section.
    @State private var recentFiles: [FileListItem] = []
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
            .penpotPageBackground()
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

    // Hand-built cards rather than a List: Penpot's tonal panel can't be drawn behind a
    // List section (see PenpotCard).
    private var menu: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !recentFiles.isEmpty {
                    recentFilesSection
                }

                PenpotCard {
                    NavigationLink {
                        ProjectsListView(team: team, onProjectsChanged: { await load() })
                    } label: {
                        countRow(count: regularProjects.count) {
                            AppIcon.folder.label("Projects")
                        }
                    }
                    .buttonStyle(.plain)

                    if let drafts = defaultProject {
                        PenpotCardDivider()
                        NavigationLink {
                            ProjectFilesView(project: drafts)
                        } label: {
                            countRow(count: drafts.fileCount) {
                                AppIcon.document.label("Drafts")
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // The default "Your Penpot" team is personal — the server rejects
                    // invitations for it and the web app shows no members page either.
                    if team.isDefault != true {
                        PenpotCardDivider()
                        NavigationLink {
                            TeamMembersView(team: team, onTeamLeft: onTeamGone)
                        } label: {
                            // Penpot's single-user glyph, not SF person.3: the SF symbol is much
                            // wider than the 18pt Penpot assets and breaks the row rhythm.
                            sourceRow(count: memberCount) { AppIcon.user.label("Members") }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Sources"))
                    PenpotCard {
                        NavigationLink {
                            FontsView(team: team)
                        } label: {
                            sourceRow(count: fontCount) { AppIcon.text.label("Fonts") }
                        }
                        .buttonStyle(.plain)
                        PenpotCardDivider()
                        NavigationLink {
                            LibrariesView(team: team)
                        } label: {
                            sourceRow(count: libraryCount) { AppIcon.library.label("Libraries") }
                        }
                        .buttonStyle(.plain)
                        PenpotCardDivider()
                        NavigationLink {
                            TemplatesView(team: team)
                        } label: {
                            sourceRow(count: templateCount) { AppIcon.template.label("Templates") }
                        }
                        .buttonStyle(.plain)
                    }
                }

                PenpotCard {
                    NavigationLink {
                        DeletedFilesView(team: team, onChanged: { await load() })
                    } label: {
                        sourceRow(count: deletedCount) { AppIcon.delete.label("Recently Deleted") }
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Pinned Projects"))
                    PenpotCard {
                        if pinnedProjects.isEmpty {
                            PenpotCardRow(showsChevron: false) {
                                Text("Pinned projects will appear here")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(Array(pinnedProjects.enumerated()), id: \.element.id) { index, project in
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
                                .buttonStyle(.plain)
                                if index < pinnedProjects.count - 1 {
                                    PenpotCardDivider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// The recent files strip stays card-less: every ``FileCardView`` already carries its
    /// own surface, so a panel behind them would read as a card inside a card.
    private var recentFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(Text("Recent Files"))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(recentFiles.prefix(8)) { file in
                        NavigationLink {
                            FileViewerView(file: file)
                        } label: {
                            FileCardView(file: file, baseURL: appState.client?.baseURL)
                                .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if recentFiles.count > 8 {
                PenpotCard {
                    NavigationLink {
                        TeamRecentFilesView(team: team, initialFiles: recentFiles,
                                            projects: activeProjects)
                    } label: {
                        countRow(count: recentFiles.count) {
                            Text("Show All")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A section title above a card, in Penpot's uppercase label style.
    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.workSans(.caption, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Color.penpotIconGray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A card row whose count sits at the trailing edge so the row's disclosure chevron
    /// is drawn *after* the number (`label … 5 >`).
    private func countRow<L: View>(count: Int, @ViewBuilder label: () -> L) -> some View {
        PenpotCardRow {
            label()
        } trailing: {
            Text("\(count)")
        }
    }

    /// Like ``countRow`` but tolerating a not-(yet-)loaded count — the row then shows
    /// just its label.
    @ViewBuilder
    private func sourceRow<L: View>(count: Int?, @ViewBuilder label: @escaping () -> L) -> some View {
        if let count {
            countRow(count: count, label: label)
        } else {
            PenpotCardRow { label() }
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
            async let loadedRecent = try? client.recentFiles(teamID: team.id)
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
            recentFiles = await loadedRecent ?? []
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
