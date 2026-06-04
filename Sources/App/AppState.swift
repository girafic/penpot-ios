import Foundation
import Observation

/// Global authentication + session state for the app.
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
        do {
            let profile = try await client.profile()
            self.client = client
            self.profile = profile
            phase = .authenticated
        } catch {
            SessionStore.clear()
            phase = .login
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

        SessionStore.serverURL = server
        SessionStore.email = email
        SessionStore.captureCookie(for: server)

        self.client = client
        self.profile = profile
        phase = .authenticated
    }

    func logout() {
        if let client {
            Task { await client.logout() }
        }
        if let server = SessionStore.serverURL,
           let cookies = HTTPCookieStorage.shared.cookies(for: server) {
            cookies.forEach(HTTPCookieStorage.shared.deleteCookie)
        }
        SessionStore.clear()
        client = nil
        profile = nil
        phase = .login
    }
}
