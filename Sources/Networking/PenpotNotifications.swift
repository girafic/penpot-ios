import Foundation

/// Penpot's notification websocket (`/ws/notifications`, `app.http.websocket`), the one
/// its workspace keeps open: subscribed to a file, it says when someone saves a change
/// (`file-change`, the changes themselves included), who else has the file open
/// (`join-file`, `presence`, `leave-file`, `disconnect`) and when it is restored or deleted.
/// Comments send nothing there.
///
/// The server writes transit `json-verbose` (`app.util.websocket`): plain JSON objects whose
/// keys and keyword values carry `~:`, uuids `~u`, tagged values `{"~#tag": value}`. It reads
/// either form, so the app writes verbose too. A session never hears its own messages; the
/// session id is the client's own, one per connection.
///
/// Authentication is the `auth-token` cookie (`session/authz`). Unlike `get-profile`, the
/// endpoint isn't behind a Cloudflare challenge on design.penpot.app.
enum PenpotNotifications {
    enum Event: Sendable {
        /// Someone saved changes. `pageIDs` are the pages they touched, `objectIDs` the
        /// shapes (and their parents) named in them; `pagesChanged` when pages were added,
        /// renamed, moved or deleted.
        case fileChange(revn: Int?, pageIDs: Set<String>, objectIDs: Set<String>, pagesChanged: Bool)
        /// Another session has the file open.
        case present(sessionID: String, profileID: String)
        /// A session closed the file.
        case left(sessionID: String)
        /// A version was restored: everything changed.
        case restored
        case deleted
    }

    /// Opens the socket and subscribes to the file. The stream ends, with an error, when the
    /// socket closes; cancelling the consuming task closes it.
    static func events(server: URL, fileID: String) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            guard let url = socketURL(server: server) else {
                continuation.finish(throwing: PenpotError.invalidURL)
                return
            }
            var request = URLRequest(url: url)
            // The session cookie, explicitly: the web views' cookie store is not URLSession's.
            if let cookie = SessionStore.authCookie(for: server) {
                request.httpShouldHandleCookies = false
                for (field, value) in HTTPCookie.requestHeaderFields(with: [cookie]) {
                    request.setValue(value, forHTTPHeaderField: field)
                }
            }
            let task = URLSession.shared.webSocketTask(with: request)
            task.maximumMessageSize = 64 * 1024 * 1024
            task.resume()

            let subscribe = encode(["type": .keyword("subscribe-file"), "file-id": .uuid(fileID)])
            let receiving = Task {
                do {
                    try await task.send(.string(subscribe))
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        let text: String? = switch message {
                        case .string(let text): text
                        case .data(let data): String(data: data, encoding: .utf8)
                        @unknown default: nil
                        }
                        if let text, let event = event(from: text, fileID: fileID) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // `keepalive` is a no-op on the server; it keeps proxies from closing a quiet socket.
            let keepalive = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    try? await task.send(.string(encode(["type": .keyword("keepalive")])))
                }
            }
            continuation.onTermination = { _ in
                receiving.cancel()
                keepalive.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    /// `ws(s)://<server>/ws/notifications?session-id=<uuid>`, the frontend's `prepare-uri`.
    static func socketURL(server: URL, sessionID: String = UUID().uuidString.lowercased()) -> URL? {
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + "/ws/notifications"
        components.queryItems = [URLQueryItem(name: "session-id", value: sessionID)]
        return components.url
    }

    // MARK: - Transit

    enum Value {
        case keyword(String)
        case uuid(String)
    }

    /// A verbose transit map of keywords and uuids.
    static func encode(_ map: [String: Value]) -> String {
        var object: [String: String] = [:]
        for (key, value) in map {
            switch value {
            case .keyword(let keyword): object["~:\(key)"] = "~:\(keyword)"
            case .uuid(let uuid): object["~:\(key)"] = "~u\(uuid)"
            }
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Verbose transit as plain values: keywords and uuids lose their prefix, tagged values
    /// (`~#shape`, `~#set`, `~#matrix`, …) their tag.
    static func decode(_ value: Any) -> Any {
        switch value {
        case let text as String:
            return decodeString(text)
        case let array as [Any]:
            return array.map(decode)
        case let object as [String: Any]:
            if object.count == 1, let entry = object.first, entry.key.hasPrefix("~#") {
                let decoded = decode(entry.value)
                // A map with non-string keys: [k1, v1, k2, v2, …].
                if entry.key == "~#cmap", let pairs = decoded as? [Any] {
                    var map: [String: Any] = [:]
                    var index = 0
                    while index + 1 < pairs.count {
                        map[String(describing: pairs[index])] = pairs[index + 1]
                        index += 2
                    }
                    return map
                }
                return decoded
            }
            var map: [String: Any] = [:]
            for (key, inner) in object { map[String(describing: decodeString(key))] = decode(inner) }
            return map
        default:
            return value
        }
    }

    private static func decodeString(_ text: String) -> Any {
        guard text.hasPrefix("~"), text.count >= 2 else { return text }
        let tag = text[text.index(after: text.startIndex)]
        let rest = String(text.dropFirst(2))
        switch tag {
        case ":", "u", "$": return rest
        case "~", "^", "`": return String(text.dropFirst())
        case "i", "n": return Int(rest) ?? rest
        case "d": return Double(rest) ?? rest
        case "?": return rest == "t"
        case "_": return NSNull()
        default: return rest
        }
    }

    /// The event a message stands for, if the app cares about it.
    static func event(from text: String, fileID: String) -> Event? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let message = decode(json) as? [String: Any],
              let type = message["type"] as? String else { return nil }
        if let file = message["file-id"] as? String, file != fileID { return nil }
        switch type {
        case "file-change":
            var pages = Set<String>(), objects = Set<String>()
            var pagesChanged = false
            for case let change as [String: Any] in message["changes"] as? [Any] ?? [] {
                if let page = change["page-id"] as? String { pages.insert(page) }
                for key in ["id", "parent-id", "frame-id"] {
                    if let id = change[key] as? String { objects.insert(id) }
                }
                for case let id as String in change["shapes"] as? [Any] ?? [] { objects.insert(id) }
                if let kind = change["type"] as? String,
                   ["add-page", "mod-page", "del-page", "mov-page"].contains(kind) {
                    pagesChanged = true
                    if let id = change["id"] as? String { pages.insert(id) }
                }
            }
            let revn = (message["revn"] as? Int) ?? (message["revn"] as? NSNumber)?.intValue
            return .fileChange(revn: revn, pageIDs: pages, objectIDs: objects, pagesChanged: pagesChanged)
        case "join-file", "presence":
            guard let session = message["session-id"] as? String,
                  let profile = message["profile-id"] as? String else { return nil }
            return .present(sessionID: session, profileID: profile)
        case "leave-file", "disconnect":
            guard let session = message["session-id"] as? String else { return nil }
            return .left(sessionID: session)
        case "file-restored":
            return .restored
        case "file-deleted":
            return .deleted
        default:
            return nil
        }
    }
}
