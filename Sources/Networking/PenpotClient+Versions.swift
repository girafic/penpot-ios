import Foundation

/// File version-history commands (Penpot ≥ 2.4). Request params are kebab-case; responses
/// camelCase. Mutation response bodies changed shape between server versions — they are
/// treated as opaque, and callers refetch the list after every mutation, exactly like the
/// web UI does. Missing edit rights surface as 404 `object-not-found` (never 403); a 404
/// *without* a `code` means the server predates the command (see
/// ``PenpotError/isUnknownCommand``).
extension PenpotClient {

    /// Lenient `create-file-snapshot` response: newer servers return a full snapshot map,
    /// 2.7 returns `{id, label}`, and only `id` is relied upon. Never throws — an empty
    /// or null body just yields a nil id.
    struct SnapshotRef: Decodable {
        let id: String?

        private enum CodingKeys: String, CodingKey { case id }

        init(from decoder: Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            id = try? container?.decodeIfPresent(String.self, forKey: .id)
        }
    }

    /// All snapshots of a file, newest first (`get-file-snapshots`). The server's SQL
    /// UNION doesn't guarantee a global order, so rows are sorted here.
    func fileSnapshots(fileID: String) async throws -> [FileSnapshot] {
        try await query("get-file-snapshots", params: ["file-id": fileID], as: [FileSnapshot].self)
            .sorted { $0.sortKey > $1.sortKey }
    }

    /// Saves the file's current state as a named version (`create-file-snapshot`).
    ///
    /// 2.7.x stamps freshly created user snapshots with a future `deleted-at`; only a
    /// follow-up `update-file-snapshot` makes them permanent — so one is sent with the
    /// same label whenever the response carried an id. Harmless on newer servers.
    @discardableResult
    func createFileSnapshot(fileID: String, label: String) async throws -> SnapshotRef {
        let ref = try await mutation("create-file-snapshot",
                                     params: ["file-id": fileID, "label": label],
                                     as: SnapshotRef.self)
        if let id = ref.id {
            try? await updateFileSnapshot(id: id, label: label)
        }
        return ref
    }

    /// Renames a version (`update-file-snapshot`; the server resolves the file from the
    /// id). This is also the "pin" operation: on a system autosave the server flips
    /// `created-by` to `"user"` and clears the expiry, making it a permanent version.
    func updateFileSnapshot(id: String, label: String) async throws {
        _ = try await mutation("update-file-snapshot",
                               params: ["id": id, "label": label],
                               as: EmptyResponse.self)
    }

    /// Replaces the file's content with the snapshot (`restore-file-snapshot`). The
    /// server first saves a system backup of the *current* state, then bumps `revn` and
    /// soft-deletes all thumbnails (they regenerate). Concurrency conflicts surface as
    /// HTTP 500 with code `file-modified`/`file-locked` — retryable, not fatal.
    func restoreFileSnapshot(fileID: String, id: String) async throws {
        _ = try await mutation("restore-file-snapshot",
                               params: ["file-id": fileID, "id": id],
                               as: EmptyResponse.self)
    }

    /// Soft-deletes a version (`delete-file-snapshot`). System autosaves can't be
    /// deleted — the server answers 400 `system-snapshots-cant-be-deleted`.
    func deleteFileSnapshot(id: String) async throws {
        _ = try await mutation("delete-file-snapshot", params: ["id": id], as: EmptyResponse.self)
    }
}
