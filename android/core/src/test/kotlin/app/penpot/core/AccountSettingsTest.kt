package app.penpot.core

import app.penpot.core.model.AccessToken
import app.penpot.core.model.CommentNotification
import app.penpot.core.model.InviteNotification
import app.penpot.core.model.NotificationSettings
import app.penpot.core.model.PenpotLanguage
import app.penpot.core.model.Profile
import app.penpot.core.model.ProfilesResponse
import app.penpot.core.network.EmailChangeResult
import app.penpot.core.network.PenpotClient
import app.penpot.core.network.PenpotJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the iOS AccountSettingsTests — decoding + helpers, pure, no network. */
class AccountSettingsTest {

    private inline fun <reified T> decode(json: String): T = PenpotJson.decodeFromString(json)

    // ── Profile back-compat ─────────────────────────────────────────────────

    // The theme/lang/props fields are optional; a legacy payload without them must still decode.
    @Test
    fun profileDecodesWithoutNewFields() {
        val profile = decode<Profile>(
            """{"id":"p1","fullname":"Test User","email":"user@example.com","photoId":"ph1"}""",
        )
        assertEquals("p1", profile.id)
        assertEquals("Test User", profile.fullname)
        assertNull(profile.theme)
        assertNull(profile.lang)
        assertNull(profile.props)
    }

    @Test
    fun profileDecodesWithPropsAndTheme() {
        val json = """
        {
          "id": "p1", "fullname": "Test User", "email": "user@example.com", "theme": "dark",
          "props": {
            "notifications": {"dashboardComments": "partial", "emailComments": "none", "emailInvites": "all"},
            "newsletterUpdates": true, "newsletterNews": false
          }
        }
        """
        val profile = decode<Profile>(json)
        assertEquals("dark", profile.theme)
        assertEquals(CommentNotification.PARTIAL, profile.props?.notifications?.dashboardComments)
        assertEquals(CommentNotification.NONE, profile.props?.notifications?.emailComments)
        assertEquals(InviteNotification.ALL, profile.props?.notifications?.emailInvites)
        assertEquals(true, profile.props?.newsletterUpdates)
        assertEquals(false, profile.props?.newsletterNews)
    }

    // `get-profiles-for-file-comments` returns either a map (id may live only in the key)
    // or an array; both shapes normalize into byId.
    @Test
    fun profilesResponseDecodesBothShapes() {
        val map = decode<ProfilesResponse>(
            """{"u1":{"fullname":"A","email":"a@x.de"},"u2":{"id":"u2b","fullname":"B"}}""",
        )
        assertEquals("A", map.byId["u1"]?.fullname)   // id defaults to the map key
        assertEquals("B", map.byId["u2b"]?.fullname)  // explicit id wins

        val array = decode<ProfilesResponse>(
            """[{"id":"u1","fullname":"A"},{"id":"u2","fullname":"B"}]""",
        )
        assertEquals(2, array.byId.size)
        assertEquals("A", array.byId["u1"]?.fullname)
    }

    // ── Notifications ───────────────────────────────────────────────────────

    @Test
    fun notificationSettingsDecodesCamelCase() {
        val s = decode<NotificationSettings>(
            """{"dashboardComments":"all","emailComments":"partial","emailInvites":"none"}""",
        )
        assertEquals(CommentNotification.ALL, s.dashboardComments)
        assertEquals(CommentNotification.PARTIAL, s.emailComments)
        assertEquals(InviteNotification.NONE, s.emailInvites)
    }

    // Missing keys must fall back to Penpot's default rather than throwing.
    @Test
    fun notificationSettingsDefaultsMissingKeysToAll() {
        val s = decode<NotificationSettings>("""{"emailComments":"none"}""")
        assertEquals(CommentNotification.ALL, s.dashboardComments)
        assertEquals(CommentNotification.NONE, s.emailComments)
        assertEquals(InviteNotification.ALL, s.emailInvites)
    }

    // ── Access tokens ───────────────────────────────────────────────────────

    @Test
    fun accessTokenListItemHasNoSecret() {
        val token = decode<AccessToken>(
            """{"id":"t1","name":"CI","createdAt":"2026-01-01T00:00:00Z","expiresAt":null}""",
        )
        assertEquals("CI", token.name)
        assertNull(token.token)
        assertNull(token.expiresAt)
    }

    @Test
    fun accessTokenCreateResponseHasSecret() {
        val token = decode<AccessToken>("""{"id":"t1","name":"CI","token":"penpat-secret-xyz"}""")
        assertEquals("penpat-secret-xyz", token.token)
    }

    // ── request-email-change dual response ──────────────────────────────────

    // Empty 200 bodies are substituted with "null" by PenpotClient.send; the nullable decodes to null.
    @Test
    fun emailChangeResultDecodesNullAndChanged() {
        val sentEmail = decode<EmailChangeResult?>("null")
        assertNull(sentEmail?.changed)

        val changed = decode<EmailChangeResult?>("""{"changed":true}""")
        assertEquals(true, changed?.changed)
    }

    // ── Languages ───────────────────────────────────────────────────────────

    @Test
    fun languageTableIsWellFormed() {
        assertEquals(34, PenpotLanguage.all.size)
        assertEquals("codes must be unique", 34, PenpotLanguage.all.map { it.penpotCode }.toSet().size)
        assertEquals(6, PenpotLanguage.appLocalizedLanguages.size)
        // Chinese script codes are special-cased (not a simple underscore→hyphen).
        assertEquals("zh-Hans", PenpotLanguage.all.first { it.penpotCode == "zh_cn" }.tag)
        assertEquals("pt-BR", PenpotLanguage.all.first { it.penpotCode == "pt_br" }.tag)
    }

    // ── Multipart framing (update-profile-photo) ────────────────────────────

    @Test
    fun multipartBodyFraming() {
        val payload = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte()) // JPEG magic bytes
        val body = PenpotClient.multipartBody(
            boundary = "BND", field = "file",
            filename = "avatar.jpg", mimeType = "image/jpeg", data = payload,
        )
        val text = body.toString(Charsets.ISO_8859_1)
        assertTrue(text.startsWith("--BND\r\n"))
        assertTrue(text.contains("""Content-Disposition: form-data; name="file"; filename="avatar.jpg""""))
        assertTrue(text.contains("Content-Type: image/jpeg\r\n\r\n"))
        assertTrue(text.endsWith("\r\n--BND--\r\n"))
    }
}
