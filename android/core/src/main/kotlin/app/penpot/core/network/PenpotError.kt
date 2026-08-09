package app.penpot.core.network

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * Error surface of [PenpotClient]. Mirrors the iOS `PenpotError`:
 *
 * - [Unauthorized] (HTTP 401) is the **only** case that means "session invalid" — callers
 *   may log the user out on it.
 * - [Forbidden] (HTTP 403) is explicitly *not* an auth failure: Penpot Cloud sits behind
 *   Cloudflare, whose bot challenge answers 403 to some commands (`get-profile`) for
 *   non-browser clients. Callers must never treat it as "logged out".
 */
sealed class PenpotError(message: String? = null, cause: Throwable? = null) : Exception(message, cause) {

    data object InvalidUrl : PenpotError("Invalid URL") {
        private fun readResolve(): Any = InvalidUrl
    }

    data object InvalidResponse : PenpotError("Invalid response") {
        private fun readResolve(): Any = InvalidResponse
    }

    data object Unauthorized : PenpotError("Unauthorized") {
        private fun readResolve(): Any = Unauthorized
    }

    data object Forbidden : PenpotError("Forbidden") {
        private fun readResolve(): Any = Forbidden
    }

    class Server(val status: Int, val body: String?) : PenpotError("Request failed ($status)") {
        /**
         * Best human-readable message from the error body: the first non-empty of the JSON
         * fields `hint`, `code`, `type` (the huge `explain` field is deliberately ignored);
         * a non-JSON body is trimmed and truncated. Null when the body carries nothing usable.
         */
        val serverMessage: String? get() = extractMessage(body)

        companion object {
            private const val MAX_RAW_LENGTH = 200

            fun extractMessage(body: String?): String? {
                val trimmed = body?.trim().orEmpty()
                if (trimmed.isEmpty()) return null
                val obj = runCatching { PenpotJson.parseToJsonElement(trimmed) }.getOrNull() as? JsonObject
                if (obj != null) {
                    for (key in listOf("hint", "code", "type")) {
                        val value = obj[key]
                        if (value is JsonPrimitive && value !is JsonNull) {
                            val content = value.contentOrNull?.trim()
                            if (!content.isNullOrEmpty()) return content
                        }
                    }
                    return null
                }
                return if (trimmed.length <= MAX_RAW_LENGTH) trimmed else trimmed.take(MAX_RAW_LENGTH) + "…"
            }
        }
    }

    class Decoding(cause: Throwable) : PenpotError("Response decoding failed", cause)
}
