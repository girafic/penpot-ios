import Foundation
import Observation
import WebKit

/// Global authentication + session state for the app.
///
/// Main-actor isolated: without it `bootstrap()` ran on a background executor, and a
/// `phase` change made there could be missed by SwiftUI, leaving the app on the splash
/// screen (seen on a loaded machine: session validated, no screen change).
///
/// Several accounts can be signed in (``SessionStore``); one is active at a time, and its
/// session cookie is the one in the shared cookie storage. Switching swaps the cookie and
/// rebuilds the screens (``RootView`` keys them on ``accountID``).
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
    /// The active account, also when it is signed out (the login form is filled in for it).
    private(set) var accountID: String?
    /// Every account the app knows, signed in or not, in the order they were added.
    private(set) var accounts: [StoredAccount] = []

    /// Attempts to restore the active account's session on launch, or after a switch.
    func bootstrap() async {
        accounts = SessionStore.accounts
        accountID = SessionStore.activeAccountID
        guard let account = SessionStore.activeAccount, SessionStore.authToken != nil else {
            phase = .login
            return
        }
        SessionStore.restoreCookie(for: account.server)
        let client = PenpotClient(baseURL: account.server)
        self.client = client
        // Make the cached profile available immediately (used e.g. for comment ownership).
        self.profile = account.profile
        do {
            // Validate the saved token with a reliable endpoint. We deliberately do NOT use
            // `get-profile` here: it sits behind a Cloudflare challenge that 403s non-browser
            // clients even with a valid token, which would wrongly wipe a good session.
            _ = try await client.teams()
            guard accountID == account.id else { return }
            // Best-effort profile refresh; tolerate the Cloudflare block.
            if let fresh = try? await client.profile() {
                self.profile = fresh
                SessionStore.cacheProfile(fresh)
                accounts = SessionStore.accounts
            }
            phase = .authenticated
        } catch PenpotError.unauthorized {
            guard accountID == account.id else { return }
            // Only a genuine 401 means the token is no longer valid.
            SessionStore.clear()
            self.client = nil
            self.profile = nil
            phase = .login
        } catch {
            guard accountID == account.id else { return }
            // Transient/forbidden error — keep the session rather than forcing re-login.
            phase = .authenticated
        }
    }

    /// Logs in with email + password against `server`.
    func login(server: URL, email: String, password: String) async throws {
        // Start from a clean cookie slate for this host.
        SessionStore.deleteCookies(for: server)
        let client = PenpotClient(baseURL: server)
        do {
            let profile = try await client.login(email: email, password: password)
            adoptSession(server: server, email: email, profile: profile, client: client)
        } catch {
            restoreActiveCookie()
            throw error
        }
    }

    /// Adopts an already-established session cookie (login, registration, email
    /// verification) as the app's authenticated state: the account it belongs to, new or
    /// known, becomes the active one.
    func adoptSession(server: URL, email: String?, profile: Profile?, client: PenpotClient) {
        let previous = accountID
        let account = SessionStore.activate(server: server, email: email, profile: profile,
                                            token: SessionStore.sessionCookieValue(for: server))
        if account.id != previous {
            profileResolveAttempted = false
            if let previous, let old = accounts.first(where: { $0.id == previous }),
               !StoredAccount.sameServer(old.server, server) {
                SessionStore.deleteCookies(for: old.server)
            }
        }
        self.client = client
        self.profile = profile ?? account.profile
        accounts = SessionStore.accounts
        accountID = account.id
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

    /// Puts the active account's cookie back after a login for another account that
    /// didn't happen (failed, or the form was closed): on the same server it replaced it.
    func restoreActiveCookie() {
        guard let account = SessionStore.activeAccount, SessionStore.authToken != nil else { return }
        SessionStore.restoreCookie(for: account.server)
    }

    // MARK: Accounts

    /// Makes another account the active one, without a new login when it is still signed
    /// in; one the server signed out opens the login form, filled in for it.
    func switchAccount(to id: String) async {
        guard id != accountID, let target = SessionStore.accounts.first(where: { $0.id == id }) else { return }
        leaveActiveSession()
        SessionStore.activeAccountID = target.id
        SessionStore.lastServerURL = target.server
        SessionStore.lastEmail = target.email
        accountID = target.id
        phase = .loading
        await bootstrap()
    }

    /// Signs an account out and forgets it. The active one gives way to the next account
    /// still signed in, or to the login form.
    func removeAccount(_ id: String) {
        if id == accountID {
            logout(deletingLocalData: true)
            return
        }
        guard let account = SessionStore.accounts.first(where: { $0.id == id }) else { return }
        if let token = SessionStore.token(for: id) {
            let client = PenpotClient(baseURL: account.server)
            Task { await client.logout(token: token) }
        }
        SessionStore.remove(id)
        Self.deleteLocalData()
        accounts = SessionStore.accounts
    }

    /// Keeps the active session's cookie (Penpot may have renewed it) and takes it out of
    /// the shared storage, so the next account's requests don't carry it.
    private func leaveActiveSession() {
        if let account = SessionStore.activeAccount {
            if SessionStore.authToken != nil { SessionStore.captureCookie(for: account.server) }
            SessionStore.deleteCookies(for: account.server)
        }
        client = nil
        profile = nil
        profileResolveAttempted = false
    }

    // MARK: Profile

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
        accounts = SessionStore.accounts
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
        accounts = SessionStore.accounts
    }

    /// The profile changed in Settings (name, avatar): the account list shows it too.
    func cacheProfile(_ profile: Profile) {
        self.profile = profile
        SessionStore.cacheProfile(profile)
        accounts = SessionStore.accounts
    }

    // MARK: Logout

    /// Ends the active account's session.
    ///
    /// `deletingLocalData` is for the user's own "Log Out" and for a deleted account: then
    /// the account is forgotten and nothing of it stays on the device, as the privacy
    /// policy says (`docs/privacy.md`); another account still signed in takes over. A
    /// session the server ended (a 401 anywhere) keeps the account, signed out, and the
    /// caches, so signing in again doesn't render every board anew.
    func logout(deletingLocalData: Bool = false) {
        let leaving = SessionStore.activeAccount
        if let leaving, let token = SessionStore.authToken {
            let client = PenpotClient(baseURL: leaving.server)
            Task { await client.logout(token: token) }
        }
        if let leaving { SessionStore.deleteCookies(for: leaving.server) }
        if deletingLocalData {
            if let leaving { SessionStore.remove(leaving.id) }
            Self.deleteLocalData()
        } else {
            SessionStore.clear()
        }
        client = nil
        profile = nil
        profileResolveAttempted = false
        accounts = SessionStore.accounts
        if deletingLocalData, let next = accounts.first(where: SessionStore.isSignedIn) {
            SessionStore.activeAccountID = next.id
            accountID = next.id
            phase = .loading
            Task { await bootstrap() }
        } else {
            accountID = SessionStore.activeAccountID
            phase = .login
        }
    }

    /// Everything the app keeps about an account besides the session:
    /// - rendered boards;
    /// - file outlines;
    /// - images;
    /// - recent searches;
    /// - the web views' cookies and storage.
    ///
    /// The caches are shared by every account, so they all go. The server address and the
    /// last email stay, to fill in the login form.
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
