import XCTest
@testable import PenpotiOS

/// Regression tests for the auth cookie rebuilt from the Keychain token.
///
/// `HTTPCookie(properties:)` does not parse the `.secure` value — the mere presence of the
/// key marks the cookie secure. Setting it to "FALSE" for an http server therefore produced a
/// secure cookie that `URLSession`/`WKWebView` silently withheld over plain http, logging out
/// the canvas web view against a local dev server.
final class SessionCookieTests: XCTestCase {
    private let token = "test-token-value"

    override func setUp() {
        super.setUp()
        SessionStore.authToken = token
    }

    override func tearDown() {
        SessionStore.authToken = nil
        super.tearDown()
    }

    func testHTTPServerCookieIsNotMarkedSecure() throws {
        let server = URL(string: "http://localhost:3450")!
        let cookie = try XCTUnwrap(SessionStore.authCookie(for: server))
        XCTAssertFalse(cookie.isSecure, "An http server's cookie must not be secure, or it is never sent.")
        XCTAssertEqual(cookie.name, "auth-token")
        XCTAssertEqual(cookie.value, token)
        XCTAssertEqual(cookie.domain, "localhost")
    }

    func testHTTPSServerCookieIsMarkedSecure() throws {
        let server = URL(string: "https://design.penpot.app")!
        let cookie = try XCTUnwrap(SessionStore.authCookie(for: server))
        XCTAssertTrue(cookie.isSecure)
        XCTAssertEqual(cookie.domain, "design.penpot.app")
    }

    /// The end-to-end symptom: cookie storage must actually hand the cookie back for an
    /// http URL, which is what the canvas `WKWebView` relies on.
    func testCookieIsDeliveredToPlainHTTPURL() throws {
        let server = URL(string: "http://localhost:3450")!
        let storage = HTTPCookieStorage.shared
        storage.cookies(for: server)?.forEach(storage.deleteCookie)
        storage.setCookie(try XCTUnwrap(SessionStore.authCookie(for: server)))
        let names = storage.cookies(for: server)?.map(\.name) ?? []
        XCTAssertTrue(names.contains("auth-token"), "Cookie was withheld from an http URL.")
        storage.cookies(for: server)?.forEach(storage.deleteCookie)
    }
}
