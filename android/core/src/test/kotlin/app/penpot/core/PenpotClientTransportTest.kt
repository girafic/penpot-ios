package app.penpot.core

import app.penpot.core.model.Profile
import app.penpot.core.network.EmailChangeResult
import app.penpot.core.network.PenpotClient
import app.penpot.core.network.PenpotError
import app.penpot.core.network.SessionCookieJar
import app.penpot.core.network.TokenStore
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** End-to-end transport semantics against a local mock server. */
class PenpotClientTransportTest {

    private class FakeTokenStore(
        override var authToken: String? = null,
        override var serverUrl: String? = null,
    ) : TokenStore

    private lateinit var server: MockWebServer
    private lateinit var store: FakeTokenStore
    private lateinit var client: PenpotClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        store = FakeTokenStore(authToken = "tok", serverUrl = server.url("/").toString())
        client = PenpotClient(
            baseUrl = server.url("/"),
            http = OkHttpClient.Builder().cookieJar(SessionCookieJar(store)).build(),
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun queryUsesKebabCaseParamsAndSendsAuthCookie() = runTest {
        server.enqueue(MockResponse().setBody("""[]"""))
        client.teamMembers("team-1")
        val recorded = server.takeRequest()
        assertEquals("/api/rpc/command/get-team-members?team-id=team-1", recorded.path)
        assertEquals("GET", recorded.method)
        assertEquals("application/json", recorded.getHeader("Accept"))
        assertTrue(recorded.getHeader("Cookie").orEmpty().contains("auth-token=tok"))
    }

    @Test
    fun mutationPostsKebabCaseJsonBody() = runTest {
        server.enqueue(MockResponse().setBody("""{"id":"p1","fullname":"Demo"}"""))
        val profile: Profile = client.login("a@b.c", "pw")
        assertEquals("p1", profile.id)
        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertTrue(recorded.getHeader("Content-Type").orEmpty().startsWith("application/json"))
        assertEquals("""{"email":"a@b.c","password":"pw"}""", recorded.body.readUtf8())
    }

    @Test
    fun loginCapturesSetCookie() = runTest {
        server.enqueue(
            MockResponse()
                .setBody("""{"id":"p1"}""")
                .addHeader("Set-Cookie", "auth-token=new-session; Path=/; HttpOnly"),
        )
        client.login("a@b.c", "pw")
        assertEquals("new-session", store.authToken)
    }

    @Test
    fun status401MapsToUnauthorized() = runTest {
        server.enqueue(MockResponse().setResponseCode(401))
        try {
            client.teams()
            fail("expected Unauthorized")
        } catch (e: PenpotError.Unauthorized) {
            // expected — the only status that may log the user out
        }
    }

    @Test
    fun status403MapsToForbiddenNotUnauthorized() = runTest {
        server.enqueue(MockResponse().setResponseCode(403).setBody("cloudflare challenge"))
        try {
            client.teams()
            fail("expected Forbidden")
        } catch (e: PenpotError.Forbidden) {
            // expected — must never be treated as "session invalid"
        }
    }

    @Test
    fun serverErrorCarriesStatusAndHint() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(400)
                .setBody("""{"type":"validation","code":"invalid-email","hint":"email is invalid"}"""),
        )
        try {
            client.teams()
            fail("expected Server")
        } catch (e: PenpotError.Server) {
            assertEquals(400, e.status)
            assertEquals("email is invalid", e.serverMessage)
        }
    }

    @Test
    fun emptySuccessBodyDecodesAsNull() = runTest {
        server.enqueue(MockResponse().setResponseCode(200))
        val result: EmailChangeResult? = client.mutation(
            "request-email-change",
            buildJsonObject { put("email", "x@y.z") },
        )
        assertNull(result)
    }

    @Test
    fun sseMutationSucceedsOnEndEvent() = runTest {
        server.enqueue(MockResponse().setBody("event: progress\ndata: 1\n\nevent: end\ndata: ok\n\n"))
        client.sseMutation("clone-template", buildJsonObject { put("template-id", "t") })
        val recorded = server.takeRequest()
        assertEquals("text/event-stream", recorded.getHeader("Accept"))
    }

    @Test
    fun sseMutationFailsOnErrorEvent() = runTest {
        server.enqueue(MockResponse().setBody("event: error\ndata: boom\n\n"))
        try {
            client.sseMutation("clone-template", buildJsonObject { put("template-id", "t") })
            fail("expected Server error")
        } catch (e: PenpotError.Server) {
            assertTrue(e.body.orEmpty().contains("error"))
        }
    }

    @Test
    fun exportBinfileFollowsSsePayloadUrl() = runTest {
        val assetPath = "/assets/by-id/abc-123"
        server.enqueue(
            MockResponse().setBody("event: end\ndata: [\"~#'\",\"${server.url(assetPath)}\"]\n\n"),
        )
        server.enqueue(MockResponse().setBody("PENPOT-BINARY"))
        val bytes = client.exportBinfile("file-1")
        assertEquals("PENPOT-BINARY", bytes.decodeToString())
        server.takeRequest() // the SSE command
        assertEquals(assetPath, server.takeRequest().path)
    }

    @Test
    fun decodingFailureMapsToDecodingError() = runTest {
        server.enqueue(MockResponse().setBody("""{"unexpected":"shape"}"""))
        try {
            client.teams()
            fail("expected Decoding")
        } catch (e: PenpotError.Decoding) {
            // expected
        }
    }
}
