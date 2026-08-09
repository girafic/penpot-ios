package app.penpot.core.network

import app.penpot.core.model.AccessToken
import app.penpot.core.model.NotificationSettings
import app.penpot.core.model.Profile
import app.penpot.core.model.ProfileProps
import app.penpot.core.model.TokenExpiration
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

// Account / profile settings commands.
//
// Two hard API constraints this app works around (mirroring the iOS client):
//
// * `get-profile` is blocked by a Cloudflare challenge for non-browser clients (both GET
//   and POST), so we never read the profile directly. Notification prefs are instead read
//   via a no-op `update-profile-props` (a POST, which is not blocked).
// * `update-profile` rewrites `fullname`+`lang`+`theme` as a set and the API never returns
//   `lang`/`theme`, so any omitted field is nulled. Callers must send every field they want
//   to preserve. Because we can't read the current `lang`, name/language edits are treated
//   as a deliberate "set all" action.

// ── Profile ─────────────────────────────────────────────────────────────────

/**
 * Updates the profile. `fullname` is always required by Penpot. Omitting `lang` or
 * `theme` **nulls** them server-side, so pass current values for anything you're not
 * intentionally changing.
 */
suspend fun PenpotClient.updateProfile(fullname: String, lang: String? = null, theme: String? = null): Profile =
    mutation("update-profile", buildJsonObject {
        put("fullname", fullname)
        if (lang != null) put("lang", lang)
        if (theme != null) put("theme", theme)
    })

/**
 * Uploads a new avatar (multipart). [mimeType] must be image/jpeg, image/png or image/webp.
 * Penpot returns an empty body here, so the new `photoId` must be recovered separately
 * (see the app's AppState.refreshProfile).
 */
suspend fun PenpotClient.updateProfilePhoto(data: ByteArray, mimeType: String, filename: String) {
    uploadUnit("update-profile-photo", data, filename, mimeType)
}

/** Resets the avatar to Penpot's default. */
suspend fun PenpotClient.deleteProfilePhoto() {
    mutationUnit("delete-profile-photo")
}

/**
 * Requests an email change. On an SMTP-enabled server (e.g. design.penpot.app) this
 * sends a confirmation link and returns an empty body → `false`. On an SMTP-disabled
 * server it changes immediately and returns `{changed: true}` → `true`.
 */
suspend fun PenpotClient.requestEmailChange(email: String): Boolean {
    val result: EmailChangeResult? =
        mutation("request-email-change", buildJsonObject { put("email", email) })
    return result?.changed == true
}

/**
 * Permanently deletes the account. Invalidates the session on success. Fails with a
 * server error if the user still owns teams that have other members.
 */
suspend fun PenpotClient.deleteProfile() {
    mutationUnit("delete-profile")
}

// ── Password ────────────────────────────────────────────────────────────────

/** Changes the password. [old] is required for accounts that already have one. */
suspend fun PenpotClient.updatePassword(new: String, old: String?) {
    mutationUnit("update-profile-password", buildJsonObject {
        put("password", new)
        if (old != null) put("old-password", old)
    })
}

// ── Notifications ───────────────────────────────────────────────────────────

/**
 * Writes all three notification prefs (Penpot requires the full set). Params are
 * kebab-case even though they read back camelCase.
 */
suspend fun PenpotClient.updateNotifications(settings: NotificationSettings) {
    mutationUnit("update-profile-notifications", buildJsonObject {
        put("dashboard-comments", settings.dashboardComments.raw)
        put("email-comments", settings.emailComments.raw)
        put("email-invites", settings.emailInvites.raw)
    })
}

/**
 * Reads the current notification prefs via a no-op `update-profile-props` merge, which
 * returns the props map and — unlike `get-profile` — is not Cloudflare-blocked.
 * Falls back to Penpot's defaults if none are set.
 */
suspend fun PenpotClient.fetchNotifications(): NotificationSettings {
    val props: ProfileProps = mutation("update-profile-props", buildJsonObject {
        putJsonObject("props") {}
    })
    return props.notifications ?: NotificationSettings()
}

/** Merges keys into the props bag (a JSON null value deletes a key). Returns the resulting props. */
suspend fun PenpotClient.updateProfileProps(props: JsonObject): ProfileProps =
    mutation("update-profile-props", buildJsonObject { put("props", props) })

// ── Access tokens ───────────────────────────────────────────────────────────

/**
 * Lists personal access tokens. `get-access-tokens` reaches the API over plain GET
 * (it is not among the Cloudflare-challenged endpoints).
 */
suspend fun PenpotClient.accessTokens(): List<AccessToken> = query("get-access-tokens")

/** Creates a token. The full secret is present only on the returned object — capture it now. */
suspend fun PenpotClient.createAccessToken(name: String, expiration: TokenExpiration): AccessToken =
    mutation("create-access-token", buildJsonObject {
        put("name", name)
        expiration.param?.let { put("expiration", it) }
    })

suspend fun PenpotClient.deleteAccessToken(id: String) {
    mutationUnit("delete-access-token", buildJsonObject { put("id", id) })
}

/**
 * Response of `request-email-change`: `{changed: true}` when applied immediately, or an
 * empty/null body when a confirmation email was sent instead.
 */
@Serializable
data class EmailChangeResult(val changed: Boolean? = null)
