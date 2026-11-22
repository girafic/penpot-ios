import Foundation
import Observation
import WebKit

/// Global authentication + session state for the app.
///
/// Main-actor isolated: without it `bootstrap()` ran on a background executor, and a
/// `phase` change made there could be missed by SwiftUI, leaving the app on the splash
/// screen (seen on a loaded machine: session validated, no screen change).
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case loading
        case login
        case authenticated
    }

    var phase: Phase = .loading
    var profile: Profile?
    private(set) var client: PenpotClient?

    /// Attempts to restore a persisted session on launch.
    func bootstrap() async {
        guard let server = SessionStore.serverURL, SessionStore.authToken != nil else {
            phase = .login
            return
        }
        SessionStore.restoreCookie(for: server)
        let client = PenpotClient(baseURL: server)
        self.client = client
        // Make the cached profile available immediately (used e.g. for comment ownership).
        self.profile = SessionStore.cachedProfile
        do {
            // Validate the saved token with a reliable endpoint. We deliberately do NOT use
            // `get-profile` here: it sits behind a Cloudflare challenge that 403s non-browser
            // clients even with a valid token, which would wrongly wipe a good session.
            _ = try await client.teams()
            // Best-effort profile refresh; tolerate the Cloudflare block.
            if let fresh = try? await client.profile() {
                self.profile = fresh
                SessionStore.cacheProfile(fresh)
            }
            phase = .authenticated
        } catch PenpotError.unauthorized {
            // Only a genuine 401 means the token is no longer valid.
            SessionStore.clear()
            self.client = nil
            self.profile = nil
            phase = .login
        } catch {
            // Transient/forbidden error — keep the session rather than forcing re-login.
            phase = .authenticated
        }
    }

    /// Logs in with email + password against `server`.
    func login(server: URL, email: String, password: String) async throws {
        // Start from a clean cookie slate for this host.
        if let cookies = HTTPCookieStorage.shared.cookies(for: server) {
            cookies.forEach(HTTPCookieStorage.shared.deleteCookie)
        }
        let client = PenpotClient(baseURL: server)
        let profile = try await client.login(email: email, password: password)
        adoptSession(server: server, email: email, profile: profile, client: client)
    }

    /// Adopts an already-established session cookie (login, registration, email
    /// verification) as the app's authenticated state.
    func adoptSession(server: URL, email: String?, profile: Profile?, client: PenpotClient) {
        SessionStore.serverURL = server
        SessionStore.email = email
        SessionStore.captureCookie(for: server)
        if let profile { SessionStore.cacheProfile(profile) }
        self.client = client
        self.profile = profile
        phase = .authenticated
    }

    /// Registration path: the server set the auth cookie on `register-profile` /
    /// `verify-token` (not on `login-with-password`). Validate it per project
    /// convention with `get-teams` — NEVER `get-profile`, which Cloudflare blocks —
    /// then adopt; the profile is recovered from team membership when missing.
    func completeRegistration(server: URL, email: String, profile: Profile?, client: PenpotClient) async throws {
        _ = try await client.teams()   // throws unauthorized if no cookie landed
        adoptSession(server: server, email: email, profile: profile, client: client)
        if profile == nil {
            await refreshProfile()
        }
    }

    /// Creates a demo account on `server` and logs in with it. Reuses ``login(server:email:password:)``
    /// so session persistence and phase transition are identical to a normal login.
    func loginWithDemoAccount(server: URL) async throws {
        // create-demo-profile needs no auth cookie; a throwaway client is fine.
        let demo = try await PenpotClient(baseURL: server).createDemoProfile()
        try await login(server: server, email: demo.email, password: demo.password)
    }

    private var profileResolveAttempted = false

    /// Recovers the current user's profile (name + avatar) from team membership when it's
    /// missing — e.g. a session restored without `get-profile` (which Cloudflare blocks).
    /// Runs at most once per launch and only while the avatar is still unknown.
    func resolveProfileIfNeeded(teamID: String) async {
        guard !profileResolveAttempted, profile?.photoId == nil, let client else { return }
        profileResolveAttempted = true
        let target = SessionStore.email?.lowercased()
        guard let members = try? await client.teamMembers(teamID: teamID),
              let me = members.first(where: { $0.email?.lowercased() == target }) else { return }
        let resolved = Profile(id: me.profileId ?? profile?.id ?? me.id,
                               fullname: me.fullname,
                               email: me.email ?? SessionStore.email,
                               photoId: me.photoId)
        profile = resolved
        SessionStore.cacheProfile(resolved)
    }

    /// Re-resolves the profile's avatar from team membership after it changes (upload/reset).
    /// Unlike ``resolveProfileIfNeeded(teamID:)`` this always runs, since `get-profile` is
    /// Cloudflare-blocked and team members are the only source of the current `photoId`.
    func refreshProfile() async {
        guard let client else { return }
        let target = SessionStore.email?.lowercased()
        guard let teams = try? await client.teams(), let team = teams.first,
              let members = try? await client.teamMembers(teamID: team.id),
              let me = members.first(where: { $0.email?.lowercased() == target }) else { return }
        let resolved = Profile(id: me.profileId ?? profile?.id ?? me.id,
                               fullname: me.fullname ?? profile?.fullname,
                               email: me.email ?? SessionStore.email,
                               photoId: me.photoId,
                               theme: profile?.theme, lang: profile?.lang, props: profile?.props)
        profile = resolved
        SessionStore.cacheProfile(resolved)
    }

    /// Ends the session. `deletingLocalData` is for the user's own "Log Out" and for a
    /// deleted account: then nothing of the account stays on the device, as the privacy
    /// policy says (`docs/privacy.md`). A session the server ended (a 401 anywhere) keeps
    /// the caches, so signing in again doesn't render every board anew.
    func logout(deletingLocalData: Bool = false) {
        if let client {
            Task { await client.logout() }
        }
        if let server = SessionStore.serverURL,
           let cookies = HTTPCookieStorage.shared.cookies(for: server) {
            cookies.forEach(HTTPCookieStorage.shared.deleteCookie)
        }
        SessionStore.clear()
        if deletingLocalData {
            Self.deleteLocalData()
        }
        client = nil
        profile = nil
        phase = .login
    }

    /// Everything the app keeps about an account besides the session:
    /// - rendered boards;
    /// - file outlines;
    /// - images;
    /// - recent searches;
    /// - the web views' cookies and storage.
    ///
    /// The server address and the last email stay, to fill in the login form.
    private static func deleteLocalData() {
        RemoteImageLoader.shared.clearCache()
        URLCache.shared.removeAllCachedResponses()
        FileOutlineCache.shared.clear()
        SearchHistory.clearAll()
        Task { await BoardPreviewRenderer.shared.clearCache() }
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }
}
