import Foundation

/// Errors surfaced by ``PenpotClient``.
enum PenpotError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case server(status: Int, body: String?)
    case decoding(Error)
    /// The exporter service is missing (self-hosted without the exporter container) or
    /// too old to return a downloadable resource.
    case exporterUnavailable
    /// The picked file has neither the binfile-v3 (zip) nor the binfile-v1 magic bytes.
    case invalidPenpotFile
    /// A font file exceeding the server's upload limit (30 MB default) — checked
    /// client-side before any network work.
    case fontTooLarge

    var errorDescription: String? {
        switch self {
        // `.appLocalized` (not `String(localized:)`) so errors follow the in-app language
        // picker rather than the system locale. Format strings keep their %-placeholders.
        case .invalidURL:
            return .appLocalized("Invalid server URL.")
        case .invalidResponse:
            return .appLocalized("The server returned an unexpected response.")
        case .unauthorized:
            return .appLocalized("Your session has expired. Please log in again.")
        case .forbidden:
            return .appLocalized("The server blocked this request (403).")
        case let .server(status, body):
            if let message = Self.weakPasswordMessage(from: body) { return message }
            if let message = Self.adminConsoleMessage(from: body) { return message }
            if let message = Self.accountLockedMessage(status: status, body: body) { return message }
            if let summary = Self.serverErrorSummary(from: body) {
                return String(format: .appLocalized("Request failed (%lld): %@"), status, summary)
            }
            return String(format: .appLocalized("Request failed with status %lld."), status)
        case let .decoding(error):
            return String(format: .appLocalized("Could not read the server response: %@"),
                          error.localizedDescription)
        case .exporterUnavailable:
            return .appLocalized("This server has no export service. Board export is unavailable here.")
        case .invalidPenpotFile:
            return .appLocalized("This file is not a valid .penpot export.")
        case .fontTooLarge:
            return .appLocalized("This font file is larger than 30 MB.")
        }
    }

    /// Penpot error bodies are JSON like `{"type":"server-error","code":"assertion",
    /// "hint":"invalid file data","explain":"…2 KB of Clojure/malli…"}`. Surface the short
    /// `hint`/`code`/`type` and drop the giant `explain` dump so the alert stays readable.
    /// Falls back to a trimmed raw body for non-JSON responses; nil for an empty body.
    private static func serverErrorSummary(from body: String?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        if let json = Self.jsonBody(body) {
            for key in ["hint", "code", "type"] {
                if let value = json[key] as? String, !value.isEmpty { return value }
                // Exporter error bodies are transit-encoded: keys like "~:hint" with
                // keyword values like "~:validation".
                if let value = json["~:" + key] as? String, !value.isEmpty {
                    return value.hasPrefix("~:") ? String(value.dropFirst(2)) : value
                }
            }
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    }

    /// Penpot ≥ 2.18 rejects weak passwords server-side on register, recovery and password
    /// change: `code: weak-password`, with the failed rules as `errors.weak-password.*`
    /// keys in `details`. Without this, its English `hint` would leak into the alert.
    private static func weakPasswordMessage(from body: String?) -> String? {
        guard let body, let json = jsonBody(body),
              json["code"] as? String == "weak-password" else { return nil }
        let details = json["details"] as? [String] ?? []
        if details.contains("errors.weak-password.in-dictionary") {
            return .appLocalized("This password is too common. Please choose a different one.")
        }
        return .appLocalized("Use at least 8 characters, including an uppercase letter, a lowercase letter, a number and a special character.")
    }

    /// Penpot ≥ 2.18 blocks every request with a 503 while its Admin Console (Nitrate) is
    /// unreachable or not yet set up on a self-hosted server. The body carries only a
    /// `type`, no `code`. Penpot's own wording (`labels.nitrate-*` in its .po files).
    private static func adminConsoleMessage(from body: String?) -> String? {
        guard let body, let json = jsonBody(body) else { return nil }
        switch json["type"] as? String {
        case "nitrate-unavailable":
            return .appLocalized("Penpot is temporarily unavailable due to a system issue. Please try again shortly.")
        case "nitrate-not-configured":
            return .appLocalized("Penpot can't start yet. This instance needs a setup step that comes with the latest version.")
        default:
            return nil
        }
    }

    /// Penpot ≥ 2.19 locks an account after repeated failed logins (5 within 15 minutes by
    /// default): a 429 with `code: account-locked` and the remaining lock time in `ttl`
    /// seconds. Penpot's own wording, with the minutes rounded up.
    private static func accountLockedMessage(status: Int, body: String?) -> String? {
        guard status == 429, let body, let json = jsonBody(body),
              json["code"] as? String == "account-locked" else { return nil }
        let seconds = (json["ttl"] as? NSNumber)?.doubleValue ?? 0
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return String.localizedStringWithFormat(
            .appLocalized("Too many failed attempts. Your account has been locked for %lld minutes. Please try again later."),
            minutes)
    }

    private static func jsonBody(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// True for the 404 an older server returns for an RPC command it doesn't know: the
    /// body has a `type` but **no** `code`. A 404 *with* `code == "object-not-found"`
    /// means the command exists but the id/access check failed — Penpot reports missing
    /// edit rights this way too, never as 403.
    var isUnknownCommand: Bool {
        guard case let .server(status, body) = self, status == 404,
              let body, let json = Self.jsonBody(body) else { return false }
        return json["type"] != nil && json["code"] == nil
    }

    /// The short machine-readable `code` of a server error body (e.g. `file-modified`,
    /// `snapshot-is-locked`, `max-quote-reached`), nil otherwise.
    var serverErrorCode: String? {
        guard case let .server(_, body) = self else { return nil }
        return Self.errorCode(inBody: body)
    }

    /// The `code` of a raw error body — used by the transport to tell a real
    /// :restriction 403 (JSON body with a code) from a Cloudflare challenge (HTML).
    static func errorCode(inBody body: String?) -> String? {
        guard let body, let json = jsonBody(body) else { return nil }
        return json["code"] as? String
    }

    /// The `reason` of an error body (e.g. `token-expired` on `invalid-token`), nil
    /// otherwise.
    var serverErrorReason: String? {
        guard case let .server(_, body) = self, let body,
              let json = Self.jsonBody(body) else { return nil }
        return json["reason"] as? String
    }
}
