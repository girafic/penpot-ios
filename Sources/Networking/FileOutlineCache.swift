import Foundation

/// The board-grid outline of each opened file, with the `get-file` ETag it came with.
///
/// Reopening a file shows its boards at once from here and only revalidates in the
/// background: an unchanged file costs the server a 304 instead of assembling tens of MB
/// (see ``PenpotClient/fileOutline(id:ifNoneMatch:)``). The ETag includes the profile, so
/// another account on the same server simply gets a fresh 200.
struct FileOutlineCache: Sendable {
    static let shared = FileOutlineCache()

    struct Entry: Codable {
        let etag: String
        let outline: FileOutline
    }

    private let directory: URL?

    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("FileOutlines", isDirectory: true)) {
        self.directory = directory
    }

    func entry(server: URL, fileID: String) -> Entry? {
        guard let url = fileURL(server: server, fileID: fileID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    func store(_ entry: Entry, server: URL, fileID: String) {
        guard let directory, let url = fileURL(server: server, fileID: fileID),
              let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func fileURL(server: URL, fileID: String) -> URL? {
        let host = server.host ?? "server"
        let port = server.port.map { "_\($0)" } ?? ""
        return directory?.appendingPathComponent("\(host)\(port)_\(fileID).json")
    }
}
