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
            if let body, !body.isEmpty {
                return String(format: .appLocalized("Request failed (%lld): %@"), status, body)
            }
            return String(format: .appLocalized("Request failed with status %lld."), status)
        case let .decoding(error):
            return String(format: .appLocalized("Could not read the server response: %@"),
                          error.localizedDescription)
        }
    }
}
