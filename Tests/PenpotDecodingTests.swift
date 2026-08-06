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
          "ownerFullname": "Test User",
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
          "ownerEmail": "owner@example.com"
        }
        """
        let thread = try decode(CommentThread.self, json)
        XCTAssertEqual(thread.fileName, "Plants-app")
        XCTAssertEqual(thread.teamId, "team-1")
        XCTAssertEqual(thread.ownerFullname, "Test User")
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

    // A page whose only content is drawn directly on the canvas (non-frame children of
    // the root frame) must report canvas objects so the file isn't presented as empty.
    // The root frame is self-parented here, as in real Penpot payloads — it must not
    // count itself.
    func testLooseCanvasShapesCountedWhenNoBoards() throws {
        let root = "00000000-0000-0000-0000-000000000000"
        let json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["page1"],
            "pagesIndex": {
              "page1": {"id": "page1", "name": "Page 1", "objects": {
                "\(root)": {"type": "frame", "name": "Root", "parentId": "\(root)", "frameId": "\(root)"},
                "rect1": {"type": "rect", "name": "Rect", "parentId": "\(root)", "frameId": "\(root)",
                          "selrect": {"x": 0, "y": 0, "width": 5, "height": 5}}
              }}
            }
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        XCTAssertEqual(file.boards.count, 0)
        XCTAssertEqual(file.pages.first?.canvasObjectCount, 1)
        XCTAssertEqual(file.pages.first?.hasContent, true)
    }

    // Shapes nested inside a board must not count; only direct children of the root do.
    func testCanvasObjectCountIgnoresBoardChildren() throws {
        let root = "00000000-0000-0000-0000-000000000000"
        let json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["page1"],
            "pagesIndex": {
              "page1": {"id": "page1", "name": "Page 1", "objects": {
                "\(root)": {"type": "frame", "name": "Root", "parentId": "\(root)"},
                "board1": {"type": "frame", "name": "Board 1", "parentId": "\(root)", "frameId": "\(root)",
                           "selrect": {"x": 0, "y": 0, "width": 100, "height": 200}},
                "rect1": {"type": "rect", "name": "Rect", "parentId": "board1",
                          "selrect": {"x": 1, "y": 1, "width": 2, "height": 2}},
                "text1": {"type": "text", "name": "Text", "parentId": "\(root)", "frameId": "\(root)",
                          "selrect": {"x": 10, "y": 10, "width": 20, "height": 5}}
              }}
            }
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        XCTAssertEqual(file.pages.first?.boards.count, 1)
        XCTAssertEqual(file.pages.first?.canvasObjectCount, 1)
    }

    // A root-level frame with no decodable selrect can't be a board thumbnail but is
    // still content — it must land in the canvas count instead of vanishing.
    func testFrameWithoutSelrectCountsAsCanvasObject() throws {
        let root = "00000000-0000-0000-0000-000000000000"
        let json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["page1"],
            "pagesIndex": {
              "page1": {"id": "page1", "name": "Page 1", "objects": {
                "\(root)": {"type": "frame", "name": "Root", "parentId": "\(root)"},
                "frame1": {"type": "frame", "name": "Frame", "parentId": "\(root)", "frameId": "\(root)"}
              }}
            }
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        XCTAssertEqual(file.boards.count, 0)
        XCTAssertEqual(file.pages.first?.canvasObjectCount, 1)
    }

    // A page containing only the root frame reports no content at all (drives the
    // "File is empty" state).
    func testEmptyPageHasNoContent() throws {
        let root = "00000000-0000-0000-0000-000000000000"
        let json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["page1"],
            "pagesIndex": {
              "page1": {"id": "page1", "name": "Page 1", "objects": {
                "\(root)": {"type": "frame", "name": "Root", "parentId": "\(root)"}
              }}
            }
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        XCTAssertEqual(file.boards.count, 0)
        XCTAssertEqual(file.pages.first?.canvasObjectCount, 0)
        XCTAssertEqual(file.pages.first?.hasContent, false)
    }

    // MARK: - Dashboard (projects, fonts, libraries)

    // get-projects returns isDefault/isPinned/count/deletedAt; the helpers wrap the optionals.
    func testProjectDecodesDashboardFields() throws {
        let json = """
        {"id": "p1", "name": "Drafts", "teamId": "t1", "isDefault": true,
         "isPinned": false, "count": 3, "totalCount": 4, "deletedAt": null}
        """
        let project = try decode(Project.self, json)
        XCTAssertTrue(project.isDefaultProject)
        XCTAssertFalse(project.isPinnedFlag)
        XCTAssertEqual(project.fileCount, 3)
        XCTAssertNil(project.deletedAt)
    }

    // A project payload lacking the new fields must still decode; helpers default safely.
    func testProjectDefaultsWhenDashboardFieldsAbsent() throws {
        let project = try decode(Project.self, #"{"id": "p1", "name": "My Project"}"#)
        XCTAssertFalse(project.isDefaultProject)
        XCTAssertFalse(project.isPinnedFlag)
        XCTAssertEqual(project.fileCount, 0)
    }

    func testFontVariantDecodes() throws {
        let json = """
        {"id": "v1", "teamId": "t1", "fontId": "f1", "fontFamily": "Inter",
         "fontWeight": 700, "fontStyle": "italic", "variantName": "Bold Italic"}
        """
        let variant = try decode(FontVariant.self, json)
        XCTAssertEqual(variant.fontFamily, "Inter")
        XCTAssertEqual(variant.fontWeight, 700)
        XCTAssertEqual(variant.fontStyle, "italic")
        XCTAssertEqual(variant.variantName, "Bold Italic")
    }

    // Verbatim row shape from `get-team-deleted-files`; extra window-function keys are ignored.
    func testDeletedFileDecodes() throws {
        let json = """
        {"id": "f1", "revn": 4, "vern": 0, "projectId": "p1", "createdAt": "2026-07-01T00:00:00.000Z",
         "modifiedAt": "2026-07-10T00:00:00.000Z", "name": "Old Design",
         "willBeDeletedAt": "2026-07-21T00:00:00.000Z", "thumbnailId": null,
         "rowNum": 1, "teamId": "t1"}
        """
        let file = try decode(DeletedFile.self, json)
        XCTAssertEqual(file.id, "f1")
        XCTAssertEqual(file.name, "Old Design")
        XCTAssertEqual(file.projectId, "p1")
        XCTAssertEqual(file.willBeDeletedAt, "2026-07-21T00:00:00.000Z")
    }

    // get-team-shared-files elements decode as FileListItem; library-only keys are ignored.
    func testSharedLibraryDecodesAsFileListItem() throws {
        let json = """
        {"id": "lib1", "name": "Design System", "projectId": "p1", "teamId": "t1",
         "isShared": true, "thumbnailId": "th1", "libraryFileIds": ["a", "b"]}
        """
        let file = try decode(FileListItem.self, json)
        XCTAssertEqual(file.id, "lib1")
        XCTAssertEqual(file.name, "Design System")
    }

    // get-builtin-templates returns only `id` and `name` per entry — no thumbnail or
    // description — verified against a live Penpot server.
    func testBuiltinTemplatesDecode() throws {
        let json = """
        [{"id": "tokens-starter-kit", "name": "Design tokens starter kit"},
         {"id": "welcome", "name": "Welcome"}]
        """
        let templates = try decode([BuiltinTemplate].self, json)
        XCTAssertEqual(templates.count, 2)
        XCTAssertEqual(templates.first?.id, "tokens-starter-kit")
        XCTAssertEqual(templates.first?.name, "Design tokens starter kit")
        XCTAssertEqual(templates.last?.id, "welcome")
    }

    // The API exposes no image field, so previews are derived from the id using the same
    // static path Penpot's own dashboard uses. Verified live: 14 of 15 templates serve a jpg.
    func testBuiltinTemplateThumbnailURL() throws {
        let template = try decode(BuiltinTemplate.self,
                                  #"{"id": "wireframing-kit", "name": "Wireframe library"}"#)
        let url = template.thumbnailURL(baseURL: URL(string: "http://localhost:3450")!)
        XCTAssertEqual(url.absoluteString,
                       "http://localhost:3450/images/thumbnails/template-wireframing-kit.jpg")
    }

    // `search-files` rows carry no `teamId` and include search-only keys (`revn`,
    // `thumbnailId`) that FileListItem must tolerate.
    func testSearchFilesRowDecodesAsFileListItem() throws {
        let json = """
        {
          "id": "file-1",
          "revn": 7,
          "projectId": "project-1",
          "createdAt": "2026-01-01T00:00:00.000Z",
          "modifiedAt": "2026-02-01T00:00:00.000Z",
          "name": "Mobile App",
          "isShared": true,
          "thumbnailId": "media-1"
        }
        """
        let file = try decode(FileListItem.self, json)
        XCTAssertEqual(file.id, "file-1")
        XCTAssertEqual(file.name, "Mobile App")
        XCTAssertNil(file.teamId)
        XCTAssertEqual(file.isShared, true)
        // The file-level cover — the stable card thumbnail (board thumbnails are only
        // the fallback and once made covers shuffle per launch).
        XCTAssertEqual(file.thumbnailId, "media-1")
    }

    // The API has no role string — `get-team-members` rows carry permission booleans the
    // role is derived from (owner ⊃ admin ⊃ editor; none set = viewer).
    func testTeamMemberRoleDerivation() throws {
        func member(_ flags: String) throws -> TeamMember {
            try decode(TeamMember.self, #"{"id": "m1", "email": "a@b.co", \#(flags)}"#)
        }
        XCTAssertEqual(try member(#""isOwner": true, "isAdmin": true, "canEdit": true"#).role, .owner)
        XCTAssertEqual(try member(#""isOwner": false, "isAdmin": true, "canEdit": true"#).role, .admin)
        XCTAssertEqual(try member(#""isOwner": false, "isAdmin": false, "canEdit": true"#).role, .editor)
        XCTAssertEqual(try member(#""isOwner": false, "isAdmin": false, "canEdit": false"#).role, .viewer)
        // Rows without the booleans (older payload shapes) degrade to viewer.
        XCTAssertEqual(try decode(TeamMember.self, #"{"id": "m1"}"#).role, .viewer)
    }

    // `get-teams` includes the caller's per-team permissions inline.
    func testTeamDecodesPermissions() throws {
        let json = """
        {
          "id": "team-1",
          "name": "Design",
          "isDefault": false,
          "permissions": {"type": "membership", "isOwner": false, "isAdmin": true, "canEdit": true}
        }
        """
        let team = try decode(Team.self, json)
        XCTAssertEqual(team.permissions?.isAdmin, true)
        XCTAssertEqual(team.permissions?.isOwner, false)
        XCTAssertTrue(team.permissions?.isAdminOrOwner == true)
        // Teams from older cached payloads decode without permissions.
        XCTAssertNil(try decode(Team.self, #"{"id": "t", "name": "n"}"#).permissions)
    }

    // Invitations are keyed by (team, email) — no id, no dates beyond `expired`.
    func testTeamInvitationDecodes() throws {
        let invitation = try decode(TeamInvitation.self,
                                    #"{"email": "new@example.com", "role": "editor", "expired": false}"#)
        XCTAssertEqual(invitation.id, "new@example.com")
        XCTAssertEqual(invitation.teamRole, .editor)
        XCTAssertEqual(invitation.expired, false)
        // Unknown/missing role degrades to editor (the web default).
        XCTAssertEqual(try decode(TeamInvitation.self, #"{"email": "x@y.co"}"#).teamRole, .editor)
    }

    // Only `total` of the create-invitations response is contract-stable.
    func testInvitationResultDecodes() throws {
        XCTAssertEqual(try decode(InvitationResult.self, #"{"total": 2, "invitations": ["a@b.co"]}"#).total, 2)
        XCTAssertNil(try decode(InvitationResult.self, #"{}"#).total)
    }

    // MARK: Prototype flows / view-mode

    // Modern servers store page flows as a map of uuid → flow.
    func testFlowsDecodeFromMap() throws {
        let json = """
        {"f1": {"id": "f1", "name": "Checkout", "startingFrame": "frame-1"}}
        """
        let flows = try decode(FlowCollection.self, json)
        XCTAssertEqual(flows.flows.count, 1)
        XCTAssertEqual(flows.flows.first?.startingFrame, "frame-1")
    }

    // Pre-2.x files stored `options.flows` as an array.
    func testFlowsDecodeFromLegacyArray() throws {
        let flows = try decode(FlowCollection.self, #"[{"id": "f1", "name": "Flow 1"}]"#)
        XCTAssertEqual(flows.flows.first?.name, "Flow 1")
    }

    // A malformed flows payload decodes as empty — it must not sink the whole get-file.
    func testMalformedFlowsDecodeEmpty() throws {
        XCTAssertTrue(try decode(FlowCollection.self, #""garbage""#).flows.isEmpty)
    }

    // hasPrototype: page-level flows, legacy options.flows, or shape interactions all
    // qualify; viewerFrameIDs preserves root z-order and drops hidden/non-frame children.
    func testPageSummaryPrototypeDetection() throws {
        let json = """
        {
          "id": "file-1", "name": "F",
          "data": {
            "pages": ["p1", "p2"],
            "pagesIndex": {
              "p1": {
                "id": "p1", "name": "With flows",
                "flows": {"f1": {"id": "f1", "name": "Main", "startingFrame": "b1"}},
                "objects": {
                  "00000000-0000-0000-0000-000000000000":
                    {"type": "frame", "shapes": ["b1", "loose", "hidden", "b2"]},
                  "b1": {"type": "frame", "parentId": "00000000-0000-0000-0000-000000000000",
                         "selrect": {"x": 0, "y": 0, "width": 10, "height": 10}},
                  "b2": {"type": "frame", "parentId": "00000000-0000-0000-0000-000000000000",
                         "selrect": {"x": 0, "y": 20, "width": 10, "height": 10}},
                  "hidden": {"type": "frame", "hideInViewer": true,
                             "parentId": "00000000-0000-0000-0000-000000000000",
                             "selrect": {"x": 0, "y": 40, "width": 10, "height": 10}},
                  "loose": {"type": "rect", "parentId": "00000000-0000-0000-0000-000000000000"}
                }
              },
              "p2": {
                "id": "p2", "name": "No prototype",
                "objects": {
                  "00000000-0000-0000-0000-000000000000": {"type": "frame", "shapes": []}
                }
              }
            }
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        let withFlows = try XCTUnwrap(file.pages.first)
        XCTAssertTrue(withFlows.hasPrototype)
        XCTAssertEqual(withFlows.viewerFrameIDs, ["b1", "b2"])
        let without = try XCTUnwrap(file.pages.last)
        XCTAssertFalse(without.hasPrototype)

        // Shape-level interactions alone also count as playable.
        let interactionsOnly = json.replacingOccurrences(
            of: #""flows": {"f1": {"id": "f1", "name": "Main", "startingFrame": "b1"}},"#,
            with: "")
            .replacingOccurrences(of: #""b1": {"type": "frame","#,
                                  with: #""b1": {"type": "frame", "interactions": [{"actionType": "navigate", "destination": "b2"}],"#)
        XCTAssertTrue(try decode(PenpotFile.self, interactionsOnly).pages.first!.hasPrototype)
    }

    // MARK: Share links

    func testShareLinkDecodes() throws {
        let json = """
        {
          "id": "link-1",
          "fileId": "file-1",
          "whoComment": "all",
          "whoInspect": "team",
          "pages": ["p1", "p2"],
          "ownerId": "owner-1"
        }
        """
        let link = try decode(PenpotShareLink.self, json)
        XCTAssertTrue(link.allowsExternalComments)
        XCTAssertFalse(link.allowsExternalInspect)
        XCTAssertEqual(link.pages, ["p1", "p2"])
    }

    // Only the links + page list of the viewer bundle are decoded; everything else in the
    // (large) payload is ignored.
    func testViewOnlyBundleDecodesLinksAndPages() throws {
        let json = """
        {
          "users": [{"id": "u1"}],
          "shareLinks": [{"id": "link-1", "whoComment": "team", "whoInspect": "team"}],
          "file": {"id": "file-1", "data": {"pages": ["p1", "p2"], "pagesIndex": {}}},
          "permissions": {"canEdit": false}
        }
        """
        let bundle = try decode(ViewOnlyBundle.self, json)
        XCTAssertEqual(bundle.shareLinks?.count, 1)
        XCTAssertEqual(bundle.pageIDs, ["p1", "p2"])
        // A bundle without links/pages degrades to empty, not a decode failure.
        let empty = try decode(ViewOnlyBundle.self, #"{}"#)
        XCTAssertNil(empty.shareLinks)
        XCTAssertTrue(empty.pageIDs.isEmpty)
    }

    // MARK: Version history

    // Full row shape of newer servers (develop line).
    func testFileSnapshotFullRowDecodes() throws {
        let json = """
        {
          "id": "snap-1",
          "label": "Before redesign",
          "revn": 42,
          "version": 67,
          "createdAt": "2026-08-01T10:00:00.000Z",
          "modifiedAt": "2026-08-02T10:00:00.000Z",
          "createdBy": "user",
          "profileId": "profile-1",
          "lockedBy": "profile-2",
          "deletedAt": null
        }
        """
        let snapshot = try decode(FileSnapshot.self, json)
        XCTAssertEqual(snapshot.label, "Before redesign")
        XCTAssertEqual(snapshot.revn, 42)
        XCTAssertEqual(snapshot.lockedBy, "profile-2")
        XCTAssertTrue(snapshot.isUserVersion)
    }

    // 2.7.x rows carry only id/label/revn/createdAt/createdBy/profileId.
    func testFileSnapshotMinimalRowDecodes() throws {
        let json = """
        {"id": "snap-1", "label": "v1", "revn": 3,
         "createdAt": "2026-08-01T10:00:00.000Z", "createdBy": "user", "profileId": "p1"}
        """
        let snapshot = try decode(FileSnapshot.self, json)
        XCTAssertNil(snapshot.version)
        XCTAssertNil(snapshot.lockedBy)
        XCTAssertTrue(snapshot.isUserVersion)
    }

    // System rows are autosaves; their internal labels are never shown as version names.
    func testFileSnapshotSystemRowIsAutosave() throws {
        let json = """
        {"id": "snap-2", "label": "internal/snapshot/45", "createdBy": "system",
         "createdAt": "2026-08-01T10:00:00.000Z", "deletedAt": "2026-08-08T10:00:00.000Z"}
        """
        XCTAssertFalse(try decode(FileSnapshot.self, json).isUserVersion)
    }

    // Web-sidebar grouping: user versions individual, system rows bundled per calendar
    // day, everything newest-first; input deliberately unsorted (the server's SQL UNION
    // guarantees no order).
    func testSnapshotGroupingMatchesWebSidebar() throws {
        func snapshot(_ id: String, _ createdAt: String, _ by: String) throws -> FileSnapshot {
            try decode(FileSnapshot.self,
                       #"{"id": "\#(id)", "createdAt": "\#(createdAt)", "createdBy": "\#(by)"}"#)
        }
        let rows = [
            try snapshot("auto-old", "2026-08-01T09:00:00.000Z", "system"),
            try snapshot("user-new", "2026-08-02T12:00:00.000Z", "user"),
            try snapshot("auto-new-2", "2026-08-02T08:00:00.000Z", "system"),
            try snapshot("user-old", "2026-08-01T10:00:00.000Z", "user"),
            try snapshot("auto-new-1", "2026-08-02T09:00:00.000Z", "system"),
        ]
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let groups = SnapshotGroup.build(from: rows, calendar: utc)

        XCTAssertEqual(groups.count, 4)
        guard case .version(let first) = groups[0],
              case .autosaves(_, let day2Items) = groups[1],
              case .version(let third) = groups[2],
              case .autosaves(_, let day1Items) = groups[3] else {
            return XCTFail("unexpected group shapes: \(groups.map(\.id))")
        }
        XCTAssertEqual(first.id, "user-new")
        XCTAssertEqual(day2Items.map(\.id), ["auto-new-1", "auto-new-2"])
        XCTAssertEqual(third.id, "user-old")
        XCTAssertEqual(day1Items.map(\.id), ["auto-old"])
    }

    // create-file-snapshot responses vary by server version; only `id` is relied upon
    // and no shape may throw (an empty 204 body reaches the decoder as "null").
    func testSnapshotRefDecodesLeniently() throws {
        let full = try decode(PenpotClient.SnapshotRef.self,
                              #"{"id": "snap-1", "label": "v1", "revn": 3, "createdBy": "user"}"#)
        XCTAssertEqual(full.id, "snap-1")
        XCTAssertEqual(try decode(PenpotClient.SnapshotRef.self, #"{"id": "s", "label": "l"}"#).id, "s")
        XCTAssertNil(try decode(PenpotClient.SnapshotRef.self, "null").id)
        XCTAssertNil(try decode(PenpotClient.SnapshotRef.self, "true").id)
    }

    // 404 WITHOUT a `code` = unknown RPC command (old server); 404 WITH `object-not-found`
    // = the command exists but id/access failed. Restore conflicts surface their code.
    func testPenpotErrorHelpers() {
        let unknown = PenpotError.server(status: 404, body: #"{"type": "not-found"}"#)
        XCTAssertTrue(unknown.isUnknownCommand)
        let notFound = PenpotError.server(status: 404,
                                          body: #"{"type": "not-found", "code": "object-not-found"}"#)
        XCTAssertFalse(notFound.isUnknownCommand)
        XCTAssertEqual(notFound.serverErrorCode, "object-not-found")
        let conflict = PenpotError.server(status: 500,
                                          body: #"{"type": "server-error", "code": "file-modified", "hint": "retry"}"#)
        XCTAssertFalse(conflict.isUnknownCommand)
        XCTAssertEqual(conflict.serverErrorCode, "file-modified")
        XCTAssertNil(PenpotError.unauthorized.serverErrorCode)
        XCTAssertFalse(PenpotError.server(status: 404, body: nil).isUnknownCommand)
    }

    // The public URL matches the web app's share dialog, including path-prefixed
    // self-hosted bases (the fragment is appended after the path).
    func testShareURLFormat() throws {
        let client = PenpotClient(baseURL: URL(string: "https://host.example/penpot")!)
        XCTAssertEqual(
            client.shareURL(fileID: "f1", pageID: "p1", shareID: "s1")?.absoluteString,
            "https://host.example/penpot/#/view?file-id=f1&page-id=p1&section=interactions&index=0&share-id=s1")
        // Without a page id the viewer falls back to the file's first page.
        XCTAssertEqual(
            client.shareURL(fileID: "f1", pageID: nil, shareID: "s1")?.absoluteString,
            "https://host.example/penpot/#/view?file-id=f1&section=interactions&index=0&share-id=s1")
    }
}
