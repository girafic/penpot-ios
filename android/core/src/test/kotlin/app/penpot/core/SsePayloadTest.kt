package app.penpot.core

import app.penpot.core.network.PenpotClient
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** SSE body parsing + export-payload URL scraping (statics of PenpotClient). */
class SsePayloadTest {

    private val base = "https://design.penpot.app".toHttpUrl()

    @Test
    fun endPayloadIsExtracted() {
        val body = "event: progress\ndata: 1\n\nevent: end\ndata: [\"~#'\",\"https://x/assets/by-id/abc\"]\n\n"
        assertEquals("[\"~#'\",\"https://x/assets/by-id/abc\"]", PenpotClient.sseEndPayload(body))
    }

    @Test
    fun multiLineDataIsJoined() {
        val body = "event: end\ndata: line1\ndata: line2\n\n"
        assertEquals("line1\nline2", PenpotClient.sseEndPayload(body))
    }

    @Test
    fun errorEventYieldsNull() {
        val body = "event: error\ndata: boom\n\nevent: end\ndata: payload\n\n"
        assertNull(PenpotClient.sseEndPayload(body))
    }

    @Test
    fun missingEndYieldsNull() {
        assertNull(PenpotClient.sseEndPayload("event: progress\ndata: 1\n\n"))
    }

    @Test
    fun streamWithoutTrailingBlankLineStillCommits() {
        assertEquals("payload", PenpotClient.sseEndPayload("event: end\ndata: payload"))
    }

    @Test
    fun absoluteUrlIsScrapedFromTransitPayload() {
        val url = PenpotClient.assetUrl("""["~#'","https://cdn.example.com/assets/by-id/abc-123"]""", base)
        assertEquals("https://cdn.example.com/assets/by-id/abc-123", url.toString())
    }

    @Test
    fun relativeAssetPathResolvesAgainstBase() {
        val url = PenpotClient.assetUrl("""["~#'","/assets/by-id/abc-123"]""", base)
        assertEquals("https://design.penpot.app/assets/by-id/abc-123", url.toString())
    }

    @Test
    fun garbagePayloadYieldsNull() {
        assertNull(PenpotClient.assetUrl("no url here", base))
    }
}
