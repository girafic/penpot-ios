import Foundation

/// Registration and password-recovery commands — all unauthenticated POSTs, called on a
/// throwaway client built from the login screen's server URL (like `create-demo-profile`).
///
/// Registration is two-step: `prepare-register-profile` validates and returns a token
/// (every gate error fires here), `register-profile` redeems it. On servers with email
/// verification (SaaS) the redeem answers `{id, email}` WITHOUT a session cookie and
/// mails a link; on SMTP-less servers it answers the full profile AND sets the cookie.
/// Redeeming the same token again re-sends the verification mail (server-throttled).
extension PenpotClient {

    private struct PreparedRegistration: Decodable { let token: String }

    /// Step 1. Gate errors (`email-already-exists`, `registration-disabled`,
    /// `email-domain-is-not-allowed`, `email-as-password`, bounce/complaint blocks)
    /// surface HERE via ``PenpotError/serverErrorCode``.
    func prepareRegister(fullname: String, email: String, password: String) async throws -> String {
        try await mutation("prepare-register-profile", params: [
            "fullname": fullname,
            "email": email,
            "password": password,
        ], as: PreparedRegistration.self).token
    }

    /// Step 2 response, decoded leniently across server variants. A non-nil `fullname`
    /// means the full profile came back — and with it the session cookie.
    struct RegisterResult: Decodable {
        let id: String?
        let email: String?
        let fullname: String?
        let photoId: String?
        let invitationToken: String?

        var profile: Profile? {
            guard let id, fullname != nil else { return nil }
            return Profile(id: id, fullname: fullname, email: email, photoId: photoId)
        }
    }

    @discardableResult
    func registerProfile(token: String, acceptNewsletter: Bool = false) async throws -> RegisterResult {
        var params: [String: Any] = ["token": token]
        if acceptNewsletter { params["accept-newsletter-updates"] = true }
        return try await mutation("register-profile", params: params, as: RegisterResult.self)
    }

    /// Activates a profile from the emailed verification link AND sets the session
    /// cookie on this response. Body shape varies by token issuer — treated as opaque;
    /// callers validate the session with `get-teams` afterwards.
    func verifyToken(_ token: String) async throws {
        _ = try await mutation("verify-token", params: ["token": token], as: EmptyResponse.self)
    }

    /// Sends the recovery email. 2.17 servers ALWAYS answer 200 (anti-enumeration);
    /// older self-hosted backends may raise profile-specific codes.
    func requestProfileRecovery(email: String) async throws {
        _ = try await mutation("request-profile-recovery", params: ["email": email], as: EmptyResponse.self)
    }

    /// Sets a new password using the emailed token (15-minute expiry; also activates an
    /// unverified account). Sets NO session cookie — log in afterwards.
    func recoverProfile(token: String, password: String) async throws {
        _ = try await mutation("recover-profile",
                               params: ["token": token, "password": password],
                               as: EmptyResponse.self)
    }

    // MARK: Token paste helper

    /// Extracts a Penpot auth token from pasted text: the full emailed URL
    /// (`{server}/#/auth/verify-token?token=…`), a URL with a plain query, or the bare
    /// JWE (base64url segments joined by dots). nil when nothing token-shaped is found.
    static func authToken(fromPastedText text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // The token rides as a query param inside the URL FRAGMENT ("…/#/auth/…?token=X").
        if let hash = trimmed.range(of: "#") {
            if let token = queryValue("token", in: String(trimmed[hash.upperBound...])) {
                return token
            }
        }
        if let token = queryValue("token", in: trimmed) {
            return token
        }
        // Bare-token case: JWE compact form.
        let jwePattern = #"^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]*){2,4}$"#
        return trimmed.range(of: jwePattern, options: .regularExpression) != nil ? trimmed : nil
    }

    private static func queryValue(_ name: String, in string: String) -> String? {
        guard let questionMark = string.range(of: "?") else { return nil }
        var components = URLComponents()
        components.query = String(string[questionMark.upperBound...])
        let value = components.queryItems?.first(where: { $0.name == name })?.value
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Server capability probe

    /// Registration capabilities parsed from `{server}/js/config.js` — Penpot has no RPC
    /// for server flags. Compile-time defaults include registration; `enable-*` /
    /// `disable-*` tokens in `penpotFlags` patch them.
    struct ServerAuthConfig: Equatable {
        var registrationEnabled = true
        /// Whether `create-demo-profile` is offered. Opt-in: unlike registration, the
        /// command hard-fails where the flag is off, so a server has to advertise
        /// `enable-demo-users` before we show the shortcut. design.penpot.app ships an
        /// explicit `disable-demo-users`.
        var demoUsersEnabled = false
        var requiresTermsCheckbox = false
        var offersNewsletter = false
        /// `export-link-later`: offer "Link matching libraries on import" when downloading.
        var exportLinkLaterEnabled = false
        var termsURL: URL?
        var privacyURL: URL?

        static let fallback = ServerAuthConfig()
    }

    /// Best-effort: any fetch/parse failure returns `.fallback` (registration shown —
    /// the backend still answers `registration-disabled` at prepare time regardless).
    func fetchAuthConfig() async -> ServerAuthConfig {
        guard let url = URL(string: "\(baseURL.absoluteString)/js/config.js") else { return .fallback }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        guard let (data, response) = try? await transportData(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let source = String(data: data, encoding: .utf8) else { return .fallback }
        return Self.authConfig(fromConfigJS: source)
    }

    static func authConfig(fromConfigJS source: String) -> ServerAuthConfig {
        var config = ServerAuthConfig()
        if let flagsRange = source.range(of: #"penpotFlags\s*=\s*"([^"]*)""#, options: .regularExpression) {
            let flagsString = String(source[flagsRange])
            let tokens = flagsString
                .replacingOccurrences(of: #"penpotFlags\s*=\s*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\"", with: "")
                .split(separator: " ").map(String.init)
            var flags: Set<String> = ["registration", "login-with-password"]
            for token in tokens {
                if token.hasPrefix("enable-") {
                    flags.insert(String(token.dropFirst("enable-".count)))
                } else if token.hasPrefix("disable-") {
                    flags.remove(String(token.dropFirst("disable-".count)))
                }
            }
            config.registrationEnabled = flags.contains("registration") && flags.contains("login-with-password")
            config.demoUsersEnabled = flags.contains("demo-users")
            config.requiresTermsCheckbox = flags.contains("terms-and-privacy-checkbox")
            config.offersNewsletter = flags.contains("newsletter-subscription")
            config.exportLinkLaterEnabled = flags.contains("export-link-later")
        }
        func urlValue(_ name: String) -> URL? {
            guard let range = source.range(of: name + #"\s*=\s*"([^"]+)""#, options: .regularExpression) else {
                return nil
            }
            let match = String(source[range])
            guard let quoteStart = match.range(of: "\"") else { return nil }
            let value = match[quoteStart.upperBound...].dropLast()
            return URL(string: String(value))
        }
        config.termsURL = urlValue("penpotTermsOfServiceURI")
        config.privacyURL = urlValue("penpotPrivacyPolicyURI")
        return config
    }
}
