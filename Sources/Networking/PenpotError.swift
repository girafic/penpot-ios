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
            return "Invalid server URL."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .unauthorized:
            return "Your session has expired. Please log in again."
        case .forbidden:
            return "The server blocked this request (403)."
        case let .server(status, body):
            if let body, !body.isEmpty {
                return "Request failed (\(status)): \(body)"
            }
            return "Request failed with status \(status)."
        case let .decoding(error):
            return "Could not read the server response: \(error.localizedDescription)"
        }
    }
}
