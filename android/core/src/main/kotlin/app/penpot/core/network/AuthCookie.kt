package app.penpot.core.network

import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * Persistence hooks the cookie jar needs; implemented by the app's SessionStore
 * (token in encrypted storage, server URL in plain preferences).
 */
interface TokenStore {
    var authToken: String?

    /** The Penpot server base URL string, e.g. `https://design.penpot.app`. */
    var serverUrl: String?
}

object AuthCookie {
    /** Penpot's session cookie, set by `login-with-password`. The app's only cookie. */
    const val NAME = "auth-token"

    /**
     * Rebuilds the session cookie for [server].
     *
     * The `Secure` flag is set **only** for https servers: a secure cookie is silently
     * withheld from plain-http requests, which logged users out of the RPC client *and*
     * the canvas WebView against local dev servers on iOS. Regression-tested.
     */
    fun build(server: HttpUrl, token: String): Cookie {
        val builder = Cookie.Builder()
            .name(NAME)
            .value(token)
            .domain(server.host)
            .path("/")
        if (server.isHttps) builder.secure()
        return builder.build()
    }

    /** `Set-Cookie`-style header value for handing the cookie to Android's WebView CookieManager. */
    fun headerValue(server: HttpUrl, token: String): String =
        buildString {
            append(NAME).append('=').append(token).append("; Path=/")
            if (server.isHttps) append("; Secure")
        }
}

/**
 * Cookie jar for exactly one cookie: the Penpot `auth-token`.
 *
 * Backed by [TokenStore] so the session survives restarts. Only talks to the configured
 * server host — the token is never attached to (or captured from) any other host, e.g.
 * an absolute asset URL pointing at a storage backend.
 */
class SessionCookieJar(private val tokens: TokenStore) : CookieJar {

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        val host = serverHost() ?: return
        if (url.host != host) return
        val cookie = cookies.firstOrNull { it.name == AuthCookie.NAME } ?: return
        tokens.authToken = cookie.value.ifEmpty { null }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val host = serverHost() ?: return emptyList()
        if (url.host != host) return emptyList()
        val token = tokens.authToken ?: return emptyList()
        // We own the send decision here: the token is sent over http too (local dev
        // servers) — see the AuthCookie.build secure-flag note.
        return listOf(AuthCookie.build(url, token))
    }

    private fun serverHost(): String? = tokens.serverUrl?.toHttpUrlOrNull()?.host
}
