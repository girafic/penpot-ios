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
        guard case let .server(_, body) = self, let body,
              let json = Self.jsonBody(body) else { return nil }
        return json["code"] as? String
    }
}
