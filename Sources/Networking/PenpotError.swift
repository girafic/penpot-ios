import Foundation

/// Errors surfaced by ``PenpotClient``.
enum PenpotError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case server(status: Int, body: String?)
    case decoding(Error)

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
        }
    }

    /// Penpot error bodies are JSON like `{"type":"server-error","code":"assertion",
    /// "hint":"invalid file data","explain":"…2 KB of Clojure/malli…"}`. Surface the short
    /// `hint`/`code`/`type` and drop the giant `explain` dump so the alert stays readable.
    /// Falls back to a trimmed raw body for non-JSON responses; nil for an empty body.
    private static func serverErrorSummary(from body: String?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["hint", "code", "type"] {
                if let value = json[key] as? String, !value.isEmpty { return value }
            }
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    }
}
