import XCTest
@testable import PenpotiOS

final class SearchHistoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private let teamID = "team-1"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.search.history")
        defaults.removePersistentDomain(forName: "test.search.history")
    }

    func testRecordDedupesBumpsAndCaps() {
        SearchHistory.record("Blender", teamID: teamID, defaults: defaults)
        SearchHistory.record("Icons", teamID: teamID, defaults: defaults)
        // Case-insensitive duplicate bumps to the front instead of duplicating.
        let list = SearchHistory.record("blender", teamID: teamID, defaults: defaults)
        XCTAssertEqual(list, ["blender", "Icons"])

        // Whitespace-only terms are ignored.
        XCTAssertEqual(SearchHistory.record("   ", teamID: teamID, defaults: defaults),
                       ["blender", "Icons"])

        for index in 0..<10 {
            SearchHistory.record("term-\(index)", teamID: teamID, defaults: defaults)
        }
        let capped = SearchHistory.entries(teamID: teamID, defaults: defaults)
        XCTAssertEqual(capped.count, SearchHistory.maxEntries)
        XCTAssertEqual(capped.first, "term-9")
    }

    func testRemoveAndClear() {
        SearchHistory.record("a", teamID: teamID, defaults: defaults)
        SearchHistory.record("b", teamID: teamID, defaults: defaults)
        XCTAssertEqual(SearchHistory.remove("a", teamID: teamID, defaults: defaults), ["b"])
        SearchHistory.clear(teamID: teamID, defaults: defaults)
        XCTAssertTrue(SearchHistory.entries(teamID: teamID, defaults: defaults).isEmpty)
    }

    // History is scoped per team.
    func testTeamsAreIsolated() {
        SearchHistory.record("a", teamID: "t1", defaults: defaults)
        XCTAssertTrue(SearchHistory.entries(teamID: "t2", defaults: defaults).isEmpty)
    }

    // MARK: Search filters (client-side — search-files only knows the term)

    func testSearchFiltersApply() {
        func file(_ id: String, project: String, shared: Bool) -> FileListItem {
            FileListItem(id: id, name: id, projectId: project, teamId: "t",
                         modifiedAt: nil, isShared: shared, thumbnailId: nil)
        }
        let files = [file("a", project: "p1", shared: false),
                     file("b", project: "p1", shared: true),
                     file("c", project: "p2", shared: false)]

        XCTAssertEqual(SearchFilters().apply(files).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(SearchFilters(projectID: "p1").apply(files).map(\.id), ["a", "b"])
        XCTAssertEqual(SearchFilters(librariesOnly: true).apply(files).map(\.id), ["b"])
        XCTAssertEqual(SearchFilters(projectID: "p2", librariesOnly: true).apply(files).map(\.id), [])
        XCTAssertFalse(SearchFilters().isNarrowing)
        XCTAssertTrue(SearchFilters(projectID: "p1").isNarrowing)
        XCTAssertTrue(SearchFilters(librariesOnly: true).isNarrowing)
    }
}
