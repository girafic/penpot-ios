import Foundation

/// `.penpot` binfile import (`import-binfile`, Penpot ≥ 1.15). The bytes travel as
/// `multipart/form-data` — plain form fields `name`, `project-id` (and `version` for a
/// legacy archive) plus the `file` part — and the response is an SSE progress stream
/// that terminates with an `end` event (success; payload = the new file ids) or an
/// `error` event (failure, under an already-committed HTTP 200).
///
/// `version` (v3 = zip, v1 = Penpot's legacy binary, sniffed from the magic bytes):
/// servers up to 2.17 read it as an int, default to 3 and don't detect the format.
/// 2.18+ detect it themselves and validate the field as `[:enum 1 3]`, which a
/// multipart field (always text: `"3"`) never matches, so the import failed with a 400
/// `params-validation`. Penpot's web app sends no `version`. So a zip goes without it,
/// and a v1 archive sends it and is retried once without it when the server rejects
/// the field. Missing edit rights on the project surface as 404 `object-not-found`,
/// never 403.
extension PenpotClient {

    /// Sniffs the binfile format: 3 for a zip archive (`PK\x03\x04`, modern exports),
    /// 1 for the legacy binary header (`01 0B 1A 86`), nil for anything else.
    static func binfileVersion(of data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        let magic = [UInt8](data.prefix(4))
        if magic == [0x50, 0x4B, 0x03, 0x04] { return 3 }
        if magic == [0x01, 0x0B, 0x1A, 0x86] { return 1 }
        return nil
    }

    /// RFC 7578 multipart body with plain fields followed by one file part. Static +
    /// internal so it's unit-testable without a network round-trip.
    static func multipartFormBody(boundary: String,
                                  fields: [(name: String, value: String)],
                                  file: (field: String, filename: String, mimeType: String, data: Data)) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        for field in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            append("\(field.value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.filename)\"\r\n")
        append("Content-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// Terminal outcome of a buffered SSE body: the `end` event's payload on success,
    /// the `error` event's payload on failure (both nil = the stream never terminated).
    static func sseOutcome(from body: String) -> (endPayload: String?, errorPayload: String?) {
        var currentEvent: String?
        var currentData: [String] = []
        var endPayload: String?
        var errorPayload: String?
        func commit() {
            let payload = currentData.joined(separator: "\n")
            if currentEvent == "end" { endPayload = payload }
            if currentEvent == "error" { errorPayload = payload }
            currentEvent = nil
            currentData = []
        }
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty { commit(); continue }
            if line.hasPrefix("event:") {
                currentEvent = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                currentData.append(String(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)))
            }
        }
        commit()
        return (endPayload, errorPayload)
    }

    /// The plain form fields of `import-binfile`. Only a legacy v1 archive names its
    /// version, and only while `sendVersion` (see the type's notes).
    static func importFields(name: String, projectID: String, version: Int,
                             sendVersion: Bool) -> [(name: String, value: String)] {
        var fields = [("name", name), ("project-id", projectID)]
        if version == 1, sendVersion { fields.append(("version", String(version))) }
        return fields
    }

    /// Whether a 400 body is 2.18+'s schema rejecting the `version` field. That check
    /// runs before the import starts, so retrying without the field creates no duplicate.
    static func rejectsVersionField(_ body: String?) -> Bool {
        guard let body else { return false }
        return body.contains("params-validation") && body.contains(":version")
    }

    private struct VersionFieldRejected: Error {}

    /// Imports a `.penpot` archive into a project. `name` is the file's display name
    /// (the picked filename minus its extension). Callers refresh the project's file
    /// list afterwards — the end payload (the new file ids) is not needed for that.
    func importBinfile(projectID: String, name: String, data: Data) async throws {
        guard let version = Self.binfileVersion(of: data) else {
            throw PenpotError.invalidPenpotFile
        }
        do {
            try await postBinfile(projectID: projectID, name: name, data: data,
                                  version: version, sendVersion: true)
        } catch is VersionFieldRejected {
            try await postBinfile(projectID: projectID, name: name, data: data,
                                  version: version, sendVersion: false)
        }
    }

    private func postBinfile(projectID: String, name: String, data: Data,
                             version: Int, sendVersion: Bool) async throws {
        let boundary = "penpot.\(UUID().uuidString)"
        var request = URLRequest(url: commandURL("import-binfile"))
        request.httpMethod = "POST"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Large archives upload + import server-side for a while.
        request.timeoutInterval = 300
        request.httpBody = Self.multipartFormBody(
            boundary: boundary,
            fields: Self.importFields(name: name, projectID: projectID, version: version,
                                      sendVersion: sendVersion),
            file: (field: "file",
                   filename: "\(name).penpot",
                   mimeType: version == 3 ? "application/zip" : "application/octet-stream",
                   data: data))

        // Deliberately no transient retry: a timeout after the server started importing
        // would create the file twice.
        let (responseData, response) = try await transportDataNoRetry(for: request)
        guard let http = response as? HTTPURLResponse else { throw PenpotError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw PenpotError.unauthorized
        case 403:
            throw PenpotError.forbidden
        default:
            // Pre-stream failures (validation, 404 object-not-found, 413 too large) are
            // ordinary HTTP errors.
            let body = String(data: responseData, encoding: .utf8)
            if http.statusCode == 400, version == 1, sendVersion, Self.rejectsVersionField(body) {
                throw VersionFieldRejected()
            }
            throw PenpotError.server(status: http.statusCode, body: body)
        }

        let body = String(data: responseData, encoding: .utf8) ?? ""
        let outcome = Self.sseOutcome(from: body)
        guard outcome.endPayload != nil else {
            // Mid-stream failures arrive as an `error` event under a committed 200; the
            // payload is the usual transit error map (hint/code surface via the summary).
            throw PenpotError.server(status: 400, body: outcome.errorPayload ?? body)
        }
    }
}
