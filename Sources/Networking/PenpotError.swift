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
        case .invalidURL:
            return String(localized: "Invalid server URL.")
        case .invalidResponse:
            return String(localized: "The server returned an unexpected response.")
        case .unauthorized:
            return String(localized: "Your session has expired. Please log in again.")
        case .forbidden:
            return String(localized: "The server blocked this request (403).")
        case let .server(status, body):
            if let body, !body.isEmpty {
                return String(localized: "Request failed (\(status)): \(body)")
            }
            return String(localized: "Request failed with status \(status).")
        case let .decoding(error):
            return String(localized: "Could not read the server response: \(error.localizedDescription)")
        }
    }
}
