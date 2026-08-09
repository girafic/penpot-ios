package app.penpot.android.app

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import app.penpot.core.model.Profile
import app.penpot.core.network.TokenStore

/**
 * Persists the session: server URL, last-used email and a cached profile in plain
 * preferences, the `auth-token` cookie value in encrypted preferences (the analog of
 * the iOS Keychain). Deliberately separate from [AppSettings] so app preferences
 * survive logout.
 */
class SessionStore(context: Context) : TokenStore {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("penpot.session", Context.MODE_PRIVATE)

    private val secure: SharedPreferences = createSecurePrefs(context)

    override var authToken: String?
        get() = secure.getString(KEY_AUTH_TOKEN, null)
        set(value) = secure.edit { putString(KEY_AUTH_TOKEN, value) }

    override var serverUrl: String?
        get() = prefs.getString(KEY_SERVER_URL, null)
        set(value) = prefs.edit { putString(KEY_SERVER_URL, value) }

    /** Last-used login email — a prefill convenience, deliberately not a secret. */
    var email: String?
        get() = prefs.getString(KEY_EMAIL, null)
        set(value) = prefs.edit { putString(KEY_EMAIL, value) }

    /**
     * Cached profile so the UI (comment ownership, avatar) works before — or without —
     * the profile being re-resolved from the network. `get-profile` is Cloudflare-blocked,
     * so this cache is the primary offline source.
     */
    var cachedProfile: Profile?
        get() {
            val id = prefs.getString(KEY_PROFILE_ID, null) ?: return null
            return Profile(
                id = id,
                fullname = prefs.getString(KEY_PROFILE_NAME, null),
                email = email,
                photoId = prefs.getString(KEY_PROFILE_PHOTO_ID, null),
            )
        }
        set(value) = prefs.edit {
            putString(KEY_PROFILE_ID, value?.id)
            putString(KEY_PROFILE_NAME, value?.fullname)
            putString(KEY_PROFILE_PHOTO_ID, value?.photoId)
        }

    /**
     * Clears the token and cached profile. Deliberately keeps [serverUrl] and [email]
     * so the login screen prefills after logout — same as iOS.
     */
    fun clear() {
        secure.edit { remove(KEY_AUTH_TOKEN) }
        prefs.edit {
            remove(KEY_PROFILE_ID)
            remove(KEY_PROFILE_NAME)
            remove(KEY_PROFILE_PHOTO_ID)
        }
    }

    companion object {
        const val DEFAULT_SERVER_URL = "https://design.penpot.app"

        private const val KEY_AUTH_TOKEN = "penpot.authToken"
        private const val KEY_SERVER_URL = "penpot.serverURL"
        private const val KEY_EMAIL = "penpot.email"
        private const val KEY_PROFILE_ID = "penpot.profileID"
        private const val KEY_PROFILE_NAME = "penpot.profileName"
        private const val KEY_PROFILE_PHOTO_ID = "penpot.profilePhotoID"

        private fun createSecurePrefs(context: Context): SharedPreferences = try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                "penpot.secure",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } catch (e: Exception) {
            // A corrupted keystore entry would otherwise brick login forever. The token is
            // a revocable session cookie; plain storage is an acceptable degraded mode.
            context.getSharedPreferences("penpot.secure.fallback", Context.MODE_PRIVATE)
        }
    }
}
