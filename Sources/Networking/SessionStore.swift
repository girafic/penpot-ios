import Foundation

/// An account the app is signed in to: a Penpot server and a profile on it. Several can be
/// signed in at once (a SaaS account and a self-hosted one, or two on one server); one is
/// active, and switching needs no new login.
struct StoredAccount: Codable, Identifiable, Equatable, Sendable {
    /// The app's own id for it, which also names its token in the Keychain.
    let id: String
    var server: URL
    var email: String?
    var profileID: String?
    var fullname: String?
    var photoID: String?

    var profile: Profile? {
        profileID.map { Profile(id: $0, fullname: fullname, email: email, photoId: photoID) }
    }

    /// The server as people write it: the host, and the port when there is one.
    var serverLabel: String {
        guard let host = server.host else { return server.absoluteString }
        return server.port.map { "\(host):\($0)" } ?? host
    }

    /// The same login: one server, one email (or one profile).
    func isSameLogin(server: URL, email: String?, profileID: String?) -> Bool {
        guard Self.sameServer(self.server, server) else { return false }
        if let profileID, let mine = self.profileID { return profileID == mine }
        return self.email?.lowercased() == email?.lowercased()
    }

    static func sameServer(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased() && lhs.host?.lowercased() == rhs.host?.lowercased()
            && lhs.port == rhs.port
    }
}

/// Persists the Penpot sessions across launches.
///
/// The accounts (server, email, cached profile) are stored in `UserDefaults`; each
/// account's sensitive `auth-token` session cookie value is stored in the Keychain. The
/// members without an account in their name act on the *active* account.
enum SessionStore {
    private static let accountsKey = "penpot.accounts"
    private static let activeKey = "penpot.activeAccount"
    // The last login, to fill in the login form.
    private static let serverKey = "penpot.serverURL"
    private static let emailKey = "penpot.email"
    // Before several accounts: one session, its profile in these keys.
    private static let profileIDKey = "penpot.profileID"
    private static let profileNameKey = "penpot.profileName"
    private static let profilePhotoKey = "penpot.profilePhotoID"
    /// The token of the single session before accounts, and of none once migrated.
    private static let legacyTokenAccount = "penpot.authToken"
    static let cookieName = "auth-token"

    // MARK: Accounts

    static var accounts: [StoredAccount] {
        get {
            migrateIfNeeded()
            guard let data = UserDefaults.standard.data(forKey: accountsKey) else { return [] }
            return (try? JSONDecoder().decode([StoredAccount].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: accountsKey)
        }
    }

    static var activeAccountID: String? {
        get {
            migrateIfNeeded()
            return UserDefaults.standard.string(forKey: activeKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: activeKey) }
    }

    static var activeAccount: StoredAccount? {
        guard let id = activeAccountID else { return nil }
        return accounts.first { $0.id == id }
    }

    static func token(for accountID: String) -> String? {
        Keychain.read(account: tokenAccount(accountID))
    }

    static func setToken(_ token: String?, for accountID: String) {
        if let token {
            Keychain.set(token, account: tokenAccount(accountID))
        } else {
            Keychain.delete(account: tokenAccount(accountID))
        }
    }

    /// Whether the account still has a session (the server may have ended it since).
    static func isSignedIn(_ account: StoredAccount) -> Bool { token(for: account.id) != nil }

    /// Adds the login, or updates the account it already is, with its session token, and
    /// makes it the active one.
    @discardableResult
    static func activate(server: URL, email: String?, profile: Profile?, token: String?) -> StoredAccount {
        var all = accounts
        var account: StoredAccount
        if let index = all.firstIndex(where: { $0.isSameLogin(server: server, email: email, profileID: profile?.id) }) {
            account = all[index]
            account.server = server
            account.email = email ?? account.email
            if let profile { account.apply(profile) }
            all[index] = account
        } else {
            account = StoredAccount(id: UUID().uuidString.lowercased(), server: server, email: email)
            if let profile { account.apply(profile) }
            all.append(account)
        }
        accounts = all
        if let token { setToken(token, for: account.id) }
        activeAccountID = account.id
        lastServerURL = server
        lastEmail = email
        return account
    }

    /// Forgets the account and its session.
    static func remove(_ accountID: String) {
        setToken(nil, for: accountID)
        accounts.removeAll { $0.id == accountID }
        if activeAccountID == accountID { activeAccountID = nil }
    }

    private static func tokenAccount(_ accountID: String) -> String { "penpot.authToken.\(accountID)" }

    /// One session, as the app kept it before it had accounts, becomes the first account.
    private nonisolated(unsafe) static var migrated = false
    private static func migrateIfNeeded() {
        guard !migrated else { return }
        migrated = true
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: accountsKey) == nil else { return }
        guard let server = lastServerURL, let token = Keychain.read(account: legacyTokenAccount) else {
            defaults.set(try? JSONEncoder().encode([StoredAccount]()), forKey: accountsKey)
            return
        }
        let account = StoredAccount(id: UUID().uuidString.lowercased(), server: server, email: lastEmail,
                                    profileID: defaults.string(forKey: profileIDKey),
                                    fullname: defaults.string(forKey: profileNameKey),
                                    photoID: defaults.string(forKey: profilePhotoKey))
        Keychain.set(token, account: tokenAccount(account.id))
        Keychain.delete(account: legacyTokenAccount)
        defaults.set(try? JSONEncoder().encode([account]), forKey: accountsKey)
        defaults.set(account.id, forKey: activeKey)
        for key in [profileIDKey, profileNameKey, profilePhotoKey] { defaults.removeObject(forKey: key) }
    }

    // MARK: The last login (fills in the login form)

    static var lastServerURL: URL? {
        get { UserDefaults.standard.string(forKey: serverKey).flatMap(URL.init(string:)) }
        set { UserDefaults.standard.set(newValue?.absoluteString, forKey: serverKey) }
    }

    static var lastEmail: String? {
        get { UserDefaults.standard.string(forKey: emailKey) }
        set { UserDefaults.standard.set(newValue, forKey: emailKey) }
    }

    // MARK: The active account

    /// The active account's server, else the last one signed in to.
    static var serverURL: URL? { activeAccount?.server ?? lastServerURL }

    static var defaultServerURL: URL { URL(string: "https://design.penpot.app")! }

    /// The active account's email, else the last one signed in with (a convenience
    /// prefill, not a secret).
    static var email: String? { activeAccount?.email ?? lastEmail }

    /// The active account's session token. Without an active account it is the slot a
    /// login in progress (or a test) uses.
    static var authToken: String? {
        get {
            if let id = activeAccountID { return token(for: id) }
            return Keychain.read(account: legacyTokenAccount)
        }
        set {
            if let id = activeAccountID {
                setToken(newValue, for: id)
            } else if let newValue {
                Keychain.set(newValue, account: legacyTokenAccount)
            } else {
                Keychain.delete(account: legacyTokenAccount)
            }
        }
    }

    // MARK: Cached profile (so the session is restorable without `get-profile`)

    /// The active account's profile, as last seen. `get-profile` sits behind a Cloudflare
    /// challenge that blocks non-browser clients, so we can't rely on it at launch.
    static var cachedProfile: Profile? { activeAccount?.profile }

    static func cacheProfile(_ profile: Profile) {
        guard let id = activeAccountID else { return }
        var all = accounts
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].apply(profile)
        accounts = all
    }

    /// Ends the active account's session; the account stays listed, signed out, so
    /// signing in again is one password away.
    static func clear() {
        authToken = nil
    }

    // MARK: Cookies

    /// Builds the persisted auth cookie for `server` (used both for the shared cookie
    /// storage and for injecting into a `WKWebView` that loads Penpot's web viewer).
    static func authCookie(for server: URL) -> HTTPCookie? {
        authCookie(for: server, token: authToken)
    }

    static func authCookie(for server: URL, token: String?) -> HTTPCookie? {
        guard let token, let host = server.host else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: host,
            .path: "/",
            .name: cookieName,
            .value: token,
        ]
        // `HTTPCookie` treats the mere *presence* of `.secure` as "secure" — the value is not
        // parsed, so passing "FALSE" still yields `isSecure == true`. A secure cookie is then
        // silently withheld from plain-http requests, which logs out both the RPC client and
        // the canvas `WKWebView` against an http dev server. Only set the key for https.
        if server.scheme == "https" { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }

    /// Re-injects the persisted auth cookie into the shared cookie storage for `server`.
    static func restoreCookie(for server: URL) {
        if let cookie = authCookie(for: server) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    /// The session cookie `server` set, from the shared cookie storage.
    static func sessionCookieValue(for server: URL) -> String? {
        HTTPCookieStorage.shared.cookies(for: server)?.first { $0.name == cookieName }?.value
    }

    /// Captures the current auth cookie from cookie storage and persists it for the
    /// active account (Penpot may renew it).
    static func captureCookie(for server: URL) {
        if let value = sessionCookieValue(for: server) {
            authToken = value
        }
    }

    /// Removes every cookie of `server`'s host from the shared storage.
    static func deleteCookies(for server: URL) {
        let storage = HTTPCookieStorage.shared
        storage.cookies(for: server)?.forEach(storage.deleteCookie)
    }
}

extension StoredAccount {
    mutating func apply(_ profile: Profile) {
        profileID = profile.id
        fullname = profile.fullname ?? fullname
        photoID = profile.photoId
        if let email = profile.email { self.email = email }
    }
}
