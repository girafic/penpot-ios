import Foundation

/// Persists the Penpot session across launches.
///
/// The server URL and last-used email are stored in `UserDefaults`; the sensitive
/// `auth-token` session cookie value is stored in the Keychain.
enum SessionStore {
    private static let serverKey = "penpot.serverURL"
    private static let emailKey = "penpot.email"
    private static let profileIDKey = "penpot.profileID"
    private static let profileNameKey = "penpot.profileName"
    private static let profilePhotoKey = "penpot.profilePhotoID"
    private static let cookieAccount = "penpot.authToken"
    static let cookieName = "auth-token"

    // MARK: Server URL

    static var serverURL: URL? {
        get {
            guard let string = UserDefaults.standard.string(forKey: serverKey) else { return nil }
            return URL(string: string)
        }
        set {
            UserDefaults.standard.set(newValue?.absoluteString, forKey: serverKey)
        }
    }

    static var defaultServerURL: URL { URL(string: "https://design.penpot.app")! }

    // MARK: Email (convenience prefill, not a secret)

    static var email: String? {
        get { UserDefaults.standard.string(forKey: emailKey) }
        set { UserDefaults.standard.set(newValue, forKey: emailKey) }
    }

    // MARK: Auth token cookie (Keychain)

    static var authToken: String? {
        get { Keychain.read(account: cookieAccount) }
        set {
            if let newValue {
                Keychain.set(newValue, account: cookieAccount)
            } else {
                Keychain.delete(account: cookieAccount)
            }
        }
    }

    // MARK: Cached profile (so the session is restorable without `get-profile`)

    /// The profile captured at login, rebuilt from cached fields. `get-profile` sits behind
    /// a Cloudflare challenge that blocks non-browser clients, so we can't rely on it at launch.
    static var cachedProfile: Profile? {
        guard let id = UserDefaults.standard.string(forKey: profileIDKey) else { return nil }
        return Profile(id: id,
                       fullname: UserDefaults.standard.string(forKey: profileNameKey),
                       email: email,
                       photoId: UserDefaults.standard.string(forKey: profilePhotoKey))
    }

    static func cacheProfile(_ profile: Profile) {
        UserDefaults.standard.set(profile.id, forKey: profileIDKey)
        UserDefaults.standard.set(profile.fullname, forKey: profileNameKey)
        UserDefaults.standard.set(profile.photoId, forKey: profilePhotoKey)
    }

    static func clear() {
        authToken = nil
        UserDefaults.standard.removeObject(forKey: profileIDKey)
        UserDefaults.standard.removeObject(forKey: profileNameKey)
        UserDefaults.standard.removeObject(forKey: profilePhotoKey)
    }

    /// Builds the persisted auth cookie for `server` (used both for the shared cookie
    /// storage and for injecting into a `WKWebView` that loads Penpot's web viewer).
    static func authCookie(for server: URL) -> HTTPCookie? {
        guard let token = authToken, let host = server.host else { return nil }
        return HTTPCookie(properties: [
            .domain: host,
            .path: "/",
            .name: cookieName,
            .value: token,
            .secure: server.scheme == "https" ? "TRUE" : "FALSE",
        ])
    }

    /// Re-injects the persisted auth cookie into the shared cookie storage for `server`.
    static func restoreCookie(for server: URL) {
        if let cookie = authCookie(for: server) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    /// Captures the current auth cookie from cookie storage and persists it.
    static func captureCookie(for server: URL) {
        let cookies = HTTPCookieStorage.shared.cookies(for: server) ?? []
        if let cookie = cookies.first(where: { $0.name == cookieName }) {
            authToken = cookie.value
        }
    }
}
