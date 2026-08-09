package app.penpot.android.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.penpot.core.model.Profile
import app.penpot.core.network.PenpotClient
import app.penpot.core.network.PenpotError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient

enum class AppPhase { LOADING, LOGIN, AUTHENTICATED }

/**
 * Auth/session state machine — the Android port of the iOS `AppState`.
 *
 * Application-scoped (survives configuration changes). The invariant that matters:
 * only a genuine 401 ([PenpotError.Unauthorized]) may end the session. 403 is a
 * Cloudflare challenge and any other failure is transient — both keep the user
 * logged in.
 */
class AppState(
    private val sessions: SessionStore,
    private val settings: AppSettings,
    private val http: OkHttpClient,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var phase: AppPhase by mutableStateOf(AppPhase.LOADING)
        private set

    var profile: Profile? by mutableStateOf(null)
        private set

    var client: PenpotClient? by mutableStateOf(null)
        private set

    /** At most one background profile resolve per launch (mirrors iOS). */
    private var profileResolveAttempted = false

    /**
     * Restores a persisted session. Validates the token with `get-teams` — deliberately
     * not `get-profile`, which is Cloudflare-challenged and would wrongly wipe a good
     * session. Only a 401 logs out; any other failure keeps the session.
     */
    suspend fun bootstrap() {
        val server = sessions.serverUrl?.toHttpUrlOrNull()
        val token = sessions.authToken
        if (server == null || token.isNullOrEmpty()) {
            phase = AppPhase.LOGIN
            return
        }
        val restored = PenpotClient(server, http)
        client = restored
        // Cached profile first, so comment-ownership checks work offline.
        profile = sessions.cachedProfile
        try {
            restored.teams()
            // Best-effort profile refresh; 403 from Cloudflare is expected and ignored.
            runCatching { restored.profile() }.getOrNull()?.let {
                profile = it
                sessions.cachedProfile = it
            }
            phase = AppPhase.AUTHENTICATED
        } catch (e: CancellationException) {
            throw e
        } catch (e: PenpotError.Unauthorized) {
            sessions.clear()
            client = null
            profile = null
            phase = AppPhase.LOGIN
        } catch (e: Exception) {
            // Transient/network/403 — stay authenticated rather than losing the session.
            phase = AppPhase.AUTHENTICATED
        }
    }

    /** Logs in and persists the session. Throws on failure (the login screen shows the error). */
    suspend fun login(server: HttpUrl, email: String, password: String) {
        // Clean slate for this host.
        sessions.authToken = null
        val fresh = PenpotClient(server, http)
        val loggedIn = fresh.login(email, password)
        sessions.serverUrl = server.toString()
        sessions.email = email
        sessions.cachedProfile = loggedIn
        client = fresh
        profile = loggedIn
        phase = AppPhase.AUTHENTICATED
    }

    /** Provisions a demo account (server flag `demo-users`) and logs in with it. */
    suspend fun loginWithDemoAccount(server: HttpUrl) {
        val throwaway = PenpotClient(server, http)
        val demo = throwaway.createDemoProfile()
        login(server, demo.email, demo.password)
    }

    /**
     * Recovers the profile (esp. the avatar `photoId`) from team membership, once per
     * launch, matching on the lowercased login email — the `get-profile` workaround.
     */
    suspend fun resolveProfileIfNeeded(teamId: String) {
        if (profileResolveAttempted || profile?.photoId != null) return
        profileResolveAttempted = true
        val client = client ?: return
        val email = sessions.email?.lowercase() ?: return
        runCatching {
            val me = client.teamMembers(teamId).firstOrNull { it.email?.lowercase() == email } ?: return
            val resolved = Profile(
                id = me.profileId ?: profile?.id ?: me.id,
                fullname = me.fullname ?: profile?.fullname,
                email = me.email ?: sessions.email,
                photoId = me.photoId,
            )
            profile = resolved
            sessions.cachedProfile = resolved
        }
    }

    /**
     * Re-resolves the profile from team membership. Used after avatar changes, because
     * `update-profile-photo` returns an empty body and the new `photoId` is only
     * observable via `get-team-members`.
     */
    suspend fun refreshProfile() {
        val client = client ?: return
        val email = sessions.email?.lowercase() ?: return
        runCatching {
            val team = client.teams().firstOrNull() ?: return
            val me = client.teamMembers(team.id).firstOrNull { it.email?.lowercase() == email } ?: return
            val old = profile
            val resolved = Profile(
                id = me.profileId ?: old?.id ?: me.id,
                fullname = me.fullname ?: old?.fullname,
                email = me.email ?: sessions.email,
                photoId = me.photoId,
                theme = old?.theme,
                lang = old?.lang,
                props = old?.props,
            )
            profile = resolved
            sessions.cachedProfile = resolved
        }
    }

    /** Replaces the in-memory profile (e.g. after a successful `update-profile`). */
    fun updateProfileLocally(updated: Profile) {
        profile = updated
        sessions.cachedProfile = updated
    }

    fun logout() {
        val closing = client
        scope.launch { closing?.logout() }   // fire-and-forget server-side logout
        sessions.clear()
        client = null
        profile = null
        profileResolveAttempted = false
        phase = AppPhase.LOGIN
    }
}
