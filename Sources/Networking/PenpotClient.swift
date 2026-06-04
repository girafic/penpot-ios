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

    private func commandURL(_ command: String) -> URL {
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

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
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
        case 401, 403:
            throw PenpotError.unauthorized
        default:
            throw PenpotError.server(status: http.statusCode, body: String(data: data, encoding: .utf8))
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

    func logout() async {
        _ = try? await mutation("logout", as: EmptyResponse.self)
    }

    // MARK: - Teams / projects / files

    func teams() async throws -> [Team] {
        try await query("get-teams", as: [Team].self)
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

    /// Returns a map of object (board) id → thumbnail media id.
    func objectThumbnails(fileID: String) async throws -> [String: String] {
        try await query("get-file-object-thumbnails", params: ["file-id": fileID], as: [String: String].self)
    }

    // MARK: - Comments

    func commentThreads(fileID: String) async throws -> [CommentThread] {
        try await query("get-comment-threads", params: ["file-id": fileID], as: [CommentThread].self)
    }

    func comments(threadID: String) async throws -> [Comment] {
        try await query("get-comments", params: ["thread-id": threadID], as: [Comment].self)
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
}

/// Used for commands whose response body we don't care about.
struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}
