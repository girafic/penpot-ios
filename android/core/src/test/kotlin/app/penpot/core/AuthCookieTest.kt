package app.penpot.core

import app.penpot.core.network.AuthCookie
import app.penpot.core.network.SessionCookieJar
import app.penpot.core.network.TokenStore
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of the iOS SessionCookieTests: the `Secure` flag must depend on the server
 * scheme, or the cookie is silently withheld over plain http and both the RPC client
 * and the canvas WebView lose their session against local dev servers.
 */
class AuthCookieTest {

    private class FakeTokenStore(
        override var authToken: String? = null,
        override var serverUrl: String? = null,
    ) : TokenStore

    private val token = "test-token-value"

    @Test
    fun httpServerCookieIsNotMarkedSecure() {
        val cookie = AuthCookie.build("http://localhost:3450".toHttpUrl(), token)
        assertFalse("An http server's cookie must not be secure, or it is never sent.", cookie.secure)
        assertEquals("auth-token", cookie.name)
        assertEquals(token, cookie.value)
        assertEquals("localhost", cookie.domain)
    }

    @Test
    fun httpsServerCookieIsMarkedSecure() {
        val cookie = AuthCookie.build("https://design.penpot.app".toHttpUrl(), token)
        assertTrue(cookie.secure)
        assertEquals("design.penpot.app", cookie.domain)
    }

    // The end-to-end symptom: the jar must actually hand the cookie back for an http URL,
    // which is what the RPC client and canvas WebView rely on.
    @Test
    fun cookieIsDeliveredToPlainHttpUrl() {
        val jar = SessionCookieJar(FakeTokenStore(authToken = token, serverUrl = "http://localhost:3450"))
        val cookies = jar.loadForRequest("http://localhost:3450/api/rpc/command/get-teams".toHttpUrl())
        assertEquals(listOf("auth-token"), cookies.map { it.name })
        assertEquals(token, cookies.single().value)
    }

    @Test
    fun cookieIsNotLeakedToOtherHosts() {
        val jar = SessionCookieJar(FakeTokenStore(authToken = token, serverUrl = "https://design.penpot.app"))
        assertTrue(jar.loadForRequest("https://evil.example.com/".toHttpUrl()).isEmpty())
        assertEquals(1, jar.loadForRequest("https://design.penpot.app/assets/by-id/x".toHttpUrl()).size)
    }

    @Test
    fun setCookieFromLoginIsCaptured() {
        val store = FakeTokenStore(serverUrl = "https://design.penpot.app")
        val jar = SessionCookieJar(store)
        val url = "https://design.penpot.app/api/rpc/command/login-with-password".toHttpUrl()
        val cookie = Cookie.Builder()
            .name("auth-token").value("fresh-token")
            .domain("design.penpot.app").path("/").secure()
            .build()
        jar.saveFromResponse(url, listOf(cookie))
        assertEquals("fresh-token", store.authToken)
    }

    @Test
    fun setCookieFromForeignHostIsIgnored() {
        val store = FakeTokenStore(serverUrl = "https://design.penpot.app")
        val jar = SessionCookieJar(store)
        val cookie = Cookie.Builder()
            .name("auth-token").value("evil").domain("evil.example.com").path("/")
            .build()
        jar.saveFromResponse("https://evil.example.com/".toHttpUrl(), listOf(cookie))
        assertNull(store.authToken)
    }

    @Test
    fun headerValueForWebViewMatchesSchemeRule() {
        assertEquals(
            "auth-token=t; Path=/; Secure",
            AuthCookie.headerValue("https://design.penpot.app".toHttpUrl(), "t"),
        )
        assertEquals(
            "auth-token=t; Path=/",
            AuthCookie.headerValue("http://localhost:9001".toHttpUrl(), "t"),
        )
    }
}
