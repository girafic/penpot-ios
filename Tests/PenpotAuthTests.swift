import XCTest
@testable import PenpotiOS

/// Registration/recovery plumbing: lenient response decoding, the pasted-link token
/// extractor, the config.js capability probe, and the refined error helpers.
final class PenpotAuthTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.penpot.decode(T.self, from: Data(json.utf8))
    }

    // MARK: register-profile response variants

    // SMTP-less servers answer the full profile (⇒ session cookie was set).
    func testRegisterResultFullProfile() throws {
        let json = #"{"id": "p1", "email": "a@b.co", "fullname": "Ann", "photoId": null}"#
        let result = try decode(PenpotClient.RegisterResult.self, json)
        XCTAssertEqual(result.profile?.id, "p1")
        XCTAssertEqual(result.profile?.fullname, "Ann")
    }

    // Verification-email servers answer only {id, email} — no profile, no cookie.
    func testRegisterResultVerificationPending() throws {
        let result = try decode(PenpotClient.RegisterResult.self, #"{"id": "p1", "email": "a@b.co"}"#)
        XCTAssertNil(result.profile)
        XCTAssertEqual(result.email, "a@b.co")
    }

    func testRegisterResultCarriesInvitationToken() throws {
        let json = #"{"id": "p1", "email": "a@b.co", "fullname": "Ann", "invitationToken": "tok"}"#
        XCTAssertEqual(try decode(PenpotClient.RegisterResult.self, json).invitationToken, "tok")
    }

    // MARK: Pasted-link token extraction

    func testAuthTokenFromEmailedLinks() {
        // The token rides in the URL FRAGMENT's query, the shape the emails use.
        XCTAssertEqual(
            PenpotClient.authToken(fromPastedText:
                "https://design.penpot.app/#/auth/verify-token?token=abc.def.ghi"),
            "abc.def.ghi")
        XCTAssertEqual(
            PenpotClient.authToken(fromPastedText:
                "https://design.penpot.app/#/auth/recovery?token=aaa.bbb.ccc.ddd.eee&foo=1"),
            "aaa.bbb.ccc.ddd.eee")
        // Plain-query URL.
        XCTAssertEqual(
            PenpotClient.authToken(fromPastedText: "https://x.example/verify?token=t.o.k"),
            "t.o.k")
        // Bare JWE compact forms (3 and 5 segments).
        XCTAssertEqual(PenpotClient.authToken(fromPastedText: "abc.def.ghi"), "abc.def.ghi")
        XCTAssertEqual(PenpotClient.authToken(fromPastedText: " a1-B2.c_3.d4.e5.f6 "), "a1-B2.c_3.d4.e5.f6")
        // Garbage.
        XCTAssertNil(PenpotClient.authToken(fromPastedText: "please verify my account"))
        XCTAssertNil(PenpotClient.authToken(fromPastedText: ""))
        XCTAssertNil(PenpotClient.authToken(fromPastedText: "https://x.example/no-token-here"))
    }

    // MARK: config.js capability probe

    func testAuthConfigParsesFlagsAndURLs() {
        let source = """
        var penpotFlags = "enable-terms-and-privacy-checkbox enable-newsletter-subscription";
        var penpotTermsOfServiceURI = "https://penpot.app/terms";
        var penpotPrivacyPolicyURI = "https://penpot.app/privacy";
        """
        let config = PenpotClient.authConfig(fromConfigJS: source)
        XCTAssertTrue(config.registrationEnabled)
        XCTAssertTrue(config.requiresTermsCheckbox)
        XCTAssertTrue(config.offersNewsletter)
        XCTAssertEqual(config.termsURL?.absoluteString, "https://penpot.app/terms")
        XCTAssertEqual(config.privacyURL?.absoluteString, "https://penpot.app/privacy")
    }

    func testAuthConfigDisableRegistration() {
        XCTAssertFalse(PenpotClient.authConfig(
            fromConfigJS: #"var penpotFlags = "disable-registration";"#).registrationEnabled)
        XCTAssertFalse(PenpotClient.authConfig(
            fromConfigJS: #"var penpotFlags = "disable-login-with-password";"#).registrationEnabled)
    }

    /// The demo shortcut is opt-in, and the SaaS opts out — this is the verbatim
    /// `penpotFlags` string design.penpot.app served on 2026-08-12, so a regression that
    /// re-shows the button there fails here rather than at a 400 from the server.
    func testAuthConfigHidesDemoUsersOnPenpotCloud() {
        let cloudFlags = """
        var penpotFlags = "enable-email-blacklist enable-audit-log enable-audit-log-archive \
        enable-audit-log-gc enable-user-feedback enable-smtp disable-log-emails \
        disable-backend-asserts disable-demo-users disable-telemetry enable-auto-file-snapshot \
        enable-terms-and-privacy-checkbox enable-login-with-google enable-login-with-github \
        enable-login-with-gitlab enable-login-with-custom-sso enable-newsletter-subscription \
        enable-quotes enable-soft-quotes enable-webhooks enable-urepl-server enable-prepl-server \
        enable-access-tokens enable-rpc-climit enable-file-validation \
        enable-soft-file-schema-validation enable-subscriptions enable-redis-cache \
        enable-sec-fetch-metadata-middleware enable-render-wasm-info enable-mcp";
        """
        let cloud = PenpotClient.authConfig(fromConfigJS: cloudFlags)
        XCTAssertFalse(cloud.demoUsersEnabled)
        // The same string must still leave the rest of the screen intact.
        XCTAssertTrue(cloud.registrationEnabled)
        XCTAssertTrue(cloud.requiresTermsCheckbox)

        XCTAssertTrue(PenpotClient.authConfig(
            fromConfigJS: #"var penpotFlags = "enable-demo-users";"#).demoUsersEnabled)
        // Silence is not consent: a server that never mentions the flag stays hidden.
        XCTAssertFalse(PenpotClient.authConfig(
            fromConfigJS: #"var penpotFlags = "enable-registration";"#).demoUsersEnabled)
    }

    // Unparseable sources fall back to showing registration — the backend still answers
    // registration-disabled at prepare time.
    func testAuthConfigFallsBackOnGarbage() {
        XCTAssertEqual(PenpotClient.authConfig(fromConfigJS: "<html>nope</html>"),
                       PenpotClient.ServerAuthConfig.fallback)
    }

    // MARK: Refined error helpers

    func testServerErrorReason() {
        let error = PenpotError.server(
            status: 400,
            body: #"{"type": "validation", "code": "invalid-token", "reason": "token-expired"}"#)
        XCTAssertEqual(error.serverErrorCode, "invalid-token")
        XCTAssertEqual(error.serverErrorReason, "token-expired")
        XCTAssertNil(PenpotError.unauthorized.serverErrorReason)
    }

    // The transport now distinguishes a :restriction 403 (JSON body with a code) from a
    // Cloudflare HTML 403 via this helper.
    func testErrorCodeInBody() {
        XCTAssertEqual(PenpotError.errorCode(inBody: #"{"type": "restriction", "code": "registration-disabled"}"#),
                       "registration-disabled")
        XCTAssertNil(PenpotError.errorCode(inBody: "<html>challenge</html>"))
        XCTAssertNil(PenpotError.errorCode(inBody: nil))
        XCTAssertNil(PenpotError.errorCode(inBody: #"{"type": "not-found"}"#))
    }
}
