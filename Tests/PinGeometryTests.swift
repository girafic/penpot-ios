import XCTest
@testable import PenpotiOS

final class PinGeometryTests: XCTestCase {
    private let board = Selrect(x: 100, y: 50, width: 400, height: 200)

    func testNormalizedPosition() {
        let point = Point(x: 300, y: 150)
        let norm = PinMath.normalized(position: point, in: board)
        XCTAssertEqual(norm.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(norm.y, 0.5, accuracy: 0.0001)
    }

    func testNormalizedRoundTrip() {
        let original = Point(x: 220, y: 90)
        let norm = PinMath.normalized(position: original, in: board)
        let back = PinMath.canvasPosition(normalized: norm, in: board)
        XCTAssertEqual(back.x, original.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, original.y, accuracy: 0.0001)
    }

    func testZeroSizeIsSafe() {
        let degenerate = Selrect(x: 0, y: 0, width: 0, height: 0)
        let norm = PinMath.normalized(position: Point(x: 5, y: 5), in: degenerate)
        XCTAssertEqual(norm, .zero)
    }

    func testFittedSizePreservesAspectRatio() {
        let fitted = PinMath.fittedSize(selrect: board, in: CGSize(width: 200, height: 200))
        // 400x200 fit into 200x200 → width-constrained → 200x100.
        XCTAssertEqual(fitted.width, 200, accuracy: 0.0001)
        XCTAssertEqual(fitted.height, 100, accuracy: 0.0001)
    }

    // A comment placed on the page canvas belongs to the topmost board under it, or to the
    // page's root frame outside every board (as in Penpot).
    @MainActor
    func testCanvasCommentGoesToTheTopmostBoardUnderIt() {
        let lower = Board(id: "lower", pageID: "p", name: "Lower", selrect: Selrect(x: 0, y: 0, width: 200, height: 200))
        let upper = Board(id: "upper", pageID: "p", name: "Upper", selrect: Selrect(x: 100, y: 100, width: 200, height: 200))
        let layers = ["lower": 0, "upper": 3]
        XCTAssertEqual(PageCanvasUIView.frameID(at: CGPoint(x: 150, y: 150), boards: [upper, lower], layers: layers), "upper")
        XCTAssertEqual(PageCanvasUIView.frameID(at: CGPoint(x: 50, y: 50), boards: [upper, lower], layers: layers), "lower")
        XCTAssertEqual(PageCanvasUIView.frameID(at: CGPoint(x: 500, y: 500), boards: [upper, lower], layers: layers),
                       Board.rootFrameID)
    }

    // Penpot's editor puts a comment on the topmost frame under the click, often one nested
    // in a board (a table cell). Those show on the board they lie in; threads on another
    // root board or on the page itself don't.
    func testThreadsOnNestedFramesShowOnTheirBoard() throws {
        func thread(frame: String, x: Double, y: Double, page: String = "p") throws -> CommentThread {
            let json = #"{"id": "t", "pageId": "\#(page)", "frameId": "\#(frame)", "position": {"x": \#(x), "y": \#(y)}}"#
            return try JSONDecoder.penpot.decode(CommentThread.self, from: Data(json.utf8))
        }
        let detail = Board(id: "board", pageID: "p", name: "Board", selrect: board)
        let roots: Set<String> = ["board", "neighbour"]
        XCTAssertTrue(PinMath.thread(try thread(frame: "board", x: 900, y: 900), isOn: detail, pageBoardIDs: roots),
                      "its own threads, wherever they sit")
        XCTAssertTrue(PinMath.thread(try thread(frame: "cell", x: 150, y: 80), isOn: detail, pageBoardIDs: roots))
        XCTAssertFalse(PinMath.thread(try thread(frame: "cell", x: 900, y: 80), isOn: detail, pageBoardIDs: roots),
                       "a nested frame elsewhere")
        XCTAssertFalse(PinMath.thread(try thread(frame: "neighbour", x: 150, y: 80), isOn: detail, pageBoardIDs: roots))
        XCTAssertFalse(PinMath.thread(try thread(frame: Board.rootFrameID, x: 150, y: 80), isOn: detail, pageBoardIDs: roots))
        XCTAssertFalse(PinMath.thread(try thread(frame: "cell", x: 150, y: 80, page: "other"), isOn: detail, pageBoardIDs: roots))
    }
}
