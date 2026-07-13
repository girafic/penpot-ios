import XCTest
@testable import PenpotiOS

final class PenpotDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.penpot.decode(T.self, from: Data(json.utf8))
    }

    // Penpot's JSON API returns camelCase keys (e.g. fileId, isResolved), not kebab-case.
    func testCommentThreadDecodesCamelKeys() throws {
        let json = """
        {
          "id": "t1",
          "fileId": "f1",
          "pageId": "p1",
          "frameId": "fr1",
          "position": {"x": 10.5, "y": 20.0},
          "content": "hello",
          "isResolved": false,
          "countComments": 2,
          "countUnreadComments": 1,
          "ownerId": "o1",
          "seqn": 3,
          "createdAt": "2024-01-01T00:00:00.000Z"
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

    // Verbatim payload shape from `get-unread-comment-threads`: the server joins the file and
    // the owner onto each thread, which is what lets the inbox render a thread outside its file.
    func testUnreadCommentThreadDecodesJoinedFileAndOwner() throws {
        let json = """
        {
          "pageName": "Design",
          "teamId": "team-1",
          "ownerFullname": "Stas",
          "fileId": "file-1",
          "participants": ["p1"],
          "content": "Test",
          "countUnreadComments": 2,
          "ownerPhotoId": "photo-1",
          "countComments": 3,
          "modifiedAt": "2026-06-26T11:46:32.296501Z",
          "pageId": "page-1",
          "id": "thread-1",
          "fileName": "Plants-app",
          "seqn": 1,
          "isResolved": false,
          "ownerId": "owner-1",
          "position": {"x": 1525.75, "y": 170.19},
          "frameId": "frame-1",
          "projectId": "project-1",
          "createdAt": "2026-06-26T11:46:32.296501Z",
          "ownerEmail": "stas@girafic.de"
        }
        """
        let thread = try decode(CommentThread.self, json)
        XCTAssertEqual(thread.fileName, "Plants-app")
        XCTAssertEqual(thread.teamId, "team-1")
        XCTAssertEqual(thread.ownerFullname, "Stas")
        XCTAssertEqual(thread.ownerPhotoId, "photo-1")
        XCTAssertEqual(thread.modifiedAt, "2026-06-26T11:46:32.296501Z")
        XCTAssertEqual(thread.unreadCount, 2)
    }

    // A thread without an unread count must not report unread comments.
    func testUnreadCountDefaultsToZero() throws {
        let thread = try decode(CommentThread.self, #"{"id": "t1"}"#)
        XCTAssertEqual(thread.unreadCount, 0)
    }

    func testThumbnailsMapDecodes() throws {
        let map = try decode([String: String].self, #"{"board1": "media-abc", "board2": "media-def"}"#)
        XCTAssertEqual(map["board1"], "media-abc")
        XCTAssertEqual(map.count, 2)
    }

    // Penpot keys object thumbnails by "<file-id>/<page-id>/<frame-id>/frame"; we re-key by frame id.
    func testFrameThumbnailsRekeysCompositeKeys() {
        let fid = "40b5cf7c-e089-81bd-8005-45ce0de05bc7"
        let pid = "40b5cf7c-e089-81bd-8005-45ce0de05bc8"
        let frame = "17dd8fce-c39e-804b-8005-c2bc12896b5d"
        let mapped = PenpotClient.frameThumbnails(from: [
            "\(fid)/\(pid)/\(frame)/frame": "media-1",
            "legacy-bare-frame-id": "media-2",
        ])
        XCTAssertEqual(mapped[frame], "media-1")
        XCTAssertEqual(mapped["legacy-bare-frame-id"], "media-2")
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
            "pagesIndex": {
              "page1": {
                "id": "page1",
                "name": "Page 1",
                "objects": {
                  "\(root)": {"type": "frame", "name": "Root", "parentId": null},
                  "board1": {
                    "type": "frame", "name": "Board 1",
                    "parentId": "\(root)", "frameId": "\(root)",
                    "selrect": {"x": 0, "y": 0, "width": 100, "height": 200}
                  },
                  "rect1": {
                    "type": "rect", "name": "Rect",
                    "parentId": "board1",
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

    func testFilePagesPreserveOrderAndBoards() throws {
        let root = "00000000-0000-0000-0000-000000000000"
        let json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["pageB", "pageA"],
            "pagesIndex": {
              "pageA": {"id": "pageA", "name": "Alpha", "objects": {
                "\(root)": {"type": "frame", "name": "Root", "parentId": null},
                "a1": {"type": "frame", "name": "A1", "parentId": "\(root)", "frameId": "\(root)",
                       "selrect": {"x": 0, "y": 0, "width": 10, "height": 10}}
              }},
              "pageB": {"id": "pageB", "name": "Beta", "objects": {
                "\(root)": {"type": "frame", "name": "Root", "parentId": null},
                "b1": {"type": "frame", "name": "B1", "parentId": "\(root)", "frameId": "\(root)",
                       "selrect": {"x": 0, "y": 0, "width": 10, "height": 10}},
                "b2": {"type": "frame", "name": "B2", "parentId": "\(root)", "frameId": "\(root)",
                       "selrect": {"x": 0, "y": 20, "width": 10, "height": 10}}
              }}
            }
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        // Pages follow data.pages order (pageB before pageA), not dictionary order.
        XCTAssertEqual(file.pages.map(\.name), ["Beta", "Alpha"])
        XCTAssertEqual(file.pages.first?.boards.count, 2)
        XCTAssertEqual(file.pages.last?.boards.count, 1)
        XCTAssertEqual(file.boards.count, 3)
    }
}
