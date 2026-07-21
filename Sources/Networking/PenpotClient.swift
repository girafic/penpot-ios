import Foundation

/// Thin client over Penpot's RPC HTTP API (`{server}/api/rpc/command/<command>`).
///
/// Query commands are issued as GET (params in the query string), mutation commands as
/// POST with a JSON body. Authentication relies on the `auth-token` session cookie that
/// Penpot sets on `login-with-password`; `URLSession`'s shared cookie storage carries it
/// automatically on subsequent requests.
final class PenpotClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func commandURL(_ command: String) -> URL {
        baseURL.appendingPathComponent("api/rpc/command/\(command)")
    }

    // MARK: - Generic transport

    /// GET query command. `params` keys are sent verbatim (Penpot uses kebab-case, e.g. `file-id`).
    func query<T: Decodable>(_ command: String, params: [String: String] = [:], as type: T.Type) async throws -> T {
        guard var components = URLComponents(url: commandURL(command), resolvingAgainstBaseURL: false) else {
            throw PenpotError.invalidURL
        }
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw PenpotError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, as: type)
    }

    /// POST mutation command with a JSON body. `params` keys are kebab-case (e.g. `thread-id`).
    @discardableResult
    func mutation<T: Decodable>(_ command: String, params: [String: Any] = [:], as type: T.Type) async throws -> T {
        var request = URLRequest(url: commandURL(command))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        return try await send(request, as: type)
    }

    func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await transportData(for: request)
        guard let http = response as? HTTPURLResponse else { throw PenpotError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            // Some mutations (e.g. mark-as-read) return an empty body on success.
            let payload = data.isEmpty ? Data("null".utf8) : data
            do {
                return try JSONDecoder.penpot.decode(T.self, from: payload)
            } catch {
                throw PenpotError.decoding(error)
            }
        case 401:
            throw PenpotError.unauthorized
        case 403:
            // Not necessarily an auth failure — e.g. a Cloudflare bot challenge. Callers
            // must not treat this as "session invalid" and log the user out.
            throw PenpotError.forbidden
        default:
            throw PenpotError.server(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    /// POST mutation whose response is a server-sent-events stream (commands declared
    /// `::sse/stream? true`, e.g. `restore-deleted-team-files`). Event payloads are
    /// transit-encoded, so they aren't decoded — the call succeeds when the stream ends
    /// with an `end` event and throws if the server emitted an `error` event instead.
    func sseMutation(_ command: String, params: [String: Any]) async throws {
        var request = URLRequest(url: commandURL(command))
        request.httpMethod = "POST"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await transportData(for: request)
        guard let http = response as? HTTPURLResponse else { throw PenpotError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw PenpotError.unauthorized
        case 403: throw PenpotError.forbidden
        default: throw PenpotError.server(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        let events = body.split(separator: "\n")
            .filter { $0.hasPrefix("event:") }
            .map { $0.dropFirst("event:".count).trimmingCharacters(in: .whitespaces) }
        guard events.contains("end"), !events.contains("error") else {
            throw PenpotError.server(status: http.statusCode, body: body)
        }
    }

    /// Runs an SSE command and returns the data payload of its terminal `end` event.
    ///
    /// Like ``sseMutation`` but keeps the value the stream carries: `export-binfile` reports
    /// progress and ends with an `end` event whose payload is the URL of the generated file.
    /// Penpot transit-encodes payloads, so the raw `data:` string is returned as-is for the
    /// caller to parse.
    private func sseResult(_ command: String, params: [String: Any]) async throws -> String {
        var request = URLRequest(url: commandURL(command))
        request.httpMethod = "POST"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await transportData(for: request)
        guard let http = response as? HTTPURLResponse else { throw PenpotError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw PenpotError.unauthorized
        case 403: throw PenpotError.forbidden
        default: throw PenpotError.server(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        guard let payload = Self.sseEndPayload(from: body) else {
            throw PenpotError.server(status: http.statusCode, body: body)
        }
        return payload
    }

    /// Pulls the `data:` payload of the terminating `end` event out of a buffered SSE body,
    /// or `nil` if the stream carried an `error` event or never reached `end`.
    static func sseEndPayload(from body: String) -> String? {
        var currentEvent: String?
        var currentData: [String] = []
        var endPayload: String?
        var sawError = false
        func commit() {
            if currentEvent == "error" { sawError = true }
            if currentEvent == "end", !currentData.isEmpty { endPayload = currentData.joined(separator: "\n") }
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
        return sawError ? nil : endPayload
    }

    // MARK: - File export

    /// Exports a file as a native Penpot binary (`.penpot`) and returns the archive bytes.
    ///
    /// `export-binfile` is an SSE command: the server builds the archive, stores it briefly
    /// (~60 min) under `/assets/by-id/<id>`, and streams that URL back as the `end` payload —
    /// which this then follows to download the bytes. `include-libraries`/`embed-assets`
    /// default to `false` (a plain single-file export). The `version` param was removed in
    /// Penpot 2.12, so it is deliberately not sent.
    func exportBinfile(fileID: String, includeLibraries: Bool = false, embedAssets: Bool = false) async throws -> Data {
        let payload = try await sseResult("export-binfile", params: [
            "file-id": fileID,
            "include-libraries": includeLibraries,
            "embed-assets": embedAssets,
        ])
        guard let url = Self.assetURL(fromSSEPayload: payload, baseURL: baseURL) else {
            throw PenpotError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await transportData(for: request)
        guard let http = response as? HTTPURLResponse else { throw PenpotError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw PenpotError.unauthorized
        case 403: throw PenpotError.forbidden
        default: throw PenpotError.server(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    /// Recovers the download URL from an `export-binfile` SSE payload. The payload is normally
    /// an absolute URL, but Penpot transit-encodes it (e.g. `["~#'","https://…"]`), so we scan
    /// for the URL rather than decode transit. Falls back to resolving a relative
    /// `/assets/by-id/…` path against the server base URL.
    static func assetURL(fromSSEPayload raw: String, baseURL: URL) -> URL? {
        if let match = raw.range(of: #"https?://[^\s"'\]\\]+"#, options: .regularExpression) {
            return URL(string: String(raw[match]))
        }
        if let match = raw.range(of: #"/assets/by-id/[^\s"'\]\\]+"#, options: .regularExpression) {
            return URL(string: String(raw[match]), relativeTo: baseURL)?.absoluteURL
        }
        return nil
    }

    /// Performs the request, retrying once on a transient transport failure.
    ///
    /// Penpot is served over HTTP/2 behind Cloudflare. An idle connection pooled by
    /// `URLSession` can be closed by the edge and then reused before the client notices,
    /// surfacing as `NSURLErrorNetworkConnectionLost` (-1005). In that race the request
    /// bytes never reached the server, so an immediate retry on a fresh connection
    /// recovers transparently. A brief timeout is treated the same way.
    private func transportData(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where Self.isRetriableTransportError(error) {
            return try await session.data(for: request)
        }
    }

    private static func isRetriableTransportError(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost, .timedOut:
            return true
        default:
            return false
        }
    }

    // MARK: - Auth

    @discardableResult
    func login(email: String, password: String) async throws -> Profile {
        try await mutation("login-with-password",
                           params: ["email": email, "password": password],
                           as: Profile.self)
    }

    func profile() async throws -> Profile {
        try await query("get-profile", as: Profile.self)
    }

    /// Provisions a throwaway demo account and returns its credentials. Requires no auth;
    /// the caller logs in with the returned email/password. Only succeeds when the server
    /// has the `demo-users` flag enabled, otherwise the server rejects the command.
    @discardableResult
    func createDemoProfile() async throws -> DemoProfile {
        try await mutation("create-demo-profile", as: DemoProfile.self)
    }

    func logout() async {
        _ = try? await mutation("logout", as: EmptyResponse.self)
    }

    // MARK: - Teams / projects / files

    func teams() async throws -> [Team] {
        try await query("get-teams", as: [Team].self)
    }

    func teamMembers(teamID: String) async throws -> [TeamMember] {
        try await query("get-team-members", params: ["team-id": teamID], as: [TeamMember].self)
    }

    func projects(teamID: String) async throws -> [Project] {
        try await query("get-projects", params: ["team-id": teamID], as: [Project].self)
    }

    func projectFiles(projectID: String) async throws -> [FileListItem] {
        try await query("get-project-files", params: ["project-id": projectID], as: [FileListItem].self)
    }

    func file(id: String) async throws -> PenpotFile {
        try await query("get-file", params: ["id": id], as: PenpotFile.self)
    }

    /// Returns a map of board (frame) id → thumbnail media id.
    func objectThumbnails(fileID: String) async throws -> [String: String] {
        let raw = try await query("get-file-object-thumbnails", params: ["file-id": fileID], as: [String: String].self)
        return Self.frameThumbnails(from: raw)
    }

    /// Penpot keys object thumbnails by a composite `"<file-id>/<page-id>/<frame-id>/frame"`.
    /// Re-key by the bare frame id (unique within a file) so callers can look up by board id.
    /// Tolerates an older bare-frame-id format too.
    static func frameThumbnails(from raw: [String: String]) -> [String: String] {
        var byFrame: [String: String] = [:]
        for (key, mediaID) in raw {
            let parts = key.split(separator: "/")
            if parts.count == 1 {
                byFrame[key] = mediaID
            } else if parts.last == "frame", parts.count >= 2 {
                byFrame[String(parts[parts.count - 2])] = mediaID
            }
        }
        return byFrame
    }

    // MARK: - Comments

    func commentThreads(fileID: String) async throws -> [CommentThread] {
        try await query("get-comment-threads", params: ["file-id": fileID], as: [CommentThread].self)
    }

    func comments(threadID: String) async throws -> [Comment] {
        try await query("get-comments", params: ["thread-id": threadID], as: [Comment].self)
    }

    /// Threads in `team` that have comments the current user hasn't read yet.
    ///
    /// This is the only team-wide thread query Penpot offers. `get-comment-threads` documents a
    /// `team-id` param but its implementation ignores it and requires a `file-id`.
    func unreadCommentThreads(teamID: String) async throws -> [CommentThread] {
        try await query("get-unread-comment-threads", params: ["team-id": teamID], as: [CommentThread].self)
    }

    /// Unread threads across every team, newest first.
    ///
    /// One team failing is tolerated — its threads are simply missing — but if every team
    /// fails the error is rethrown, so callers don't render "nothing unread" for a network
    /// outage or an expired session.
    func unreadCommentThreads(teams: [Team]) async throws -> [CommentThread] {
        guard !teams.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: [CommentThread].self) { group in
            for team in teams {
                group.addTask { try await self.unreadCommentThreads(teamID: team.id) }
            }
            var all: [CommentThread] = []
            var failures = 0
            var lastError: Error?
            while true {
                do {
                    guard let threads = try await group.next() else { break }
                    all.append(contentsOf: threads)
                } catch {
                    failures += 1
                    lastError = error
                }
            }
            if let lastError, failures == teams.count { throw lastError }
            return all.sorted {
                PenpotDate.sortKey($0.modifiedAt ?? $0.createdAt) > PenpotDate.sortKey($1.modifiedAt ?? $1.createdAt)
            }
        }
    }

    /// Marks every given thread as read in one round trip.
    func markThreadsRead(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await mutation("mark-all-threads-as-read", params: ["threads": ids], as: EmptyResponse.self)
    }

    func commentProfiles(fileID: String) async throws -> [String: Profile] {
        try await query("get-profiles-for-file-comments",
                        params: ["file-id": fileID],
                        as: ProfilesResponse.self).byID
    }

    @discardableResult
    func createCommentThread(fileID: String, pageID: String, frameID: String,
                             position: Point, content: String) async throws -> CommentThread {
        try await mutation("create-comment-thread", params: [
            "file-id": fileID,
            "page-id": pageID,
            "frame-id": frameID,
            "position": ["x": position.x, "y": position.y],
            "content": content,
        ], as: CommentThread.self)
    }

    @discardableResult
    func createComment(threadID: String, content: String) async throws -> Comment {
        try await mutation("create-comment",
                           params: ["thread-id": threadID, "content": content],
                           as: Comment.self)
    }

    /// Moves a comment thread's pin to a new canvas position.
    func updateThreadPosition(id: String, frameID: String, position: Point) async throws {
        _ = try await mutation("update-comment-thread-position", params: [
            "id": id,
            "frame-id": frameID,
            "position": ["x": position.x, "y": position.y],
        ], as: EmptyResponse.self)
    }

    func setThreadResolved(id: String, isResolved: Bool) async throws {
        _ = try await mutation("update-comment-thread",
                               params: ["id": id, "is-resolved": isResolved],
                               as: EmptyResponse.self)
    }

    func markThreadRead(id: String) async throws {
        _ = try await mutation("update-comment-thread-status",
                               params: ["id": id],
                               as: EmptyResponse.self)
    }

    /// Edits the text of an existing comment.
    func updateComment(id: String, content: String) async throws {
        _ = try await mutation("update-comment",
                               params: ["id": id, "content": content],
                               as: EmptyResponse.self)
    }

    /// Deletes a single comment. Deleting a thread's first comment removes the whole thread.
    func deleteComment(id: String) async throws {
        _ = try await mutation("delete-comment", params: ["id": id], as: EmptyResponse.self)
    }

    /// Deletes an entire comment thread and all of its comments.
    func deleteCommentThread(id: String) async throws {
        _ = try await mutation("delete-comment-thread", params: ["id": id], as: EmptyResponse.self)
    }
}

/// Used for commands whose response body we don't care about.
struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}
