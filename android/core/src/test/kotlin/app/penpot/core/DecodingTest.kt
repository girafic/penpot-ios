package app.penpot.core

import app.penpot.core.model.BuiltinTemplate
import app.penpot.core.model.CommentThread
import app.penpot.core.model.DeletedFile
import app.penpot.core.model.FileListItem
import app.penpot.core.model.FontVariant
import app.penpot.core.model.PenpotFile
import app.penpot.core.model.Point
import app.penpot.core.model.Project
import app.penpot.core.model.Selrect
import app.penpot.core.network.PenpotClient
import app.penpot.core.network.PenpotJson
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the iOS PenpotDecodingTests — same JSON fixtures, same expectations. */
class DecodingTest {

    private inline fun <reified T> decode(json: String): T = PenpotJson.decodeFromString(json)

    private val root = "00000000-0000-0000-0000-000000000000"

    // Penpot's JSON API returns camelCase keys (e.g. fileId, isResolved), not kebab-case.
    @Test
    fun commentThreadDecodesCamelKeys() {
        val json = """
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
        val thread = decode<CommentThread>(json)
        assertEquals("t1", thread.id)
        assertEquals("f1", thread.fileId)
        assertEquals("fr1", thread.frameId)
        assertEquals(Point(10.5, 20.0), thread.position)
        assertEquals(false, thread.isResolved)
        assertEquals(1, thread.countUnreadComments)
    }

    // Verbatim payload shape from `get-unread-comment-threads`: the server joins the file and
    // the owner onto each thread, which is what lets the inbox render a thread outside its file.
    @Test
    fun unreadCommentThreadDecodesJoinedFileAndOwner() {
        val json = """
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
        val thread = decode<CommentThread>(json)
        assertEquals("Plants-app", thread.fileName)
        assertEquals("team-1", thread.teamId)
        assertEquals("Test User", thread.ownerFullname)
        assertEquals("photo-1", thread.ownerPhotoId)
        assertEquals("2026-06-26T11:46:32.296501Z", thread.modifiedAt)
        assertEquals(2, thread.unreadCount)
    }

    // A thread without an unread count must not report unread comments.
    @Test
    fun unreadCountDefaultsToZero() {
        val thread = decode<CommentThread>("""{"id": "t1"}""")
        assertEquals(0, thread.unreadCount)
    }

    @Test
    fun thumbnailsMapDecodes() {
        val map = decode<Map<String, String>>("""{"board1": "media-abc", "board2": "media-def"}""")
        assertEquals("media-abc", map["board1"])
        assertEquals(2, map.size)
    }

    // Penpot keys object thumbnails by "<file-id>/<page-id>/<frame-id>/frame"; we re-key by frame id.
    @Test
    fun frameThumbnailsRekeysCompositeKeys() {
        val fid = "40b5cf7c-e089-81bd-8005-45ce0de05bc7"
        val pid = "40b5cf7c-e089-81bd-8005-45ce0de05bc8"
        val frame = "17dd8fce-c39e-804b-8005-c2bc12896b5d"
        val mapped = PenpotClient.frameThumbnails(
            mapOf(
                "$fid/$pid/$frame/frame" to "media-1",
                "legacy-bare-frame-id" to "media-2",
            ),
        )
        assertEquals("media-1", mapped[frame])
        assertEquals("media-2", mapped["legacy-bare-frame-id"])
    }

    @Test
    fun fileBoardExtraction() {
        val json = """
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
                  "$root": {"type": "frame", "name": "Root", "parentId": null},
                  "board1": {
                    "type": "frame", "name": "Board 1",
                    "parentId": "$root", "frameId": "$root",
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
        val file = decode<PenpotFile>(json)
        val boards = file.boards
        assertEquals(1, boards.size)
        assertEquals("board1", boards.first().id)
        assertEquals("page1", boards.first().pageId)
        assertEquals(Selrect(0.0, 0.0, 100.0, 200.0), boards.first().selrect)
    }

    @Test
    fun filePagesPreserveOrderAndBoards() {
        val json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["pageB", "pageA"],
            "pagesIndex": {
              "pageA": {"id": "pageA", "name": "Alpha", "objects": {
                "$root": {"type": "frame", "name": "Root", "parentId": null},
                "a1": {"type": "frame", "name": "A1", "parentId": "$root", "frameId": "$root",
                       "selrect": {"x": 0, "y": 0, "width": 10, "height": 10}}
              }},
              "pageB": {"id": "pageB", "name": "Beta", "objects": {
                "$root": {"type": "frame", "name": "Root", "parentId": null},
                "b1": {"type": "frame", "name": "B1", "parentId": "$root", "frameId": "$root",
                       "selrect": {"x": 0, "y": 0, "width": 10, "height": 10}},
                "b2": {"type": "frame", "name": "B2", "parentId": "$root", "frameId": "$root",
                       "selrect": {"x": 0, "y": 20, "width": 10, "height": 10}}
              }}
            }
          }
        }
        """
        val file = decode<PenpotFile>(json)
        // Pages follow data.pages order (pageB before pageA), not map order.
        assertEquals(listOf("Beta", "Alpha"), file.pages.map { it.name })
        assertEquals(2, file.pages.first().boards.size)
        assertEquals(1, file.pages.last().boards.size)
        assertEquals(3, file.boards.size)
    }

    // A page whose only content is drawn directly on the canvas (non-frame children of
    // the root frame) must report canvas objects so the file isn't presented as empty.
    // The root frame is self-parented here, as in real Penpot payloads — it must not
    // count itself.
    @Test
    fun looseCanvasShapesCountedWhenNoBoards() {
        val json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["page1"],
            "pagesIndex": {
              "page1": {"id": "page1", "name": "Page 1", "objects": {
                "$root": {"type": "frame", "name": "Root", "parentId": "$root", "frameId": "$root"},
                "rect1": {"type": "rect", "name": "Rect", "parentId": "$root", "frameId": "$root",
                          "selrect": {"x": 0, "y": 0, "width": 5, "height": 5}}
              }}
            }
          }
        }
        """
        val file = decode<PenpotFile>(json)
        assertEquals(0, file.boards.size)
        assertEquals(1, file.pages.first().canvasObjectCount)
        assertTrue(file.pages.first().hasContent)
    }

    // Shapes nested inside a board must not count; only direct children of the root do.
    @Test
    fun canvasObjectCountIgnoresBoardChildren() {
        val json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["page1"],
            "pagesIndex": {
              "page1": {"id": "page1", "name": "Page 1", "objects": {
                "$root": {"type": "frame", "name": "Root", "parentId": "$root"},
                "board1": {"type": "frame", "name": "Board 1", "parentId": "$root", "frameId": "$root",
                           "selrect": {"x": 0, "y": 0, "width": 100, "height": 200}},
                "rect1": {"type": "rect", "name": "Rect", "parentId": "board1",
                          "selrect": {"x": 1, "y": 1, "width": 2, "height": 2}},
                "text1": {"type": "text", "name": "Text", "parentId": "$root", "frameId": "$root",
                          "selrect": {"x": 10, "y": 10, "width": 20, "height": 5}}
              }}
            }
          }
        }
        """
        val file = decode<PenpotFile>(json)
        assertEquals(1, file.pages.first().boards.size)
        assertEquals(1, file.pages.first().canvasObjectCount)
    }

    // A root-level frame with no decodable selrect can't be a board thumbnail but is
    // still content — it must land in the canvas count instead of vanishing.
    @Test
    fun frameWithoutSelrectCountsAsCanvasObject() {
        val json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["page1"],
            "pagesIndex": {
              "page1": {"id": "page1", "name": "Page 1", "objects": {
                "$root": {"type": "frame", "name": "Root", "parentId": "$root"},
                "frame1": {"type": "frame", "name": "Frame", "parentId": "$root", "frameId": "$root"}
              }}
            }
          }
        }
        """
        val file = decode<PenpotFile>(json)
        assertEquals(0, file.boards.size)
        assertEquals(1, file.pages.first().canvasObjectCount)
    }

    // A malformed selrect must degrade that one shape, never fail the whole file decode.
    @Test
    fun malformedSelrectDegradesToCanvasObject() {
        val json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["page1"],
            "pagesIndex": {
              "page1": {"id": "page1", "name": "Page 1", "objects": {
                "$root": {"type": "frame", "name": "Root", "parentId": "$root"},
                "frame1": {"type": "frame", "name": "Frame", "parentId": "$root",
                           "selrect": {"x": "not-a-number"}}
              }}
            }
          }
        }
        """
        val file = decode<PenpotFile>(json)
        assertEquals(0, file.boards.size)
        assertEquals(1, file.pages.first().canvasObjectCount)
    }

    // A page containing only the root frame reports no content at all (drives the
    // "File is empty" state).
    @Test
    fun emptyPageHasNoContent() {
        val json = """
        {
          "id": "file1", "name": "Design", "revn": 1,
          "data": {
            "pages": ["page1"],
            "pagesIndex": {
              "page1": {"id": "page1", "name": "Page 1", "objects": {
                "$root": {"type": "frame", "name": "Root", "parentId": "$root"}
              }}
            }
          }
        }
        """
        val file = decode<PenpotFile>(json)
        assertEquals(0, file.boards.size)
        assertEquals(0, file.pages.first().canvasObjectCount)
        assertFalse(file.pages.first().hasContent)
    }

    // ── Dashboard (projects, fonts, libraries) ──────────────────────────────

    // get-projects returns isDefault/isPinned/count/deletedAt; the helpers wrap the optionals.
    @Test
    fun projectDecodesDashboardFields() {
        val json = """
        {"id": "p1", "name": "Drafts", "teamId": "t1", "isDefault": true,
         "isPinned": false, "count": 3, "totalCount": 4, "deletedAt": null}
        """
        val project = decode<Project>(json)
        assertTrue(project.isDefaultProject)
        assertFalse(project.isPinnedFlag)
        assertEquals(3, project.fileCount)
        assertNull(project.deletedAt)
    }

    // A project payload lacking the new fields must still decode; helpers default safely.
    @Test
    fun projectDefaultsWhenDashboardFieldsAbsent() {
        val project = decode<Project>("""{"id": "p1", "name": "My Project"}""")
        assertFalse(project.isDefaultProject)
        assertFalse(project.isPinnedFlag)
        assertEquals(0, project.fileCount)
    }

    @Test
    fun fontVariantDecodes() {
        val json = """
        {"id": "v1", "teamId": "t1", "fontId": "f1", "fontFamily": "Inter",
         "fontWeight": 700, "fontStyle": "italic", "variantName": "Bold Italic"}
        """
        val variant = decode<FontVariant>(json)
        assertEquals("Inter", variant.fontFamily)
        assertEquals(700, variant.fontWeight)
        assertEquals("italic", variant.fontStyle)
        assertEquals("Bold Italic", variant.variantName)
    }

    // Verbatim row shape from `get-team-deleted-files`; extra window-function keys are ignored.
    @Test
    fun deletedFileDecodes() {
        val json = """
        {"id": "f1", "revn": 4, "vern": 0, "projectId": "p1", "createdAt": "2026-07-01T00:00:00.000Z",
         "modifiedAt": "2026-07-10T00:00:00.000Z", "name": "Old Design",
         "willBeDeletedAt": "2026-07-21T00:00:00.000Z", "thumbnailId": null,
         "rowNum": 1, "teamId": "t1"}
        """
        val file = decode<DeletedFile>(json)
        assertEquals("f1", file.id)
        assertEquals("Old Design", file.name)
        assertEquals("p1", file.projectId)
        assertEquals("2026-07-21T00:00:00.000Z", file.willBeDeletedAt)
    }

    // get-team-shared-files elements decode as FileListItem; library-only keys are ignored.
    @Test
    fun sharedLibraryDecodesAsFileListItem() {
        val json = """
        {"id": "lib1", "name": "Design System", "projectId": "p1", "teamId": "t1",
         "isShared": true, "thumbnailId": "th1", "libraryFileIds": ["a", "b"]}
        """
        val file = decode<FileListItem>(json)
        assertEquals("lib1", file.id)
        assertEquals("Design System", file.name)
    }

    // get-builtin-templates returns only `id` and `name` per entry — no thumbnail or
    // description — verified against a live Penpot server.
    @Test
    fun builtinTemplatesDecode() {
        val json = """
        [{"id": "tokens-starter-kit", "name": "Design tokens starter kit"},
         {"id": "welcome", "name": "Welcome"}]
        """
        val templates = decode<List<BuiltinTemplate>>(json)
        assertEquals(2, templates.size)
        assertEquals("tokens-starter-kit", templates.first().id)
        assertEquals("Design tokens starter kit", templates.first().name)
        assertEquals("welcome", templates.last().id)
    }

    // The API exposes no image field, so previews are derived from the id using the same
    // static path Penpot's own dashboard uses.
    @Test
    fun builtinTemplateThumbnailUrl() {
        val template = decode<BuiltinTemplate>("""{"id": "wireframing-kit", "name": "Wireframe library"}""")
        val url = template.thumbnailUrl("http://localhost:3450".toHttpUrl())
        assertEquals(
            "http://localhost:3450/images/thumbnails/template-wireframing-kit.jpg",
            url.toString(),
        )
    }
}
