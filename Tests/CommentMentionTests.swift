import XCTest
@testable import PenpotiOS

/// Penpot's mention wire format: `@[Fullname](profile-uuid)` inside comment content.
final class CommentMentionTests: XCTestCase {
    private let uuid1 = "11111111-1111-1111-1111-111111111111"
    private let uuid2 = "22222222-2222-2222-2222-222222222222"

    func testExtractIDsDedupesInOrder() {
        let content = "Hi @[Ann Lee](\(uuid1)), ping @[Bo](\(uuid2)) and again @[Ann Lee](\(uuid1))"
        XCTAssertEqual(CommentMention.extractIDs(from: content), [uuid1, uuid2])
    }

    // A token whose id is not a UUID must be treated as literal text, not a mention.
    func testNonUUIDTokenStaysLiteral() {
        let content = "see @[docs](https://example.com) please"
        XCTAssertEqual(CommentMention.extractIDs(from: content), [])
        XCTAssertEqual(CommentMention.displayText(from: content), content)
    }

    func testDisplayTextStripsMarkup() {
        let content = "Hi @[Ann Lee](\(uuid1)), look at this"
        XCTAssertEqual(CommentMention.displayText(from: content), "Hi @Ann Lee, look at this")
    }

    func testSerializeRoundTripsThroughDisplayRepresentation() {
        let original = "Hi @[Ann Lee](\(uuid1)), ping @[Bo](\(uuid2))!"
        let display = CommentMention.displayRepresentation(of: original)
        XCTAssertEqual(display.text, "Hi @Ann Lee, ping @Bo!")
        XCTAssertEqual(display.mentions, [.init(name: "Ann Lee", id: uuid1),
                                          .init(name: "Bo", id: uuid2)])
        XCTAssertEqual(CommentMention.serialize(display: display.text, mentions: display.mentions),
                       original)
    }

    // Longest names serialize first so "@Ann Lee" can't be half-eaten by a pick named "@Ann".
    func testSerializePrefersLongestName() {
        let picks: [CommentMention.Pick] = [.init(name: "Ann", id: uuid1),
                                            .init(name: "Ann Lee", id: uuid2)]
        XCTAssertEqual(CommentMention.serialize(display: "cc @Ann Lee and @Ann", mentions: picks),
                       "cc @[Ann Lee](\(uuid2)) and @[Ann](\(uuid1))")
    }

    // Picks whose @Name was deleted from the text must not resurface on send.
    func testSerializeDropsRemovedMentions() {
        let picks: [CommentMention.Pick] = [.init(name: "Ann", id: uuid1)]
        XCTAssertEqual(CommentMention.serialize(display: "no mentions left", mentions: picks),
                       "no mentions left")
    }

    func testAttributedStringHighlightsMentionRuns() {
        let content = "Hi @[Ann](\(uuid1))!"
        let attributed = CommentMention.attributedString(from: content)
        XCTAssertEqual(String(attributed.characters), "Hi @Ann!")
        let highlighted = attributed.runs.filter { $0.foregroundColor != nil }
        XCTAssertEqual(highlighted.count, 1)
    }

    // MARK: Filters (web semantics)

    private func thread(_ json: String) throws -> CommentThread {
        try JSONDecoder.penpot.decode(CommentThread.self, from: Data(json.utf8))
    }

    func testFiltersMatchWebSemantics() throws {
        let me = uuid1
        let mine = try thread(#"{"id": "t1", "participants": ["\#(uuid1)"], "isResolved": false}"#)
        let mentionsMe = try thread(#"{"id": "t2", "mentions": ["\#(uuid1)"], "isResolved": false}"#)
        let foreign = try thread(#"{"id": "t3", "participants": ["\#(uuid2)"], "isResolved": false}"#)
        let resolved = try thread(#"{"id": "t4", "isResolved": true}"#)
        let all = [mine, mentionsMe, foreign, resolved]

        let hideResolved = CommentFilters(mode: .all, showResolved: false)
        XCTAssertEqual(hideResolved.apply(all, profileID: me).map(\.id), ["t1", "t2", "t3"])

        let showResolved = CommentFilters(mode: .all, showResolved: true)
        XCTAssertEqual(showResolved.apply(all, profileID: me).count, 4)

        let yours = CommentFilters(mode: .yours, showResolved: false)
        XCTAssertEqual(yours.apply(all, profileID: me).map(\.id), ["t1"])
        // Without a profile id, "yours" matches nothing rather than everything.
        XCTAssertTrue(yours.apply(all, profileID: nil).isEmpty)

        let mentions = CommentFilters(mode: .mentions, showResolved: false)
        XCTAssertEqual(mentions.apply(all, profileID: me).map(\.id), ["t2"])
    }

    // Payloads without `participants` fall back to the owner for "yours".
    func testYoursFallsBackToOwner() throws {
        let owned = try thread(#"{"id": "t1", "ownerId": "\#(uuid1)"}"#)
        let filters = CommentFilters(mode: .yours, showResolved: true)
        XCTAssertEqual(filters.apply([owned], profileID: uuid1).count, 1)
        XCTAssertTrue(filters.apply([owned], profileID: uuid2).isEmpty)
    }

    // A malformed participants/mentions shape must not sink the whole thread row.
    func testMalformedParticipantsDecodeDefensively() throws {
        let decoded = try thread(#"{"id": "t1", "participants": {"weird": true}, "mentions": 7}"#)
        XCTAssertEqual(decoded.id, "t1")
        XCTAssertNil(decoded.participants)
        XCTAssertNil(decoded.mentions)
    }
}
