import Foundation

/// Persists the Penpot session across launches.
///
/// The server URL and last-used email are stored in `UserDefaults`; the sensitive
/// `auth-token` session cookie value is stored in the Keychain.
enum SessionStore {
    private static let serverKey = "penpot.serverURL"
    private static let emailKey = "penpot.email"
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

    static func clear() {
        authToken = nil
    }

    /// Re-injects the persisted auth cookie into the shared cookie storage for `server`.
    static func restoreCookie(for server: URL) {
        guard let token = authToken, let host = server.host else { return }
        let cookie = HTTPCookie(properties: [
            .domain: host,
            .path: "/",
            .name: cookieName,
            .value: token,
            .secure: server.scheme == "https" ? "TRUE" : "FALSE",
        ])
        if let cookie {
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
