package app.penpot.core.network

import app.penpot.core.model.Comment
import app.penpot.core.model.CommentThread
import app.penpot.core.model.DemoProfile
import app.penpot.core.model.PenpotDate
import app.penpot.core.model.PenpotFile
import app.penpot.core.model.Point
import app.penpot.core.model.Profile
import app.penpot.core.model.ProfilesResponse
import app.penpot.core.model.Project
import app.penpot.core.model.FileListItem
import app.penpot.core.model.Team
import app.penpot.core.model.TeamMember
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.SocketTimeoutException
import java.util.UUID

/** Params for a mutation that takes none. */
val EmptyParams: JsonObject = JsonObject(emptyMap())

/**
 * Thin client over Penpot's RPC HTTP API (`{server}/api/rpc/command/<command>`).
 *
 * Query commands are issued as GET (params in the query string), mutation commands as
 * POST with a JSON body. Request params are **kebab-case** (`file-id`), responses are
 * **camelCase** — see [PenpotJson]. Authentication relies on the `auth-token` session
 * cookie that Penpot sets on `login-with-password`; the [OkHttpClient]'s cookie jar
 * (a [SessionCookieJar]) carries it automatically on subsequent requests.
 */
class PenpotClient(
    val baseUrl: HttpUrl,
    val http: OkHttpClient,
) {

    fun commandUrl(command: String): HttpUrl =
        baseUrl.newBuilder().addPathSegments("api/rpc/command/$command").build()

    // ── Generic transport ───────────────────────────────────────────────────

    /** GET query command. `params` keys are sent verbatim (kebab-case). */
    suspend inline fun <reified T> query(command: String, params: Map<String, String> = emptyMap()): T =
        send(queryRequest(command, params)) { PenpotJson.decodeFromString<T>(it) }

    /** POST mutation command with a JSON body. `params` keys are kebab-case. */
    suspend inline fun <reified T> mutation(command: String, params: JsonObject = EmptyParams): T =
        send(mutationRequest(command, params)) { PenpotJson.decodeFromString<T>(it) }

    /** POST mutation whose response body is irrelevant (often empty). */
    suspend fun mutationUnit(command: String, params: JsonObject = EmptyParams) {
        send(mutationRequest(command, params)) { }
    }

    fun queryRequest(command: String, params: Map<String, String>): Request {
        val url = commandUrl(command).newBuilder().apply {
            for ((key, value) in params) addQueryParameter(key, value)
        }.build()
        return Request.Builder()
            .url(url)
            .get()
            .header("Accept", "application/json")
            .build()
    }

    fun mutationRequest(command: String, params: JsonObject): Request =
        Request.Builder()
            .url(commandUrl(command))
            .post(params.toString().toRequestBody(JSON_MEDIA_TYPE))
            .header("Accept", "application/json")
            .build()

    suspend fun <T> send(request: Request, decode: (String) -> T): T {
        val (status, bytes) = transport(request)
        return when (status) {
            in 200..299 -> {
                // Some mutations (e.g. mark-as-read) return an empty body on success —
                // substitute JSON null so nullable results decode instead of throwing.
                val payload = if (bytes.isEmpty()) "null" else bytes.decodeToString()
                try {
                    decode(payload)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    throw PenpotError.Decoding(e)
                }
            }
            else -> throw errorForStatus(status, bytes)
        }
    }

    /**
     * Performs the request, retrying once on a transient transport failure.
     *
     * Penpot is served over HTTP/2 behind Cloudflare. An idle pooled connection can be
     * closed by the edge and then reused before the client notices; the request bytes
     * never reached the server, so an immediate retry on a fresh connection recovers
     * transparently. A brief timeout is treated the same way. (Mirrors the iOS handling
     * of NSURLErrorNetworkConnectionLost.)
     */
    suspend fun transport(request: Request): Pair<Int, ByteArray> = withContext(Dispatchers.IO) {
        try {
            executeOnce(request)
        } catch (e: IOException) {
            if (isRetriableTransportError(e)) executeOnce(request) else throw e
        }
    }

    private fun executeOnce(request: Request): Pair<Int, ByteArray> =
        http.newCall(request).execute().use { response ->
            response.code to (response.body?.bytes() ?: ByteArray(0))
        }

    private fun errorForStatus(status: Int, bytes: ByteArray): PenpotError = when (status) {
        401 -> PenpotError.Unauthorized
        // Not necessarily an auth failure — e.g. a Cloudflare bot challenge. Callers
        // must not treat this as "session invalid" and log the user out.
        403 -> PenpotError.Forbidden
        else -> PenpotError.Server(status, bytes.takeIf { it.isNotEmpty() }?.decodeToString())
    }

    // ── SSE commands ────────────────────────────────────────────────────────

    private fun sseRequest(command: String, params: JsonObject): Request =
        Request.Builder()
            .url(commandUrl(command))
            .post(params.toString().toRequestBody(JSON_MEDIA_TYPE))
            .header("Accept", "text/event-stream")
            .build()

    /**
     * POST mutation whose response is a server-sent-events stream (commands declared
     * `::sse/stream? true`, e.g. `restore-deleted-team-files`). Event payloads are
     * transit-encoded, so they aren't decoded — the call succeeds when the stream ends
     * with an `end` event and throws if the server emitted an `error` event instead.
     */
    suspend fun sseMutation(command: String, params: JsonObject) {
        val (status, bytes) = transport(sseRequest(command, params))
        if (status !in 200..299) throw errorForStatus(status, bytes)
        val body = bytes.decodeToString()
        val events = body.split("\n")
            .filter { it.startsWith("event:") }
            .map { it.removePrefix("event:").trim() }
        if ("end" !in events || "error" in events) {
            throw PenpotError.Server(status, body)
        }
    }

    /**
     * Runs an SSE command and returns the data payload of its terminal `end` event.
     * Penpot transit-encodes payloads, so the raw `data:` string is returned as-is for
     * the caller to parse.
     */
    suspend fun sseResult(command: String, params: JsonObject): String {
        val (status, bytes) = transport(sseRequest(command, params))
        if (status !in 200..299) throw errorForStatus(status, bytes)
        val body = bytes.decodeToString()
        return sseEndPayload(body) ?: throw PenpotError.Server(status, body)
    }

    // ── File export ─────────────────────────────────────────────────────────

    /**
     * Exports a file as a native Penpot binary (`.penpot`) and returns the archive bytes.
     *
     * `export-binfile` is an SSE command: the server builds the archive, stores it briefly
     * (~60 min) under `/assets/by-id/<id>`, and streams that URL back as the `end` payload —
     * which this then follows to download the bytes. The `version` param was removed in
     * Penpot 2.12, so it is deliberately not sent.
     */
    suspend fun exportBinfile(
        fileId: String,
        includeLibraries: Boolean = false,
        embedAssets: Boolean = false,
    ): ByteArray {
        val payload = sseResult("export-binfile", buildJsonObject {
            put("file-id", fileId)
            put("include-libraries", includeLibraries)
            put("embed-assets", embedAssets)
        })
        val url = assetUrl(payload, baseUrl) ?: throw PenpotError.InvalidResponse
        val request = Request.Builder().url(url).get().build()
        val (status, bytes) = transport(request)
        if (status !in 200..299) throw errorForStatus(status, bytes)
        return bytes
    }

    // ── Multipart transport ─────────────────────────────────────────────────

    /** POSTs a single-file `multipart/form-data` body (part name `file`), e.g. `update-profile-photo`. */
    suspend inline fun <reified T> upload(
        command: String,
        fileData: ByteArray,
        filename: String,
        mimeType: String,
    ): T {
        val boundary = "penpot.${UUID.randomUUID()}"
        val body = multipartBody(boundary, "file", filename, mimeType, fileData)
        val request = Request.Builder()
            .url(commandUrl(command))
            .post(body.toRequestBody("multipart/form-data; boundary=$boundary".toMediaType()))
            .header("Accept", "application/json")
            .build()
        return send(request) { PenpotJson.decodeFromString<T>(it) }
    }

    /** Like [upload], but ignores the response body (e.g. `update-profile-photo` returns none). */
    suspend fun uploadUnit(command: String, fileData: ByteArray, filename: String, mimeType: String) {
        val boundary = "penpot.${UUID.randomUUID()}"
        val body = multipartBody(boundary, "file", filename, mimeType, fileData)
        val request = Request.Builder()
            .url(commandUrl(command))
            .post(body.toRequestBody("multipart/form-data; boundary=$boundary".toMediaType()))
            .header("Accept", "application/json")
            .build()
        send(request) { }
    }

    // ── Auth ────────────────────────────────────────────────────────────────

    suspend fun login(email: String, password: String): Profile =
        mutation("login-with-password", buildJsonObject {
            put("email", email)
            put("password", password)
        })

    /** Blocked by Cloudflare for non-browser clients on Penpot Cloud — best-effort only. */
    suspend fun profile(): Profile = query("get-profile")

    /**
     * Provisions a throwaway demo account and returns its credentials. Requires no auth;
     * the caller logs in with the returned email/password. Only succeeds when the server
     * has the `demo-users` flag enabled.
     */
    suspend fun createDemoProfile(): DemoProfile = mutation("create-demo-profile")

    suspend fun logout() {
        try {
            mutationUnit("logout")
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Fire-and-forget: local session state is cleared regardless.
        }
    }

    // ── Teams / projects / files ────────────────────────────────────────────

    suspend fun teams(): List<Team> = query("get-teams")

    suspend fun teamMembers(teamId: String): List<TeamMember> =
        query("get-team-members", mapOf("team-id" to teamId))

    suspend fun projects(teamId: String): List<Project> =
        query("get-projects", mapOf("team-id" to teamId))

    suspend fun projectFiles(projectId: String): List<FileListItem> =
        query("get-project-files", mapOf("project-id" to projectId))

    suspend fun file(id: String): PenpotFile = query("get-file", mapOf("id" to id))

    /** Returns a map of board (frame) id → thumbnail media id. */
    suspend fun objectThumbnails(fileId: String): Map<String, String> {
        val raw: Map<String, String> =
            query("get-file-object-thumbnails", mapOf("file-id" to fileId))
        return frameThumbnails(raw)
    }

    // ── Comments ────────────────────────────────────────────────────────────

    suspend fun commentThreads(fileId: String): List<CommentThread> =
        query("get-comment-threads", mapOf("file-id" to fileId))

    suspend fun comments(threadId: String): List<Comment> =
        query("get-comments", mapOf("thread-id" to threadId))

    /**
     * Threads in a team that have comments the current user hasn't read yet.
     *
     * This is the only team-wide thread query Penpot offers. `get-comment-threads`
     * documents a `team-id` param but its implementation ignores it and requires `file-id`.
     */
    suspend fun unreadCommentThreads(teamId: String): List<CommentThread> =
        query("get-unread-comment-threads", mapOf("team-id" to teamId))

    /**
     * Unread threads across every team, newest first.
     *
     * One team failing is tolerated — its threads are simply missing — but if every team
     * fails the last error is rethrown, so callers don't render "nothing unread" for a
     * network outage or an expired session.
     */
    suspend fun unreadCommentThreads(teams: List<Team>): List<CommentThread> {
        if (teams.isEmpty()) return emptyList()
        val results: List<Result<List<CommentThread>>> = coroutineScope {
            teams.map { team ->
                async {
                    try {
                        Result.success(unreadCommentThreads(team.id))
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        Result.failure(e)
                    }
                }
            }.awaitAll()
        }
        val lastFailure = results.lastOrNull { it.isFailure }?.exceptionOrNull()
        if (lastFailure != null && results.all { it.isFailure }) throw lastFailure
        return results.mapNotNull { it.getOrNull() }
            .flatten()
            .sortedByDescending { PenpotDate.sortKey(it.modifiedAt ?: it.createdAt) }
    }

    /** Marks every given thread as read in one round trip. */
    suspend fun markThreadsRead(ids: List<String>) {
        if (ids.isEmpty()) return
        mutationUnit("mark-all-threads-as-read", buildJsonObject {
            put("threads", JsonArray(ids.map { JsonPrimitive(it) }))
        })
    }

    suspend fun commentProfiles(fileId: String): Map<String, Profile> =
        query<ProfilesResponse>("get-profiles-for-file-comments", mapOf("file-id" to fileId)).byId

    suspend fun createCommentThread(
        fileId: String,
        pageId: String,
        frameId: String,
        position: Point,
        content: String,
    ): CommentThread = mutation("create-comment-thread", buildJsonObject {
        put("file-id", fileId)
        put("page-id", pageId)
        put("frame-id", frameId)
        putJsonObject("position") {
            put("x", position.x)
            put("y", position.y)
        }
        put("content", content)
    })

    suspend fun createComment(threadId: String, content: String): Comment =
        mutation("create-comment", buildJsonObject {
            put("thread-id", threadId)
            put("content", content)
        })

    /** Moves a comment thread's pin to a new canvas position. */
    suspend fun updateThreadPosition(id: String, frameId: String, position: Point) {
        mutationUnit("update-comment-thread-position", buildJsonObject {
            put("id", id)
            put("frame-id", frameId)
            putJsonObject("position") {
                put("x", position.x)
                put("y", position.y)
            }
        })
    }

    suspend fun setThreadResolved(id: String, isResolved: Boolean) {
        mutationUnit("update-comment-thread", buildJsonObject {
            put("id", id)
            put("is-resolved", isResolved)
        })
    }

    suspend fun markThreadRead(id: String) {
        mutationUnit("update-comment-thread-status", buildJsonObject { put("id", id) })
    }

    /** Edits the text of an existing comment. */
    suspend fun updateComment(id: String, content: String) {
        mutationUnit("update-comment", buildJsonObject {
            put("id", id)
            put("content", content)
        })
    }

    /** Deletes a single comment. Deleting a thread's first comment removes the whole thread. */
    suspend fun deleteComment(id: String) {
        mutationUnit("delete-comment", buildJsonObject { put("id", id) })
    }

    /** Deletes an entire comment thread and all of its comments. */
    suspend fun deleteCommentThread(id: String) {
        mutationUnit("delete-comment-thread", buildJsonObject { put("id", id) })
    }

    companion object {
        val JSON_MEDIA_TYPE = "application/json".toMediaType()

        private val ABSOLUTE_URL = Regex("""https?://[^\s"'\]\\]+""")
        private val RELATIVE_ASSET = Regex("""/assets/by-id/[^\s"'\]\\]+""")

        fun isRetriableTransportError(error: IOException): Boolean {
            if (error is SocketTimeoutException) return true
            // OkHttp surfaces a pooled connection reaped by the edge as one of these
            // when the request bytes never reached the server.
            val name = error.javaClass.simpleName
            if (name == "StreamResetException" || name == "ConnectionShutdownException") return true
            return error.message?.contains("unexpected end of stream") == true
        }

        /**
         * Pulls the `data:` payload of the terminating `end` event out of a buffered SSE
         * body, or null if the stream carried an `error` event or never reached `end`.
         */
        fun sseEndPayload(body: String): String? {
            var currentEvent: String? = null
            val currentData = mutableListOf<String>()
            var endPayload: String? = null
            var sawError = false

            fun commit() {
                if (currentEvent == "error") sawError = true
                if (currentEvent == "end" && currentData.isNotEmpty()) {
                    endPayload = currentData.joinToString("\n")
                }
                currentEvent = null
                currentData.clear()
            }

            for (line in body.split("\n")) {
                when {
                    line.isEmpty() -> commit()
                    line.startsWith("event:") -> currentEvent = line.removePrefix("event:").trim()
                    line.startsWith("data:") -> currentData += line.removePrefix("data:").trim()
                }
            }
            commit()
            return if (sawError) null else endPayload
        }

        /**
         * Recovers the download URL from an `export-binfile` SSE payload. The payload is
         * normally an absolute URL, but Penpot transit-encodes it (e.g. `["~#'","https://…"]`),
         * so we scan for the URL rather than decode transit. Falls back to resolving a
         * relative `/assets/by-id/…` path against the server base URL.
         */
        fun assetUrl(payload: String, baseUrl: HttpUrl): HttpUrl? {
            ABSOLUTE_URL.find(payload)?.let { return it.value.toHttpUrlOrNull() }
            RELATIVE_ASSET.find(payload)?.let { return baseUrl.resolve(it.value) }
            return null
        }

        /**
         * Penpot keys object thumbnails by a composite `"<file-id>/<page-id>/<frame-id>/frame"`.
         * Re-key by the bare frame id (unique within a file) so callers can look up by board id.
         * Tolerates an older bare-frame-id format too.
         */
        fun frameThumbnails(raw: Map<String, String>): Map<String, String> {
            val byFrame = mutableMapOf<String, String>()
            for ((key, mediaId) in raw) {
                val parts = key.split("/")
                when {
                    parts.size == 1 -> byFrame[key] = mediaId
                    parts.last() == "frame" && parts.size >= 2 -> byFrame[parts[parts.size - 2]] = mediaId
                }
            }
            return byFrame
        }

        /**
         * Builds an RFC 7578 multipart body with one file part. Kept static so it's
         * unit-testable without a network round-trip.
         */
        fun multipartBody(
            boundary: String,
            field: String,
            filename: String,
            mimeType: String,
            data: ByteArray,
        ): ByteArray {
            val head = buildString {
                append("--").append(boundary).append("\r\n")
                append("Content-Disposition: form-data; name=\"").append(field)
                append("\"; filename=\"").append(filename).append("\"\r\n")
                append("Content-Type: ").append(mimeType).append("\r\n\r\n")
            }.encodeToByteArray()
            val tail = "\r\n--$boundary--\r\n".encodeToByteArray()
            return head + data + tail
        }
    }
}
