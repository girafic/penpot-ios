package app.penpot.core.model

import app.penpot.core.network.PenpotJson
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import okhttp3.HttpUrl

// ── Geometry ────────────────────────────────────────────────────────────────

@Serializable
data class Point(val x: Double, val y: Double)

@Serializable
data class Selrect(val x: Double, val y: Double, val width: Double, val height: Double)

// ── Profile / Team / Project / File ─────────────────────────────────────────

/**
 * Credentials returned by `create-demo-profile` — a throwaway account the caller then
 * logs in with. Only works when the server has the `demo-users` flag enabled.
 */
@Serializable
data class DemoProfile(val email: String, val password: String)

@Serializable
data class Profile(
    val id: String,
    val fullname: String? = null,
    val email: String? = null,
    val photoId: String? = null,
    // Present on some responses (login/update-profile), absent on others. All optional so
    // decoding never fails. Note: `lang` and `theme` are write-only in Penpot's API — they
    // are accepted as `update-profile` params but never returned, so they usually stay null.
    val theme: String? = null,
    val lang: String? = null,
    val props: ProfileProps? = null,
) {
    /** Best display name, or null when the caller should fall back to a localized "Unknown". */
    val displayName: String? get() = fullname ?: email
}

/**
 * A member of a team (from `get-team-members`). Used to recover the current user's
 * profile (incl. avatar) when `get-profile` is unavailable.
 */
@Serializable
data class TeamMember(
    val id: String,
    val profileId: String? = null,
    val email: String? = null,
    val fullname: String? = null,
    val photoId: String? = null,
)

@Serializable
data class Team(
    val id: String,
    val name: String,
    val isDefault: Boolean? = null,
    val photoId: String? = null,
) {
    /**
     * The default team is stored as "Default" but presented as the localized
     * "Your Penpot", matching the web UI — the UI layer resolves the string.
     */
    val isDefaultTeam: Boolean get() = isDefault == true
}

@Serializable
data class Project(
    val id: String,
    val name: String,
    val teamId: String? = null,
    /** Identifies the team's default "Drafts" project (its stored name is literally "Drafts"). */
    val isDefault: Boolean? = null,
    /** Per-profile pin state (from `get-projects`). */
    val isPinned: Boolean? = null,
    /** Non-deleted file count. Present only on `get-projects`, not `get-project-files`. */
    val count: Int? = null,
    /** Soft-delete marker; `get-projects` may include recoverable projects — filter these out. */
    val deletedAt: String? = null,
) {
    val isDefaultProject: Boolean get() = isDefault == true
    val isPinnedFlag: Boolean get() = isPinned == true
    val fileCount: Int get() = count ?: 0
}

/**
 * A built-in starter template offered by the server (`get-builtin-templates`).
 *
 * The command returns only an id and a display name — no thumbnail, description or preview
 * URL — so templates can only be listed by name. The id's sole use is `clone-template`.
 */
@Serializable
data class BuiltinTemplate(val id: String, val name: String) {

    /**
     * Preview image for the template. The API returns no image field, so the path is derived
     * from the id exactly as Penpot's own dashboard does (`images/thumbnails/template-<id>.jpg`).
     * Not every template ships one — `welcome` 404s on current servers — so callers must
     * tolerate a missing image and fall back to a placeholder.
     */
    fun thumbnailUrl(baseUrl: HttpUrl): HttpUrl =
        baseUrl.newBuilder().addPathSegments("images/thumbnails/template-$id.jpg").build()
}

/** A soft-deleted file from `get-team-deleted-files`, recoverable until [willBeDeletedAt]. */
@Serializable
data class DeletedFile(
    val id: String,
    val name: String,
    val projectId: String? = null,
    val modifiedAt: String? = null,
    val willBeDeletedAt: String? = null,
)

/** A single installed font variant (weight + style) from `get-font-variants`. */
@Serializable
data class FontVariant(
    val id: String,
    val teamId: String? = null,
    val fontId: String? = null,
    val fontFamily: String,
    val fontWeight: Int? = null,   // 100–950
    val fontStyle: String? = null, // "normal" | "italic"
    val variantName: String? = null,
    val createdAt: String? = null,
    val modifiedAt: String? = null,
)

/**
 * A file row from `get-project-files` / `get-team-shared-files`. As a data class, equality
 * compares every field — deliberately so: the UI diffing must notice e.g. an is-shared flip
 * after unpublishing, which id-only equality would miss (learned the hard way on iOS).
 */
@Serializable
data class FileListItem(
    val id: String,
    val name: String,
    val projectId: String? = null,
    val teamId: String? = null,
    val modifiedAt: String? = null,
    /**
     * Whether the file is published as a team shared library. Returned by `get-project-files`
     * and `get-team-shared-files`; null when an endpoint omits it.
     */
    val isShared: Boolean? = null,
)

// ── File data (for board geometry) ──────────────────────────────────────────

@Serializable
data class PenpotFile(
    val id: String,
    val name: String,
    val revn: Int? = null,
    val data: FileData? = null,
) {
    /** The file's pages in document order, each with its root-level boards. */
    val pages: List<PenpotPageSummary>
        get() {
            val index = data?.pagesIndex ?: return emptyList()
            // `data.pages` carries the authored page order; fall back to the index keys.
            val order = data.pages ?: index.keys.toList()
            return order.mapNotNull { pageId ->
                val page = index[pageId] ?: return@mapNotNull null
                val content = rootContent(page, pageId)
                PenpotPageSummary(
                    id = pageId,
                    name = page.name ?: "Page",
                    boards = content.first,
                    canvasObjectCount = content.second,
                )
            }
        }

    /** All root-level boards across every page, in page then top-to-bottom order. */
    val boards: List<Board> get() = pages.flatMap { it.boards }

    companion object {
        /**
         * Splits a page's direct root-frame children into boards and loose canvas objects.
         * Every direct child is exactly one of the two, so a page with content can never
         * look empty: shapes drawn straight on the canvas (and frames whose selrect failed
         * to decode) surface via canvasObjectCount. In real payloads the root frame is
         * self-parented, hence the explicit id check.
         */
        private fun rootContent(page: PenpotPage, pageId: String): Pair<List<Board>, Int> {
            val boards = mutableListOf<Board>()
            var canvasObjectCount = 0
            for ((objectId, shape) in page.objects) {
                if (objectId == Board.ROOT_FRAME_ID) continue
                if (shape.parentId != Board.ROOT_FRAME_ID) continue
                val selrect = shape.selrect
                if (shape.type == "frame" && selrect != null) {
                    boards += Board(id = objectId, pageId = pageId, name = shape.name ?: "Board", selrect = selrect)
                } else {
                    canvasObjectCount += 1
                }
            }
            // Stable-ish ordering: top-to-bottom, then left-to-right.
            boards.sortWith(compareBy({ it.selrect.y }, { it.selrect.x }))
            return boards to canvasObjectCount
        }
    }
}

/** A page within a file, with its root-level boards in display order. */
data class PenpotPageSummary(
    val id: String,
    val name: String,
    val boards: List<Board>,
    /**
     * Direct children of the root frame that are not surfaced as boards (shapes drawn
     * straight on the canvas). Penpot renders no thumbnails for these; they are only
     * viewable in the live canvas.
     */
    val canvasObjectCount: Int,
) {
    val hasContent: Boolean get() = boards.isNotEmpty() || canvasObjectCount > 0
}

@Serializable
data class FileData(
    val pagesIndex: Map<String, PenpotPage>? = null,
    val pages: List<String>? = null,
)

@Serializable
data class PenpotPage(
    val id: String? = null,
    val name: String? = null,
    val objects: Map<String, Shape>,
)

/**
 * Decoded defensively: a single shape with an unexpected field shape (e.g. a malformed
 * selrect) must not fail decoding of the whole file — see [ShapeSerializer].
 */
@Serializable(with = ShapeSerializer::class)
data class Shape(
    val id: String? = null,
    val name: String? = null,
    val type: String? = null,
    val frameId: String? = null,
    val parentId: String? = null,
    val selrect: Selrect? = null,
)

object ShapeSerializer : KSerializer<Shape> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("app.penpot.core.model.Shape")

    override fun deserialize(decoder: Decoder): Shape {
        val input = decoder as? JsonDecoder
            ?: throw IllegalStateException("Shape can only be decoded from JSON")
        val element = input.decodeJsonElement()
        val obj = element as? JsonObject ?: return Shape()

        fun str(key: String): String? {
            val value = obj[key] ?: return null
            if (value is JsonNull) return null
            return (value as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        }

        val selrect = obj["selrect"]?.let { raw ->
            runCatching { PenpotJson.decodeFromJsonElement<Selrect>(raw) }.getOrNull()
        }
        return Shape(
            id = str("id"),
            name = str("name"),
            type = str("type"),
            frameId = str("frameId"),
            parentId = str("parentId"),
            selrect = selrect,
        )
    }

    override fun serialize(encoder: Encoder, value: Shape) {
        throw UnsupportedOperationException("Shape is decode-only")
    }
}

/** A root-level board (frame) extracted from a file. */
data class Board(
    val id: String,
    val pageId: String,
    val name: String,
    val selrect: Selrect,
) {
    companion object {
        const val ROOT_FRAME_ID = "00000000-0000-0000-0000-000000000000"
    }
}

// ── Comments ────────────────────────────────────────────────────────────────

@Serializable
data class CommentThread(
    val id: String,
    val fileId: String? = null,
    val pageId: String? = null,
    val frameId: String? = null,
    val position: Point? = null,
    val content: String? = null,
    val isResolved: Boolean? = null,
    val countComments: Int? = null,
    val countUnreadComments: Int? = null,
    val ownerId: String? = null,
    val seqn: Int? = null,
    val createdAt: String? = null,
    val modifiedAt: String? = null,

    // Joined by the server on thread queries, so a thread can be rendered outside its file.
    val teamId: String? = null,
    val fileName: String? = null,
    val ownerFullname: String? = null,
    val ownerPhotoId: String? = null,
) {
    val unreadCount: Int get() = countUnreadComments ?: 0
}

@Serializable
data class Comment(
    val id: String,
    val threadId: String? = null,
    val ownerId: String? = null,
    val content: String? = null,
    val createdAt: String? = null,
)

/**
 * `get-profiles-for-file-comments` may return either a list of profiles or a map keyed
 * by profile id (where the value object may omit its own `id`). This normalizes both
 * shapes into [byId].
 */
@Serializable(with = ProfilesResponseSerializer::class)
data class ProfilesResponse(val byId: Map<String, Profile>)

@Serializable
private data class ProfileDto(
    val id: String? = null,
    val fullname: String? = null,
    val email: String? = null,
    val photoId: String? = null,
)

object ProfilesResponseSerializer : KSerializer<ProfilesResponse> {
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("app.penpot.core.model.ProfilesResponse")

    override fun deserialize(decoder: Decoder): ProfilesResponse {
        val input = decoder as? JsonDecoder
            ?: throw IllegalStateException("ProfilesResponse can only be decoded from JSON")
        val element = input.decodeJsonElement()
        val result = mutableMapOf<String, Profile>()
        when (element) {
            is JsonObject -> for ((key, raw) in element) {
                val dto = runCatching { PenpotJson.decodeFromJsonElement<ProfileDto>(raw) }.getOrNull() ?: continue
                val id = dto.id ?: key
                result[id] = Profile(id = id, fullname = dto.fullname, email = dto.email, photoId = dto.photoId)
            }
            is JsonArray -> for (raw in element) {
                val dto = runCatching { PenpotJson.decodeFromJsonElement<ProfileDto>(raw) }.getOrNull() ?: continue
                val id = dto.id ?: continue
                result[id] = Profile(id = id, fullname = dto.fullname, email = dto.email, photoId = dto.photoId)
            }
            else -> Unit
        }
        return ProfilesResponse(result)
    }

    override fun serialize(encoder: Encoder, value: ProfilesResponse) {
        throw UnsupportedOperationException("ProfilesResponse is decode-only")
    }
}
