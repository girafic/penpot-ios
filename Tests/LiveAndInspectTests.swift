import XCTest
@testable import PenpotiOS

/// Penpot's notification websocket as the app reads it (verbose transit, the events it
/// cares about), the fingerprints that tell changed boards, and the Inspect mode's picking.
final class LiveAndInspectTests: XCTestCase {
    private let server = URL(string: "https://penpot.test")!
    private let root = PenpotSVG.rootID

    // MARK: - Websocket

    func testSocketURLFollowsTheServerScheme() throws {
        let https = try XCTUnwrap(PenpotNotifications.socketURL(server: URL(string: "https://design.penpot.app")!,
                                                                sessionID: "s1"))
        XCTAssertEqual(https.absoluteString, "wss://design.penpot.app/ws/notifications?session-id=s1")
        let http = try XCTUnwrap(PenpotNotifications.socketURL(server: URL(string: "http://localhost:3450/")!,
                                                               sessionID: "s1"))
        XCTAssertEqual(http.absoluteString, "ws://localhost:3450/ws/notifications?session-id=s1")
    }

    func testSubscribeMessageIsVerboseTransit() throws {
        let text = PenpotNotifications.encode(["type": .keyword("subscribe-file"), "file-id": .uuid("f1")])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String])
        XCTAssertEqual(json, ["~:type": "~:subscribe-file", "~:file-id": "~uf1"])
    }

    /// A `file-change` as the server writes it (`json-verbose`): tagged shapes, uuid keys,
    /// escaped strings.
    func testFileChangeNamesPagesAndShapes() throws {
        let message = """
        {"~:type":"~:file-change","~:file-id":"~uf1","~:session-id":"~us2","~:revn":42,
         "~:changes":[
           {"~:type":"~:mod-obj","~:page-id":"~up1","~:id":"~ushape","~:operations":[]},
           {"~:type":"~:add-obj","~:page-id":"~up1","~:id":"~unew","~:parent-id":"~uboard",
            "~:frame-id":"~uboard","~:obj":{"~#shape":{"~:name":"~~tilde","~:type":"~:rect"}}},
           {"~:type":"~:mov-objects","~:page-id":"~up2","~:parent-id":"~ugroup","~:shapes":["~ua","~ub"]}
         ]}
        """
        guard case .fileChange(let revn, let pages, let objects, let pagesChanged)? =
                PenpotNotifications.event(from: message, fileID: "f1") else {
            return XCTFail("not a file change")
        }
        XCTAssertEqual(revn, 42)
        XCTAssertEqual(pages, ["p1", "p2"])
        XCTAssertEqual(objects, ["shape", "new", "board", "group", "a", "b"])
        XCTAssertFalse(pagesChanged)
    }

    func testPageChangesAskForTheWholeFile() throws {
        let message = #"{"~:type":"~:file-change","~:file-id":"~uf1","~:revn":3,"~:changes":[{"~:type":"~:add-page","~:id":"~up9","~:name":"New"}]}"#
        guard case .fileChange(_, let pages, _, let pagesChanged)? =
                PenpotNotifications.event(from: message, fileID: "f1") else {
            return XCTFail("not a file change")
        }
        XCTAssertTrue(pagesChanged)
        XCTAssertEqual(pages, ["p9"])
    }

    func testPresenceAndOtherFiles() {
        let join = #"{"~:type":"~:join-file","~:file-id":"~uf1","~:session-id":"~us2","~:profile-id":"~uu2"}"#
        guard case .present(let session, let profile)? = PenpotNotifications.event(from: join, fileID: "f1") else {
            return XCTFail("no presence")
        }
        XCTAssertEqual(session, "s2")
        XCTAssertEqual(profile, "u2")
        let leave = #"{"~:type":"~:disconnect","~:profile-id":"~uu2","~:session-id":"~us2"}"#
        guard case .left("s2")? = PenpotNotifications.event(from: leave, fileID: "f1") else {
            return XCTFail("no leave")
        }
        XCTAssertNil(PenpotNotifications.event(from: join, fileID: "other"))
        XCTAssertNil(PenpotNotifications.event(from: #"{"~:type":"~:pointer-update","~:file-id":"~uf1"}"#, fileID: "f1"))
    }

    /// A `file-change` as a Penpot devenv (2.19) sent it after a fill was changed.
    func testFileChangeFromPenpot() {
        let message = ##"{"~:type":"~:file-change","~:profile-id":"~u6ef122f5-06d2-8182-8009-02a93e9cab41","~:file-id":"~u6ef122f5-06d2-8182-8009-02a955d542da","~:session-id":"~u58e8e0d6-c157-4cb4-8807-1c486f11f768","~:revn":20,"~:vern":0,"~:changes":[{"~:type":"~:mod-obj","~:page-id":"~u43a47cf1-669c-80f7-8004-18ac29b8f1f4","~:id":"~u43a47cf1-669c-80f7-8004-18ac2dc275aa","~:operations":[{"~:type":"~:set","~:attr":"~:fills","~:val":[{"~:fill-color":"#ff3366","~:fill-opacity":1}]}]}],"~:topic":"~u6ef122f5-06d2-8182-8009-02a955d542da"}"##
        guard case .fileChange(let revn, let pages, let objects, false)? =
                PenpotNotifications.event(from: message, fileID: "6ef122f5-06d2-8182-8009-02a955d542da") else {
            return XCTFail("not a file change")
        }
        XCTAssertEqual(revn, 20)
        XCTAssertEqual(pages, ["43a47cf1-669c-80f7-8004-18ac29b8f1f4"])
        XCTAssertEqual(objects, ["43a47cf1-669c-80f7-8004-18ac2dc275aa"])
    }

    // MARK: - Changed boards

    /// A change names shapes; their root boards are the changed ones. A shape that is gone
    /// (deleted) names no board.
    func testChangedShapesNameTheirBoards() throws {
        let page: [String: Any] = ["id": "p", "name": "Page", "objects": [
            root: ["id": root, "type": "frame", "parentId": root, "shapes": ["a", "b"]],
            "a": ["id": "a", "type": "frame", "name": "A", "parentId": root, "frameId": root, "shapes": ["g"],
                  "selrect": ["x": 0, "y": 0, "width": 10, "height": 10]],
            "g": ["id": "g", "type": "group", "parentId": "a", "frameId": "a", "shapes": ["r"]],
            "r": ["id": "r", "type": "rect", "parentId": "g", "frameId": "a"],
            "b": ["id": "b", "type": "frame", "name": "B", "parentId": root, "frameId": root, "shapes": [],
                  "selrect": ["x": 20, "y": 0, "width": 10, "height": 10]],
        ]]
        let data = try JSONSerialization.data(withJSONObject: page)
        let state = try LiveFile.read(data, pageID: "p", objects: ["r", "p"])
        XCTAssertEqual(state.touched, ["a"])
        XCTAssertFalse(state.lostShapes)
        XCTAssertEqual(Set(state.fingerprints.keys), ["a", "b"])
        XCTAssertTrue(try LiveFile.read(data, pageID: "p", objects: ["gone"]).lostShapes)
    }

    func testFingerprintsChangeOnlyWithTheirBoard() {
        var objects: [String: [String: Any]] = [
            "a": ["id": "a", "type": "frame", "shapes": ["a1"]],
            "a1": ["id": "a1", "type": "rect", "fills": [["fillColor": "#ff0000"]]],
            "b": ["id": "b", "type": "frame", "shapes": []],
        ]
        let before = LiveFile.fingerprints(of: ["a", "b"], objects: objects)
        objects["a1"]?["fills"] = [["fillColor": "#00ff00"]]
        let after = LiveFile.fingerprints(of: ["a", "b"], objects: objects)
        XCTAssertNotEqual(before["a"], after["a"])
        XCTAssertEqual(before["b"], after["b"])
    }

    // MARK: - Inspect picking

    private func inspectBoard(_ shapes: [[String: Any]], boardChildren: [String]) throws -> InspectBoard {
        var objects: [String: Any] = [
            root: ["id": root, "type": "frame", "parentId": root, "shapes": ["board"]],
            "board": ["id": "board", "type": "frame", "name": "Board", "parentId": root,
                      "selrect": ["x": 100, "y": 100, "width": 400, "height": 300],
                      "shapes": boardChildren],
        ]
        for shape in shapes { objects[shape["id"] as! String] = shape }
        let data = try JSONSerialization.data(withJSONObject: ["id": "page", "objects": objects])
        let page = try PenpotSVG.Page(pageJSON: data, server: server)
        return try XCTUnwrap(InspectBoard(page: page, boardID: "board"))
    }

    private func rect(_ id: String, parent: String, x: Double, y: Double, w: Double, h: Double,
                      extra: [String: Any] = [:]) -> [String: Any] {
        var shape: [String: Any] = ["id": id, "type": "rect", "name": id, "parentId": parent,
                                    "selrect": ["x": x, "y": y, "width": w, "height": h]]
        shape.merge(extra) { $1 }
        return shape
    }

    /// The innermost shape under the finger, the topmost first; groups only through their
    /// children; empty board space picks the board; hidden shapes and the board's clip.
    func testPickingFollowsPenpotsHover() throws {
        let board = try inspectBoard([
            rect("bottom", parent: "board", x: 100, y: 100, w: 200, h: 200),
            ["id": "group", "type": "group", "name": "group", "parentId": "board", "shapes": ["inner"],
             "selrect": ["x": 150, "y": 150, "width": 300, "height": 100]],
            rect("inner", parent: "group", x: 150, y: 150, w: 50, h: 50),
            rect("hidden", parent: "board", x: 100, y: 100, w: 400, h: 300, extra: ["hidden": true]),
            rect("outside", parent: "board", x: 600, y: 100, w: 50, h: 50),
        ], boardChildren: ["bottom", "group", "hidden", "outside"])

        XCTAssertEqual(board.shape(at: CGPoint(x: 160, y: 160)), "inner", "the group's child, over the rect")
        XCTAssertEqual(board.shape(at: CGPoint(x: 400, y: 200)), "board", "inside the group's box but no child")
        XCTAssertEqual(board.shape(at: CGPoint(x: 120, y: 120)), "bottom")
        XCTAssertEqual(board.shape(at: CGPoint(x: 450, y: 350)), "board")
        XCTAssertNil(board.shape(at: CGPoint(x: 620, y: 120)), "clipped by the board")
        XCTAssertEqual(board.path(to: "inner"), ["board", "group", "inner"])
    }

    func testRotatedShapesPickByTheirCorners() throws {
        // A 100×20 bar turned 90° around its centre (250, 210): it stands upright.
        let points: [[String: Double]] = [["x": 260, "y": 160], ["x": 260, "y": 260],
                                          ["x": 240, "y": 260], ["x": 240, "y": 160]]
        let board = try inspectBoard([
            rect("bar", parent: "board", x: 200, y: 200, w: 100, h: 20, extra: ["points": points]),
        ], boardChildren: ["bar"])
        XCTAssertEqual(board.shape(at: CGPoint(x: 250, y: 170)), "bar")
        XCTAssertEqual(board.shape(at: CGPoint(x: 210, y: 210)), "board", "where the unturned bar would be")
        XCTAssertEqual(board.bounds("bar"), CGRect(x: 240, y: 160, width: 20, height: 100))
    }

    func testTextRunsMergeEqualStyles() throws {
        let content: [String: Any] = ["type": "root", "children": [[
            "type": "paragraph-set", "children": [
                ["type": "paragraph", "fontSize": "14", "children": [
                    ["text": "Hello ", "fontFamily": "Work Sans", "fontId": "gfont-work-sans", "fontWeight": "700",
                     "fills": [["fillColor": "#000000", "fillOpacity": 1]]],
                    ["text": "world", "fontFamily": "Work Sans", "fontId": "gfont-work-sans", "fontWeight": "700",
                     "fills": [["fillColor": "#000000", "fillOpacity": 1]]],
                ]],
                ["type": "paragraph", "fontSize": "14", "children": [
                    ["text": "again", "fontWeight": "400", "fills": [["fillColor": "#ff0000", "fillOpacity": 0.5]]],
                ]],
            ],
        ]]]
        let board = try inspectBoard([
            ["id": "t", "type": "text", "name": "t", "parentId": "board", "content": content,
             "selrect": ["x": 100, "y": 100, "width": 100, "height": 40]],
        ], boardChildren: ["t"])
        let runs = board.textRuns("t")
        XCTAssertEqual(runs.map(\.text), ["Hello world", "again"])
        XCTAssertEqual(runs.first?.fontName, "Work Sans")
        XCTAssertEqual(runs.first?.fontWeight, "700")
        XCTAssertEqual(runs.last?.fontName, "Source Sans Pro", "Penpot's default font")
        XCTAssertEqual(runs.last?.fills, [.init(kind: .color("#ff0000"), opacity: 0.5)])
    }

    func testNumbersFormatLikePenpot() {
        XCTAssertEqual(InspectBoard.trim(12), "12")
        XCTAssertEqual(InspectBoard.trim(12.5), "12.5")
        XCTAssertEqual(InspectBoard.trim(12.3456), "12.35")
        XCTAssertEqual(InspectBoard.trim(-0.004), "0")
    }
}
