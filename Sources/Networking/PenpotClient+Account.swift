import Foundation

/// Account / profile settings commands.
///
/// Casing follows Penpot's convention (see ``JSONCoding``): request params are kebab-case,
/// responses camelCase. Note two hard API constraints this app works around:
///
/// * `get-profile` is blocked by a Cloudflare challenge for non-browser clients (both GET
///   and POST), so we never read the profile directly. Notification prefs are instead read
///   via a no-op `update-profile-props` (a POST, which is not blocked).
/// * `update-profile` rewrites `fullname`+`lang`+`theme` as a set and the API never returns
///   `lang`/`theme`, so any omitted field is nulled. Callers must send every field they want
///   to preserve. Because we can't read the current `lang`, name/language edits are treated
///   as a deliberate "set all" action.
extension PenpotClient {

    // MARK: Profile

    /// Updates the profile. `fullname` is always required by Penpot. Omitting `lang` or
    /// `theme` **nulls** them server-side, so pass current values for anything you're not
    /// intentionally changing.
    @discardableResult
    func updateProfile(fullname: String, lang: String? = nil, theme: String? = nil) async throws -> Profile {
        var params: [String: Any] = ["fullname": fullname]
        if let lang { params["lang"] = lang }
        if let theme { params["theme"] = theme }
        return try await mutation("update-profile", params: params, as: Profile.self)
    }

    /// Uploads a new avatar (multipart). `mimeType` must be image/jpeg, image/png or image/webp.
    func updateProfilePhoto(_ data: Data, mimeType: String, filename: String) async throws {
        _ = try await upload("update-profile-photo", fileData: data,
                             filename: filename, mimeType: mimeType, as: EmptyResponse.self)
    }

    /// Resets the avatar to Penpot's default.
    func deleteProfilePhoto() async throws {
        _ = try await mutation("delete-profile-photo", as: EmptyResponse.self)
    }

    /// Requests an email change. On an SMTP-enabled server (e.g. design.penpot.app) this
    /// sends a confirmation link and returns an empty body → `false`. On an SMTP-disabled
    /// server it changes immediately and returns `{changed: true}` → `true`.
    @discardableResult
    func requestEmailChange(to email: String) async throws -> Bool {
        let result = try await mutation("request-email-change",
                                        params: ["email": email],
                                        as: EmailChangeResult?.self)
        return result?.changed == true
    }

    /// Permanently deletes the account. Invalidates the session on success. Fails with a
    /// server error if the user still owns teams that have other members.
    func deleteProfile() async throws {
        _ = try await mutation("delete-profile", as: EmptyResponse.self)
    }

    // MARK: Password

    /// Changes the password. `old` is required for accounts that already have one.
    func updatePassword(new: String, old: String?) async throws {
        var params: [String: Any] = ["password": new]
        if let old { params["old-password"] = old }
        _ = try await mutation("update-profile-password", params: params, as: EmptyResponse.self)
    }

    // MARK: Notifications

    /// Writes all three notification prefs (Penpot requires the full set). Params are
    /// kebab-case even though they read back camelCase.
    func updateNotifications(_ settings: NotificationSettings) async throws {
        _ = try await mutation("update-profile-notifications", params: [
            "dashboard-comments": settings.dashboardComments.rawValue,
            "email-comments": settings.emailComments.rawValue,
            "email-invites": settings.emailInvites.rawValue,
        ], as: EmptyResponse.self)
    }

    /// Reads the current notification prefs via a no-op `update-profile-props` merge, which
    /// returns the props map and — unlike `get-profile` — is not Cloudflare-blocked.
    /// Falls back to Penpot's defaults if none are set.
    func fetchNotifications() async throws -> NotificationSettings {
        let props = try await mutation("update-profile-props",
                                       params: ["props": [String: Any]()],
                                       as: ProfileProps.self)
        return props.notifications ?? NotificationSettings()
    }

    /// Merges keys into the props bag (a nil value deletes a key). Returns the resulting props.
    @discardableResult
    func updateProfileProps(_ props: [String: Any]) async throws -> ProfileProps {
        try await mutation("update-profile-props", params: ["props": props], as: ProfileProps.self)
    }

    // MARK: Access tokens

    /// Lists personal access tokens. `get-access-tokens` reaches the API over plain GET
    /// (it is not among the Cloudflare-challenged endpoints).
    func accessTokens() async throws -> [AccessToken] {
        try await query("get-access-tokens", as: [AccessToken].self)
    }

    /// Creates a token. The full secret is present only on the returned object — capture it now.
    @discardableResult
    func createAccessToken(name: String, expiration: TokenExpiration) async throws -> AccessToken {
        var params: [String: Any] = ["name": name]
        if expiration != .never { params["expiration"] = expiration.rawValue }
        return try await mutation("create-access-token", params: params, as: AccessToken.self)
    }

    func deleteAccessToken(id: String) async throws {
        _ = try await mutation("delete-access-token", params: ["id": id], as: EmptyResponse.self)
    }

    // MARK: Multipart transport

    /// POSTs a single-file `multipart/form-data` body (part name `file`), for `update-profile-photo`.
    @discardableResult
    func upload<T: Decodable>(_ command: String, fileData: Data, filename: String,
                             mimeType: String, as type: T.Type) async throws -> T {
        let boundary = "penpot.\(UUID().uuidString)"
        var request = URLRequest(url: commandURL(command))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(boundary: boundary, field: "file",
                                              filename: filename, mimeType: mimeType, data: fileData)
        return try await send(request, as: type)
    }

    /// Builds an RFC 7578 multipart body with one file part. Kept static + internal so it's
    /// unit-testable without a network round-trip.
    static func multipartBody(boundary: String, field: String, filename: String,
                              mimeType: String, data: Data) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}

/// Response of `request-email-change`: `{changed: true}` when applied immediately, or an
/// empty/null body when a confirmation email was sent instead.
struct EmailChangeResult: Decodable {
    let changed: Bool?
}
