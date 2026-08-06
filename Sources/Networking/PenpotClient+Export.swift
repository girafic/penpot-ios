import Foundation
import UniformTypeIdentifiers

/// A board-export output format, mapped to the exporter's `~:type` enum
/// (`png/jpeg/webp/svg/pdf` — verified in the exporter's renderer).
enum BoardExportFormat: String, CaseIterable, Identifiable {
    case png, jpeg, webp, svg, pdf

    var id: String { rawValue }
    /// The exporter's transit keyword.
    var transitType: String { "~:" + rawValue }
    /// Matches the exporter's own mime/extension table (jpeg files get `.jpg`).
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    /// For future Transferable/preview use — the share sheet keys off the temp file's
    /// extension, not this.
    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .webp: .webP
        case .svg: .svg
        case .pdf: .pdf
        }
    }
    /// Bitmap output has a pixel-density choice; vector formats don't.
    var supportsScale: Bool {
        switch self {
        case .png, .jpeg, .webp: true
        case .svg, .pdf: false
        }
    }

    /// Segmented-control label — format names are verbatim, never localized.
    var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPG"
        case .webp: "WebP"
        case .svg: "SVG"
        case .pdf: "PDF"
        }
    }
}

/// Board export via Penpot's exporter service. Unlike everything else in the client this
/// is NOT an RPC command: `POST {server}/api/export` is proxied by nginx straight to the
/// separate Node exporter, authenticated by the same `auth-token` cookie (no CSRF, no
/// client header). Body and response are transit+json (verbose): keywords travel as
/// `"~:kw"`, uuids as `"~u<lowercase>"`. The response is never the binary — it's a small
/// resource map whose `~:uri` points at a short-lived (~10 min) tempfile asset that must
/// be fetched immediately with the same cookie (the tempfile bucket is not public).
extension PenpotClient {

    struct ExportResource {
        let filename: String?
        let mtype: String?
        let uri: URL?
    }

    /// `"~u" + lowercased` — transit's uuid tag.
    static func transitUUID(_ uuid: String) -> String { "~u" + uuid.lowercased() }

    /// Escapes a leading `~`/`^` per transit rules; applies to user-controlled strings
    /// (the board name).
    static func transitString(_ string: String) -> String {
        string.hasPrefix("~") || string.hasPrefix("^") ? "~" + string : string
    }

    /// The transit json-verbose body for a single-board export (`cmd=export-shapes`,
    /// `wait=true`). Every entry field is required by the exporter's spec (`suffix` may
    /// be empty). `profile-id` is not auth-checked — it's only the exporter's progress
    /// pub/sub topic — so any uuid satisfies it.
    static func exportTransitBody(fileID: String, pageID: String, objectID: String,
                                  profileID: String, type: BoardExportFormat,
                                  scale: Double, suffix: String, name: String) throws -> Data {
        let entry: [String: Any] = [
            "~:file-id": transitUUID(fileID),
            "~:page-id": transitUUID(pageID),
            "~:object-id": transitUUID(objectID),
            "~:type": type.transitType,
            "~:scale": scale,
            "~:suffix": transitString(suffix),
            "~:name": transitString(name),
        ]
        let body: [String: Any] = [
            "~:wait": true,
            "~:cmd": "~:export-shapes",
            "~:profile-id": transitUUID(profileID),
            "~:exports": [entry],
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Parses the exporter's transit resource map (`{~:id, ~:name, ~:filename, ~:mtype,
    /// ~:uri}`). Transit has two JSON encodings — the verbose object form and the compact
    /// array form `["^ ", k1, v1, …]` — and values may carry type tags (`~r` URI, `~u`
    /// uuid); all of those are accepted here. Returns nil when the body is neither (e.g.
    /// an HTML error page slipping through a proxy). A relative uri is resolved against
    /// `baseURL`.
    static func exportResource(fromTransit data: Data, baseURL: URL) -> ExportResource? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var raw = root as? [String: Any]
        if raw == nil, let array = root as? [Any], array.first as? String == "^ " {
            var dict: [String: Any] = [:]
            var index = 1
            while index + 1 < array.count {
                if let key = array[index] as? String { dict[key] = array[index + 1] }
                index += 2
            }
            raw = dict
        }
        guard let raw else { return nil }

        // Transit value forms: plain strings, single-char-tagged strings ("~r…"/"~u…"),
        // and custom multi-char tags — Penpot registers tag "uri" for its URI type —
        // which arrive as a single-entry map {"~#uri": "…"} (verbose) or a two-element
        // array ["~#uri", "…"] (compact). Unwrap them all to the raw string.
        func stringValue(_ value: Any) -> String? {
            if let string = value as? String { return string }
            if let dict = value as? [String: Any], dict.count == 1,
               let entry = dict.first, entry.key.hasPrefix("~#") {
                return entry.value as? String
            }
            if let array = value as? [Any], array.count == 2,
               let tag = array.first as? String, tag.hasPrefix("~#") {
                return array[1] as? String
            }
            return nil
        }

        var map: [String: String] = [:]
        for (key, value) in raw {
            guard let string = stringValue(value) else { continue }
            let cleanKey = key.hasPrefix("~:") ? String(key.dropFirst(2)) : key
            map[cleanKey] = string
        }
        func untagged(_ value: String?) -> String? {
            guard let value else { return nil }
            if value.hasPrefix("~r") || value.hasPrefix("~u") { return String(value.dropFirst(2)) }
            return value
        }

        let filename = untagged(map["filename"]).flatMap { $0.isEmpty ? nil : $0 }
        var uri: URL?
        if let rawURI = untagged(map["uri"]) {
            if let absolute = URL(string: rawURI), absolute.scheme != nil {
                uri = absolute
            } else {
                uri = URL(string: rawURI, relativeTo: baseURL)?.absoluteURL
            }
        }
        // A resource carries at least one of the two; anything else isn't a resource map.
        guard filename != nil || uri != nil else { return nil }
        return ExportResource(filename: filename, mtype: untagged(map["mtype"]), uri: uri)
    }

    /// Exports one board and returns the file bytes plus the server-built filename
    /// (already sanitized and deduped, e.g. `Board 1@2x.png`).
    func exportBoard(fileID: String, pageID: String, boardID: String, boardName: String,
                     profileID: String, format: BoardExportFormat, scale: Int) async throws
        -> (data: Data, filename: String) {
        let effectiveScale = format.supportsScale ? max(1, scale) : 1
        let suffix = effectiveScale > 1 ? "@\(effectiveScale)x" : ""

        var request = URLRequest(url: baseURL.appendingPathComponent("api/export"))
        request.httpMethod = "POST"
        // Content-Type is mandatory verbatim — the exporter only transit-decodes bodies
        // declared exactly as application/transit+json.
        request.setValue("application/transit+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/transit+json", forHTTPHeaderField: "Accept")
        // Heavy boards render in headless Chromium for tens of seconds. (transportData
        // retries a timeout once, doubling the worst case — acceptable: the retry
        // usually hits an already-warm browser.)
        request.timeoutInterval = 180
        request.httpBody = try Self.exportTransitBody(
            fileID: fileID, pageID: pageID, objectID: boardID, profileID: profileID,
            type: format, scale: Double(effectiveScale), suffix: suffix, name: boardName)

        let resource = try await sendExportRequest(request, retryOnWarmup: true)
        guard let uri = resource.uri else {
            // A wait=true response without a uri comes from pre-2.12 servers. Log it —
            // this state has been silently misleading before (a tagged uri the parser
            // couldn't read looked exactly like "no exporter").
            NSLog("PenpotExport — resource without uri (filename: %@)",
                  resource.filename ?? "<none>")
            throw PenpotError.exporterUnavailable
        }
        // The server builds a sanitized, deduped filename; fall back to our own when the
        // response variant didn't carry one.
        let filename = resource.filename ?? "\(boardName)\(suffix).\(format.fileExtension)"

        // Fetch immediately — the tempfile asset is GC-eligible after ~10 minutes. The
        // auth-token cookie rides along automatically on the shared session.
        var download = URLRequest(url: uri)
        download.httpMethod = "GET"
        let (bytes, response) = try await transportData(for: download)
        guard let http = response as? HTTPURLResponse else { throw PenpotError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return (bytes, filename)
        case 401: throw PenpotError.unauthorized
        case 403: throw PenpotError.forbidden
        default: throw PenpotError.server(status: http.statusCode,
                                          body: String(data: bytes, encoding: .utf8))
        }
    }

    private func sendExportRequest(_ request: URLRequest, retryOnWarmup: Bool) async throws -> ExportResource {
        let (data, response) = try await transportData(for: request)
        guard let http = response as? HTTPURLResponse else { throw PenpotError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            guard let resource = Self.exportResource(fromTransit: data, baseURL: baseURL) else {
                // A 2xx that isn't a resource map in any known encoding: NOT the
                // "no exporter" signal (a real exporter answered) — surface it as an
                // unexpected response and log the head for diagnosis.
                NSLog("PenpotExport — unexpected 2xx body: %@",
                      String(data: data.prefix(300), encoding: .utf8) ?? "<non-utf8>")
                throw PenpotError.invalidResponse
            }
            return resource
        case 401:
            throw PenpotError.unauthorized
        case 403:
            // Not necessarily auth — Cloudflare challenge; callers must not log out.
            throw PenpotError.forbidden
        case 502:
            // nginx with no exporter container behind /api/export (self-hosted setups).
            throw PenpotError.exporterUnavailable
        case 503 where retryOnWarmup:
            // Headless browser still warming up — give it a moment and retry once.
            try await Task.sleep(for: .seconds(2))
            return try await sendExportRequest(request, retryOnWarmup: false)
        default:
            throw PenpotError.server(status: http.statusCode,
                                     body: String(data: data, encoding: .utf8))
        }
    }
}
