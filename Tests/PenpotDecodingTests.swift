import XCTest
@testable import PenpotiOS

final class PenpotDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.penpot.decode(T.self, from: Data(json.utf8))
    }

    // A real `get-file-stats` response (Penpot devenv, the "UI mockup example" template).
    func testFileStatsDecodesAndSortsLayerTypes() throws {
        let json = """
        {"pageCount":3,"updatedAt":"2026-10-09T16:36:23.261887Z",
         "shapeCounts":{"total":1941,"byType":{"rect":339,"text":145,"group":470,"frame":265,
                                               "path":693,"circle":23,"bool":6,"image":0}},
         "fileId":"f40feac7-a962-8164-8008-c3a5901949c3","deletedComponentCount":0,"revn":19,
         "referencedByCount":0,"typographyCount":4,"componentCount":201,"colorCount":7,
         "libraryCount":0}
        """
        let stats = try decode(FileStats.self, json)
        XCTAssertEqual(stats.pageCount, 3)
        XCTAssertEqual(stats.shapeCounts?.total, 1941)
        XCTAssertEqual(stats.componentCount, 201)
        XCTAssertEqual(stats.colorCount, 7)
        XCTAssertEqual(stats.typographyCount, 4)
        XCTAssertEqual(stats.libraryCount, 0)
        XCTAssertEqual(stats.revn, 19)
        // Most frequent first; zero counts dropped.
        XCTAssertEqual(stats.layerTypes.map(\.type),
                       ["path", "group", "rect", "frame", "text", "circle", "bool"])
        XCTAssertEqual(stats.layerTypes.first?.count, 693)
    }

    func testFileStatsToleratesMissingKeys() throws {
        let stats = try decode(FileStats.self, #"{"pageCount": 1}"#)
        XCTAssertEqual(stats.pageCount, 1)
        XCTAssertTrue(stats.layerTypes.isEmpty)
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

    // MARK: Recent files / team photo

    // get-team-recent-files rows carry extra keys FileListItem must tolerate.
    func testRecentFileRowDecodesAsFileListItem() throws {
        let json = """
        {
          "id": "file-1", "revn": 3, "vern": 12345, "rowNum": 1,
          "projectId": "project-1", "teamId": "team-1",
          "createdAt": "2026-01-01T00:00:00.000Z", "modifiedAt": "2026-08-01T00:00:00.000Z",
          "name": "Latest", "isShared": false, "thumbnailId": "media-9"
        }
        """
        let file = try decode(FileListItem.self, json)
        XCTAssertEqual(file.name, "Latest")
        XCTAssertEqual(file.thumbnailId, "media-9")
    }

    // update-team-photo answers with the full team row carrying the NEW photoId.
    func testUpdateTeamPhotoResponseDecodesTeam() throws {
        let json = """
        {"id": "team-1", "name": "Design", "isDefault": false, "photoId": "media-new",
         "permissions": {"isOwner": true, "isAdmin": true, "canEdit": true}}
        """
        let team = try decode(Team.self, json)
        XCTAssertEqual(team.photoId, "media-new")
        XCTAssertEqual(team.permissions?.isOwner, true)
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

    // viewerIndex counts the topmost board first and skips hidden/non-frame children;
    // the canvas color is the page's, else the legacy options', else Penpot's default.
    func testPageSummaryViewerIndexAndBackground() throws {
        let json = """
        {
          "id": "file-1", "name": "F",
          "data": {
            "pages": ["p1", "p2", "p3"],
            "pagesIndex": {
              "p1": {
                "id": "p1", "name": "Boards", "background": "#1E1E2E",
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
                "id": "p2", "name": "Legacy", "options": {"background": "#FFFFFF"},
                "objects": {
                  "00000000-0000-0000-0000-000000000000": {"type": "frame", "shapes": []}
                }
              },
              "p3": {
                "id": "p3", "name": "Default",
                "objects": {
                  "00000000-0000-0000-0000-000000000000": {"type": "frame", "shapes": []}
                }
              }
            }
          }
        }
        """
        let pages = try decode(PenpotFile.self, json).pages
        XCTAssertEqual(pages.first?.viewerIndex, ["b2": 0, "b1": 1])
        XCTAssertEqual(pages.map(\.background), ["#1E1E2E", "#FFFFFF", "#E8E9EA"])
    }

    /// Penpot names root boards on its canvas, with an icon for the thumbnail board and a
    /// main component; a copy of a component and a hidden board get no name.
    func testCanvasTitles() throws {
        let root = Board.rootFrameID
        let json = """
        {"id": "p", "name": "P", "objects": {
          "\(root)": {"type": "frame", "shapes": ["plain", "thumb", "main", "copy", "hidden"]},
          "plain": {"type": "frame", "parentId": "\(root)", "selrect": {"x": 0, "y": 0, "width": 10, "height": 10}},
          "thumb": {"type": "frame", "parentId": "\(root)", "useForThumbnail": true,
                    "selrect": {"x": 20, "y": 0, "width": 10, "height": 10}},
          "main": {"type": "frame", "parentId": "\(root)", "componentId": "c", "mainInstance": true,
                   "selrect": {"x": 40, "y": 0, "width": 10, "height": 10}},
          "copy": {"type": "frame", "parentId": "\(root)", "componentId": "c",
                   "selrect": {"x": 60, "y": 0, "width": 10, "height": 10}},
          "hidden": {"type": "frame", "parentId": "\(root)", "hidden": true,
                     "selrect": {"x": 80, "y": 0, "width": 10, "height": 10}}
        }}
        """
        let boards = PenpotPageSummary(id: "p", page: try decode(PenpotPage.self, json)).boards
        XCTAssertEqual(boards.map(\.id), ["plain", "thumb", "main", "copy", "hidden"])
        XCTAssertEqual(boards.map(\.titleIcon), [nil, .thumbnail, .component, nil, nil])
        XCTAssertEqual(boards.map(\.showsCanvasTitle), [true, true, true, false, false])
    }

    /// An outline cached before pages kept their canvas color is fetched again.
    func testOutlineWithoutBackgroundDoesNotDecode() {
        let cached = #"{"revision": 3, "pages": [{"id": "p", "name": "P", "boards": [], "canvasObjectCount": 0, "hasPrototype": false, "viewerIndex": {}}]}"#
        XCTAssertThrowsError(try decode(FileOutline.self, cached))
    }

    // MARK: View-mode frame order

    /// A page from `objects`, with the root frame listing `rootShapes`.
    private func viewerPage(rootShapes: [String], _ objects: String) throws -> PenpotPage {
        let root = Board.rootFrameID
        let shapes = rootShapes.map { "\"\($0)\"" }.joined(separator: ", ")
        return try decode(PenpotPage.self, """
        {"id": "p1", "name": "Page 1", "objects": {
          "\(root)": {"id": "\(root)", "type": "frame", "parentId": "\(root)", "shapes": [\(shapes)]},
          \(objects)
        }}
        """)
    }

    private func board(_ id: String, x: Int, y: Int = 0, hidden: Bool = false) -> String {
        """
        "\(id)": {"id": "\(id)", "name": "\(id)", "type": "frame", "hideInViewer": \(hidden),
          "parentId": "\(Board.rootFrameID)",
          "selrect": {"x": \(x), "y": \(y), "width": 400, "height": 800}}
        """
    }

    // "Café Linde – iPhone prototype": the root lists its boards bottom layer first, and
    // Penpot's viewer starts at the topmost, so it showed "2 / 4" (Full menu) for Flat
    // white. The four landscape boards are hidden in the viewer.
    func testViewerFramesStartAtTheTopmostBoard() throws {
        let page = try viewerPage(
            rootShapes: ["menu-l", "order", "flat", "flat-l", "full", "order-l", "menu", "full-l"],
            [board("menu", x: 0), board("flat", x: 500), board("order", x: 1000),
             board("full", x: 1500), board("flat-l", x: 2000, hidden: true),
             board("menu-l", x: 0, y: 2000, hidden: true),
             board("order-l", x: 2000, y: 2000, hidden: true),
             board("full-l", x: 1000, y: 2000, hidden: true)].joined(separator: ",\n"))

        XCTAssertEqual(page.viewerFrameIDs, ["menu", "full", "flat", "order"])
        let summary = PenpotPageSummary(id: "p1", page: page)
        XCTAssertEqual(summary.viewerIndex, ["menu": 0, "full": 1, "flat": 2, "order": 3])
        XCTAssertNil(summary.viewerIndex["flat-l"])
        // The board grid keeps its own reading order.
        XCTAssertEqual(summary.boards.map(\.id).prefix(4), ["menu", "flat", "order", "full"])
    }

    // `get-viewer-frames` lists every frame of the page, not only root boards: a frame
    // comes right before the frames inside it, groups are looked through, a frame hidden
    // in the viewer still lets its children in, and a flex or grid board orders its
    // children by z-index (highest first), then in `shapes` order. A nested frame shifts
    // the index of every root board after it.
    func testViewerFramesFollowPenpotsZIndexSort() throws {
        let root = Board.rootFrameID
        let page = try viewerPage(rootShapes: ["board", "group", "flex"], """
          "board": {"id": "board", "type": "frame", "parentId": "\(root)",
            "selrect": {"x": 0, "y": 0, "width": 100, "height": 100},
            "shapes": ["n1", "n2", "n3"]},
          "n1": {"id": "n1", "type": "frame", "parentId": "board", "hideInViewer": true,
            "shapes": ["n1a"]},
          "n1a": {"id": "n1a", "type": "frame", "parentId": "n1"},
          "n2": {"id": "n2", "type": "rect", "parentId": "board"},
          "n3": {"id": "n3", "type": "frame", "parentId": "board"},
          "group": {"id": "group", "type": "group", "parentId": "\(root)", "shapes": ["g1"]},
          "g1": {"id": "g1", "type": "frame", "parentId": "group"},
          "flex": {"id": "flex", "type": "frame", "parentId": "\(root)", "layout": "flex",
            "selrect": {"x": 200, "y": 0, "width": 100, "height": 100},
            "shapes": ["f1", "f2", "f3"]},
          "f1": {"id": "f1", "type": "frame", "parentId": "flex"},
          "f2": {"id": "f2", "type": "frame", "parentId": "flex", "layoutItemZIndex": 5},
          "f3": {"id": "f3", "type": "frame", "parentId": "flex", "layoutItemZIndex": 0}
        """)

        XCTAssertEqual(page.viewerFrameIDs, ["flex", "f2", "f1", "f3", "g1", "board", "n3", "n1a"])
        XCTAssertEqual(PenpotPageSummary(id: "p1", page: page).viewerIndex,
                       ["flex": 0, "board": 5])
    }

    // The start board goes in as `frame-id`, which Penpot prefers over `index`.
    func testViewModeURLStartsOnTheBoard() throws {
        let url = try XCTUnwrap(PenpotViewModeView.viewModeURL(
            baseURL: URL(string: "https://design.penpot.app")!, fileID: "f", pageID: "p",
            frameID: "flat", index: 2))
        // `wasm=false`: the WebGL viewer outgrows a web view's memory on an iPhone.
        XCTAssertEqual(url.absoluteString, "https://design.penpot.app/#/view?file-id=f&page-id=p"
                       + "&frame-id=flat&section=interactions&index=2&wasm=false")
        let pageStart = PenpotViewModeView.viewModeURL(
            baseURL: URL(string: "https://design.penpot.app")!, fileID: "f", pageID: "p",
            frameID: nil, index: 0)
        XCTAssertFalse(pageStart?.absoluteString.contains("frame-id") ?? true)
    }

    // MARK: Fragment pointers (large-file page data)

    // The HTTP middleware encodes a pagesIndex pointer as [fragmentId, {meta}]. It must
    // be recognized — and must NOT sink the whole get-file decode.
    func testPagesIndexPointerArrayRecognized() throws {
        let json = """
        {
          "id": "file-1", "name": "Big file",
          "data": {
            "pages": ["p1"],
            "pagesIndex": {"p1": ["frag-1", {"createdAt": "2026-08-01T10:00:00.000Z"}]}
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        XCTAssertEqual(file.unresolvedPointerPages, ["p1": "frag-1"])
        XCTAssertTrue(file.pages.isEmpty)
    }

    // Defensive alternative pointer shape ({"type": "pointer", "id": …}).
    func testPagesIndexObjectPointerRecognized() throws {
        let json = """
        {"id": "f", "name": "F", "data": {"pages": ["p1"],
         "pagesIndex": {"p1": {"type": "pointer", "id": "frag-2", "meta": {}}}}}
        """
        XCTAssertEqual(try decode(PenpotFile.self, json).unresolvedPointerPages, ["p1": "frag-2"])
    }

    // Inline pages and pointers coexist; inline boards extract, pointers are listed.
    func testInlineAndPointerPagesCoexist() throws {
        let json = """
        {
          "id": "f", "name": "F",
          "data": {
            "pages": ["p1", "p2"],
            "pagesIndex": {
              "p1": {"id": "p1", "name": "Inline", "objects": {
                "00000000-0000-0000-0000-000000000000": {"type": "frame", "shapes": ["b1"]},
                "b1": {"type": "frame", "parentId": "00000000-0000-0000-0000-000000000000",
                       "selrect": {"x": 0, "y": 0, "width": 10, "height": 10}}}},
              "p2": ["frag-9", {}]
            }
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        XCTAssertEqual(file.pages.map(\.id), ["p1"])
        XCTAssertEqual(file.pages.first?.boards.count, 1)
        XCTAssertEqual(file.unresolvedPointerPages, ["p2": "frag-9"])
    }

    // Garbage pagesIndex values degrade to .unrecognized without sinking siblings.
    func testUnrecognizedPagesIndexEntryDoesNotSinkDecode() throws {
        let json = """
        {"id": "f", "name": "F", "data": {"pages": ["p1", "p2"], "pagesIndex": {
          "p1": 42,
          "p2": {"id": "p2", "name": "OK", "objects": {}}}}}
        """
        let file = try decode(PenpotFile.self, json)
        XCTAssertEqual(file.pages.map(\.id), ["p2"])
        XCTAssertTrue(file.unresolvedPointerPages.isEmpty)
    }

    // Modern fragment rows carry the page under `data`…
    func testFileFragmentDecodesDataKey() throws {
        let json = """
        {"id": "frag-1", "fileId": "f", "type": "fragment",
         "data": {"id": "p1", "name": "Page 1", "objects": {}}}
        """
        XCTAssertEqual(try decode(FileFragment.self, json).page?.name, "Page 1")
    }

    // …2.0-era servers used `content`.
    func testFileFragmentDecodesLegacyContentKey() throws {
        let json = #"{"id": "frag-1", "content": {"id": "p1", "name": "Old", "objects": {}}}"#
        XCTAssertEqual(try decode(FileFragment.self, json).page?.name, "Old")
    }

    // A components-map fragment is not a page — must yield nil, not throw.
    func testFileFragmentToleratesNonPagePayload() throws {
        let json = #"{"id": "frag-1", "data": {"c1": {"name": "Component"}}}"#
        XCTAssertNil(try decode(FileFragment.self, json).page)
    }

    // Stitching replaces pointers by page id and preserves the data.pages order.
    func testResolvingPointerPagesStitchesByPageID() throws {
        let json = """
        {
          "id": "f", "name": "F",
          "data": {
            "pages": ["p1", "p2", "p3"],
            "pagesIndex": {
              "p1": {"id": "p1", "name": "One", "objects": {}},
              "p2": ["frag-2", {}],
              "p3": {"id": "p3", "name": "Three", "objects": {}}
            }
          }
        }
        """
        let file = try decode(PenpotFile.self, json)
        let resolvedPage = try decode(PenpotPage.self,
                                      #"{"id": "p2", "name": "Two", "objects": {}}"#)
        let stitched = file.resolvingPointerPages(["p2": resolvedPage])
        XCTAssertEqual(stitched.pages.map(\.name), ["One", "Two", "Three"])
        XCTAssertTrue(stitched.unresolvedPointerPages.isEmpty)
        // An unresolved pointer stays skipped rather than failing.
        XCTAssertEqual(file.resolvingPointerPages([:]).pages.map(\.name), ["One", "Three"])
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
