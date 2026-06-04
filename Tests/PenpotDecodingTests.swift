import XCTest
@testable import PenpotiOS

final class PenpotDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.penpot.decode(T.self, from: Data(json.utf8))
    }

    func testCommentThreadDecodesKebabKeys() throws {
        let json = """
        {
          "id": "t1",
          "file-id": "f1",
          "page-id": "p1",
          "frame-id": "fr1",
          "position": {"x": 10.5, "y": 20.0},
          "content": "hello",
          "is-resolved": false,
          "count-comments": 2,
          "count-unread-comments": 1,
          "owner-id": "o1",
          "seqn": 3,
          "created-at": "2024-01-01T00:00:00.000Z"
        }
        """
        let thread = try decode(CommentThread.self, json)
        XCTAssertEqual(thread.id, "t1")
        XCTAssertEqual(thread.fileId, "f1")
        XCTAssertEqual(thread.frameId, "fr1")
        XCTAssertEqual(thread.position, Point(x: 10.5, y: 20.0))
        XCTAssertEqual(thread.isResolved, false)
        XCTAssertEqual(thread.countUnreadComments, 1)
    }

    func testThumbnailsMapDecodes() throws {
        let map = try decode([String: String].self, #"{"board1": "media-abc", "board2": "media-def"}"#)
        XCTAssertEqual(map["board1"], "media-abc")
        XCTAssertEqual(map.count, 2)
    }

    func testFileBoardExtraction() throws {
        let root = "00000000-0000-0000-0000-000000000000"
        let json = """
        {
          "id": "file1",
          "name": "Design",
          "revn": 7,
          "data": {
            "pages": ["page1"],
            "pages-index": {
              "page1": {
                "id": "page1",
                "name": "Page 1",
                "objects": {
                  "\(root)": {"type": "frame", "name": "Root", "parent-id": null},
                  "board1": {
                    "type": "frame", "name": "Board 1",
                    "parent-id": "\(root)", "frame-id": "\(root)",
                    "selrect": {"x": 0, "y": 0, "width": 100, "height": 200}
                  },
                  "rect1": {
                    "type": "rect", "name": "Rect",
                    "parent-id": "board1",
                    "selrect": {"x": 1, "y": 1, "width": 2, "height": 2}
                  }
                }
              }
            }
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        let boards = file.boards
        XCTAssertEqual(boards.count, 1)
        XCTAssertEqual(boards.first?.id, "board1")
        XCTAssertEqual(boards.first?.pageID, "page1")
        XCTAssertEqual(boards.first?.selrect, Selrect(x: 0, y: 0, width: 100, height: 200))
    }
}
