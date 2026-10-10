import SwiftUI

/// Device-local recent search terms, kept per team (search is team-scoped).
/// Most recent first, case-insensitively deduped, capped at ``maxEntries``.
enum SearchHistory {
    static let maxEntries = 8

    private static func key(_ teamID: String) -> String { "search.history.\(teamID)" }

    static func entries(teamID: String, defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key(teamID)) ?? []
    }

    /// Records a term (bumping an existing case-insensitive duplicate to the front) and
    /// returns the updated list.
    @discardableResult
    static func record(_ term: String, teamID: String,
                       defaults: UserDefaults = .standard) -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries(teamID: teamID, defaults: defaults) }
        var list = entries(teamID: teamID, defaults: defaults)
        list.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        list.insert(trimmed, at: 0)
        list = Array(list.prefix(maxEntries))
        defaults.set(list, forKey: key(teamID))
        return list
    }

    @discardableResult
    static func remove(_ term: String, teamID: String,
                       defaults: UserDefaults = .standard) -> [String] {
        var list = entries(teamID: teamID, defaults: defaults)
        list.removeAll { $0 == term }
        defaults.set(list, forKey: key(teamID))
        return list
    }

    static func clear(teamID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(teamID))
    }
}

/// Client-side narrowing of search results. `search-files` only knows the term, so
/// project and library filters are applied to the returned rows.
struct SearchFilters {
    /// nil = all projects.
    var projectID: String?
    var librariesOnly = false

    var isNarrowing: Bool { projectID != nil || librariesOnly }

    func apply(_ files: [FileListItem]) -> [FileListItem] {
        files.filter { file in
            if let projectID, file.projectId != projectID { return false }
            if librariesOnly && file.isShared != true { return false }
            return true
        }
    }
}

/// Dedicated team-wide file-search screen, pushed from the dashboard's magnifier.
///
/// Owning the search field on its own screen — instead of a drawer on the dashboard —
/// keeps the navigation transitions clean: nothing ghost-paints over the menu during
/// the dashboard push, and returning from an opened file restores field, text and
/// results intact (conditionally attaching `.searchable` to the dashboard broke both).
///
/// While the field is empty, recent searches are offered; terms are recorded on search
/// submit and when a result is opened. Results can be narrowed by project and to
/// shared libraries via the toolbar filter menu.
struct TeamSearchView: View {
    let team: Team
    /// The team's active projects, used to label results with their containing project.
    let projects: [Project]

    @State private var searchText = ""
    /// Starts presented so the keyboard comes up immediately on push.
    @State private var isSearchPresented = true
    @State private var history: [String] = []
    @State private var filters = SearchFilters()

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        content
            .penpotPageBackground()
            .navigationTitle("Search files")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText,
                        isPresented: $isSearchPresented,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search files"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .onSubmit(of: .search) {
                history = SearchHistory.record(trimmedSearch, teamID: team.id)
            }
            .onAppear {
                history = SearchHistory.entries(teamID: team.id)
            }
    }

    private var filterMenu: some View {
        Menu {
            PenpotMenuChoices(selection: $filters.projectID, options:
                [(value: String?.none, label: Text("All projects"))]
                + projects.map { project in
                    (value: String?.some(project.id),
                     label: Text(project.isDefaultProject ? .appLocalized("Drafts") : project.name))
                })
            Divider()
            Button { filters.librariesOnly.toggle() } label: {
                PenpotMenuCheckLabel(label: Text("Only shared libraries"), isOn: filters.librariesOnly)
            }
        } label: {
            (filters.isNarrowing ? AppIcon.filterActive : AppIcon.filter).image
        }
        .accessibilityLabel("Filter results")
    }

    @ViewBuilder
    private var content: some View {
        if !trimmedSearch.isEmpty {
            TeamSearchResultsView(team: team, projects: projects, term: trimmedSearch,
                                  filters: $filters,
                                  onResultOpened: {
                                      history = SearchHistory.record(trimmedSearch, teamID: team.id)
                                  })
        } else if history.isEmpty {
            EmptyStateView(title: "Search files", icon: .search,
                           description: "Find files across this team's projects and drafts.")
        } else {
            historyList
        }
    }

    // Hand-built cards rather than a List (see PenpotCard). Removing a single term moved
    // from the list's swipe-to-delete into the row's context menu.
    private var historyList: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recently searched")
                            .font(.workSans(.caption, weight: .semibold))
                            .textCase(.uppercase)
                            .kerning(0.5)
                            .foregroundStyle(Color.penpotIconGray)
                        Spacer()
                        Button("Clear") {
                            SearchHistory.clear(teamID: team.id)
                            history = []
                        }
                        .font(.workSans(.caption))
                    }
                    PenpotCard {
                        ForEach(Array(history.enumerated()), id: \.element) { index, term in
                            Button {
                                searchText = term
                                history = SearchHistory.record(term, teamID: team.id)
                            } label: {
                                PenpotCardRow(showsChevron: false) {
                                    HStack(spacing: 12) {
                                        AppIcon.recent.image(size: 16)
                                            .foregroundStyle(.secondary)
                                        Text(term)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    history = SearchHistory.remove(term, teamID: team.id)
                                } label: {
                                    AppIcon.delete.destructiveLabel("Delete")
                                }
                            }
                            .penpotSwipeActions(id: term) {
                                PenpotSwipeAction("Delete", icon: .delete, isDestructive: true) {
                                    history = SearchHistory.remove(term, teamID: team.id)
                                }
                            }
                            if index < history.count - 1 {
                                PenpotCardDivider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
