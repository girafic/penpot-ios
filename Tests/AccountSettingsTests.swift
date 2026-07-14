import XCTest
@testable import PenpotiOS

/// Decoding + helpers for the account-settings feature. Pure, no network.
final class AccountSettingsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.penpot.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Profile back-compat

    // The three new fields are optional; a legacy payload without them must still decode.
    func testProfileDecodesWithoutNewFields() throws {
        let profile = try decode(Profile.self,
            #"{"id":"p1","fullname":"Test User","email":"user@example.com","photoId":"ph1"}"#)
        XCTAssertEqual(profile.id, "p1")
        XCTAssertEqual(profile.fullname, "Test User")
        XCTAssertNil(profile.theme)
        XCTAssertNil(profile.lang)
        XCTAssertNil(profile.props)
    }

    func testProfileDecodesWithPropsAndTheme() throws {
        let json = """
        {
          "id": "p1", "fullname": "Test User", "email": "user@example.com", "theme": "dark",
          "props": {
            "notifications": {"dashboardComments": "partial", "emailComments": "none", "emailInvites": "all"},
            "newsletterUpdates": true, "newsletterNews": false
          }
        }
        """
        let profile = try decode(Profile.self, json)
        XCTAssertEqual(profile.theme, "dark")
        XCTAssertEqual(profile.props?.notifications?.dashboardComments, .partial)
        // `.none` on an optional is ambiguous with Optional.none, so name the case explicitly.
        XCTAssertEqual(profile.props?.notifications?.emailComments, CommentNotification.none)
        XCTAssertEqual(profile.props?.notifications?.emailInvites, .all)
        XCTAssertEqual(profile.props?.newsletterUpdates, true)
        XCTAssertEqual(profile.props?.newsletterNews, false)
    }

    // Guards the memberwise-init call sites (ProfilesResponse etc.) that extending Profile could break.
    func testProfilesResponseStillDecodesBothShapes() throws {
        let map = try decode(ProfilesResponse.self,
            #"{"u1":{"fullname":"A","email":"a@x.de"},"u2":{"id":"u2b","fullname":"B"}}"#)
        XCTAssertEqual(map.byID["u1"]?.fullname, "A")   // id defaults to the map key
        XCTAssertEqual(map.byID["u2b"]?.fullname, "B")  // explicit id wins

        let array = try decode(ProfilesResponse.self,
            #"[{"id":"u1","fullname":"A"},{"id":"u2","fullname":"B"}]"#)
        XCTAssertEqual(array.byID.count, 2)
        XCTAssertEqual(array.byID["u1"]?.fullname, "A")
    }

    // MARK: Notifications

    func testNotificationSettingsDecodesCamelCase() throws {
        let s = try decode(NotificationSettings.self,
            #"{"dashboardComments":"all","emailComments":"partial","emailInvites":"none"}"#)
        XCTAssertEqual(s.dashboardComments, .all)
        XCTAssertEqual(s.emailComments, .partial)
        XCTAssertEqual(s.emailInvites, .none)
    }

    // Missing keys must fall back to Penpot's default rather than throwing.
    func testNotificationSettingsDefaultsMissingKeysToAll() throws {
        let s = try decode(NotificationSettings.self, #"{"emailComments":"none"}"#)
        XCTAssertEqual(s.dashboardComments, .all)
        XCTAssertEqual(s.emailComments, .none)
        XCTAssertEqual(s.emailInvites, .all)
    }

    // MARK: Access tokens

    func testAccessTokenListItemHasNoSecret() throws {
        let token = try decode(AccessToken.self,
            #"{"id":"t1","name":"CI","createdAt":"2026-01-01T00:00:00Z","expiresAt":null}"#)
        XCTAssertEqual(token.name, "CI")
        XCTAssertNil(token.token)
        XCTAssertNil(token.expiresAt)
    }

    func testAccessTokenCreateResponseHasSecret() throws {
        let token = try decode(AccessToken.self,
            #"{"id":"t1","name":"CI","token":"penpat-secret-xyz"}"#)
        XCTAssertEqual(token.token, "penpat-secret-xyz")
    }

    // MARK: request-email-change dual response

    // Empty 200 bodies are substituted with "null" by PenpotClient.send; the optional decodes to nil.
    func testEmailChangeResultDecodesNullAndChanged() throws {
        let sentEmail = try decode(EmailChangeResult?.self, "null")
        XCTAssertNil(sentEmail?.changed)

        let changed = try decode(EmailChangeResult?.self, #"{"changed":true}"#)
        XCTAssertEqual(changed?.changed, true)
    }

    // MARK: Languages

    func testLanguageTableIsWellFormed() {
        XCTAssertEqual(PenpotLanguage.all.count, 34)
        XCTAssertEqual(Set(PenpotLanguage.all.map(\.penpotCode)).count, 34, "codes must be unique")
        XCTAssertEqual(PenpotLanguage.appLocalizedLanguages.count, 6)
        // Chinese script codes are special-cased (not a simple underscore→hyphen).
        XCTAssertEqual(PenpotLanguage.all.first { $0.penpotCode == "zh_cn" }?.iosCode, "zh-Hans")
        XCTAssertEqual(PenpotLanguage.all.first { $0.penpotCode == "pt_br" }?.iosCode, "pt-BR")
    }

    // MARK: Multipart framing (update-profile-photo)

    func testMultipartBodyFraming() throws {
        let payload = Data([0xFF, 0xD8, 0xFF])  // JPEG magic bytes
        let body = PenpotClient.multipartBody(boundary: "BND", field: "file",
                                              filename: "avatar.jpg", mimeType: "image/jpeg", data: payload)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("--BND\r\n"))
        XCTAssertTrue(text.contains(#"Content-Disposition: form-data; name="file"; filename="avatar.jpg""#))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg\r\n\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n--BND--\r\n"))
    }
}
