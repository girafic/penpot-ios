import Foundation

/// Font upload/management commands (upload requires the chunked-upload API, Penpot
/// ≥ 2.17 — the legacy inline `data` param is unusable over JSON and removed in 2.18).
/// The backend never parses the font binary: family/weight/style come from the client
/// (see ``FontFileMetadata``), and font-id/family grouping is a CLIENT convention with
/// no server-side uniqueness.
extension PenpotClient {

    private struct UploadSession: Decodable { let sessionId: String }

    /// The web client's chunk size.
    static let fontChunkSize = 10 * 1024 * 1024
    /// Server default `font-max-file-size`.
    static let fontMaxFileSize = 30 * 1024 * 1024

    /// Number of upload chunks for a payload (10-MiB chunks, minimum 1).
    static func fontChunkCount(forSize size: Int) -> Int {
        max(1, (size + fontChunkSize - 1) / fontChunkSize)
    }

    /// Opens a chunked-upload session (`create-upload-session`). Quotas: ≤ 20 chunks
    /// per session, ≤ 5 sessions per profile (400 `max-quote-reached`).
    func createUploadSession(totalChunks: Int) async throws -> String {
        try await mutation("create-upload-session",
                           params: ["total-chunks": totalChunks],
                           as: UploadSession.self).sessionId
    }

    /// Uploads one chunk (`upload-chunk`, multipart: `session-id`, `index`, `content`).
    /// Deliberately no transient retry: a blind resend could double-store a chunk and
    /// trip assembly's exact-count check — on failure the caller restarts with a fresh
    /// session (sessions are single-use).
    func uploadChunk(sessionID: String, index: Int, data: Data) async throws {
        let boundary = "penpot.\(UUID().uuidString)"
        var request = URLRequest(url: commandURL("upload-chunk"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = Self.multipartFormBody(
            boundary: boundary,
            fields: [("session-id", sessionID), ("index", String(index))],
            file: (field: "content", filename: "chunk-\(index)",
                   mimeType: "application/octet-stream", data: data))
        let (responseData, response) = try await transportDataNoRetry(for: request)
        guard let http = response as? HTTPURLResponse else { throw PenpotError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw PenpotError.unauthorized
        case 403: throw PenpotError.forbidden
        default: throw PenpotError.server(status: http.statusCode,
                                          body: String(data: responseData, encoding: .utf8))
        }
    }

    /// Registers an uploaded session as a font variant (`create-font-variant`).
    /// `fontID` is client-generated — reuse an existing family's `fontId` so variants
    /// group; the uploads-map key must be one of font/ttf|otf|woff|woff2.
    @discardableResult
    func createFontVariant(teamID: String, fontID: String,
                           metadata: FontFileMetadata, sessionID: String) async throws -> FontVariant {
        try await mutation("create-font-variant", params: [
            "team-id": teamID,
            "font-id": fontID,
            "font-family": metadata.family,
            "font-weight": metadata.weight,
            "font-style": metadata.style,
            "uploads": [metadata.mimeType: sessionID],
        ], as: FontVariant.self)
    }

    /// Full upload orchestration: size check → session → sequential chunks →
    /// `create-font-variant`. `onProgress` reports 0…1 (files < 10 MiB are one chunk).
    @discardableResult
    func uploadFontVariant(teamID: String, fontID: String,
                           metadata: FontFileMetadata, data: Data,
                           onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> FontVariant {
        guard data.count <= Self.fontMaxFileSize else { throw PenpotError.fontTooLarge }
        let chunkSize = Self.fontChunkSize
        let totalChunks = Self.fontChunkCount(forSize: data.count)
        let sessionID = try await createUploadSession(totalChunks: totalChunks)
        for index in 0..<totalChunks {
            let start = index * chunkSize
            let end = min(start + chunkSize, data.count)
            try await uploadChunk(sessionID: sessionID, index: index,
                                  data: data.subdata(in: start..<end))
            onProgress?(Double(index + 1) / Double(totalChunks + 1))
        }
        let variant = try await createFontVariant(teamID: teamID, fontID: fontID,
                                                  metadata: metadata, sessionID: sessionID)
        onProgress?(1)
        return variant
    }

    /// Renames a whole font family (`update-font`; `fontID` = the family's `fontId`).
    func updateFont(teamID: String, fontID: String, name: String) async throws {
        _ = try await mutation("update-font",
                               params: ["team-id": teamID, "id": fontID, "name": name],
                               as: EmptyResponse.self)
    }

    struct FontDownload: Decodable {
        let id: String?
        let uri: String?
        let name: String?
    }

    /// Downloads a family as a zip (`download-font-family` — POST-only, the name
    /// doesn't start with `get-`). The zip is a TEMPORARY storage object (~30 min),
    /// so it is fetched immediately.
    func downloadFontFamilyArchive(fontID: String) async throws -> (data: Data, name: String) {
        let download = try await mutation("download-font-family",
                                          params: ["font-id": fontID],
                                          as: FontDownload.self)
        guard let rawURI = download.uri,
              let url = Self.assetURL(fromSSEPayload: rawURI, baseURL: baseURL) else {
            throw PenpotError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (bytes, response) = try await transportData(for: request)
        guard let http = response as? HTTPURLResponse else { throw PenpotError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return (bytes, download.name ?? "fonts.zip")
        case 401: throw PenpotError.unauthorized
        case 403: throw PenpotError.forbidden
        default: throw PenpotError.server(status: http.statusCode,
                                          body: String(data: bytes, encoding: .utf8))
        }
    }
}
