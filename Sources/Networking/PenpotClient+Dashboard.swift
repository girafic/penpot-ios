import Foundation

/// Team-dashboard read/write commands (fonts, shared libraries, project pinning).
/// Request params are kebab-case; responses are camelCase. See ``JSONCoding``.
extension PenpotClient {

    /// All font variants installed for a team (`get-font-variants`).
    func fontVariants(teamID: String) async throws -> [FontVariant] {
        try await query("get-font-variants", params: ["team-id": teamID], as: [FontVariant].self)
    }

    /// The team's shared library files (`get-team-shared-files`). Reuses `FileListItem`;
    /// library-only keys (`libraryFileIds`, `isShared`, `thumbnailId`) are ignored on decode.
    func sharedLibraries(teamID: String) async throws -> [FileListItem] {
        try await query("get-team-shared-files", params: ["team-id": teamID], as: [FileListItem].self)
    }

    /// Publishes or unpublishes a file as a shared library (`set-file-shared`). Unpublishing
    /// (`isShared: false`) removes it from the team's shared libraries and absorbs its assets
    /// into the files that depend on it.
    func setFileShared(id: String, isShared: Bool) async throws {
        _ = try await mutation("set-file-shared",
                               params: ["id": id, "is-shared": isShared],
                               as: EmptyResponse.self)
    }

    /// Penpot's built-in starter templates (`get-builtin-templates`, Penpot ≥ 1.19).
    /// Not team-scoped and takes no params; each entry carries only an id and a name.
    func builtinTemplates() async throws -> [BuiltinTemplate] {
        try await query("get-builtin-templates", as: [BuiltinTemplate].self)
    }

    /// Imports a built-in template into a project (`clone-template`). The server streams
    /// import progress as server-sent events and the call completes when the stream ends;
    /// requires edit permission on the project's team.
    func cloneTemplate(templateID: String, projectID: String) async throws {
        try await sseMutation("clone-template", params: [
            "template-id": templateID,
            "project-id": projectID,
        ])
    }

    /// Pins or unpins a project for the current profile (`update-project-pin`). Returns null.
    func setProjectPinned(teamID: String, projectID: String, isPinned: Bool) async throws {
        _ = try await mutation("update-project-pin", params: [
            "team-id": teamID,
            "id": projectID,
            "is-pinned": isPinned,
        ], as: EmptyResponse.self)
    }

    // MARK: Create / delete

    /// Creates a team owned by the current profile (`create-team`).
    @discardableResult
    func createTeam(name: String) async throws -> Team {
        try await mutation("create-team", params: ["name": name], as: Team.self)
    }

    /// Soft-deletes a team with all its projects and files (`delete-team`).
    /// Owner-only; the server rejects it for the default team.
    func deleteTeam(id: String) async throws {
        _ = try await mutation("delete-team", params: ["id": id], as: EmptyResponse.self)
    }

    /// Creates a project in a team (`create-project`).
    @discardableResult
    func createProject(teamID: String, name: String) async throws -> Project {
        try await mutation("create-project", params: ["team-id": teamID, "name": name], as: Project.self)
    }

    /// Soft-deletes a project (`delete-project`). Fails for the default "Drafts" project.
    func deleteProject(id: String) async throws {
        _ = try await mutation("delete-project", params: ["id": id], as: EmptyResponse.self)
    }

    /// Creates an empty file with a default page in a project (`create-file`). The server
    /// builds the file data — the client only supplies name + project.
    @discardableResult
    func createFile(projectID: String, name: String) async throws -> FileListItem {
        try await mutation("create-file", params: ["project-id": projectID, "name": name], as: FileListItem.self)
    }

    /// Soft-deletes a file (`delete-file`).
    func deleteFile(id: String) async throws {
        _ = try await mutation("delete-file", params: ["id": id], as: EmptyResponse.self)
    }

    /// Soft-deletes one font variant (`delete-font-variant`); `id` is the variant id.
    func deleteFontVariant(teamID: String, id: String) async throws {
        _ = try await mutation("delete-font-variant", params: ["team-id": teamID, "id": id], as: EmptyResponse.self)
    }

    /// Soft-deletes a whole font family and its variants (`delete-font`); `fontID` is the `fontId`.
    func deleteFont(teamID: String, fontID: String) async throws {
        _ = try await mutation("delete-font", params: ["team-id": teamID, "id": fontID], as: EmptyResponse.self)
    }

    // MARK: Trash (recently deleted)

    /// Soft-deleted files of a team that are still recoverable (`get-team-deleted-files`).
    /// Includes files whose whole project was deleted. Requires Penpot ≥ 2.12.
    func deletedFiles(teamID: String) async throws -> [DeletedFile] {
        try await query("get-team-deleted-files", params: ["team-id": teamID], as: [DeletedFile].self)
    }

    /// Clears the deletion mark from files — and the projects containing them —
    /// (`restore-deleted-team-files`, Penpot ≥ 2.13).
    func restoreDeletedFiles(teamID: String, ids: [String]) async throws {
        try await sseMutation("restore-deleted-team-files", params: ["team-id": teamID, "ids": ids])
    }

    /// Schedules trashed files for immediate, irrecoverable deletion
    /// (`permanently-delete-team-files`, Penpot ≥ 2.13).
    func permanentlyDeleteFiles(teamID: String, ids: [String]) async throws {
        try await sseMutation("permanently-delete-team-files", params: ["team-id": teamID, "ids": ids])
    }

    // MARK: Rename / duplicate / move

    /// Renames a team (`update-team`). The server rejects it for the default team.
    func renameTeam(id: String, name: String) async throws {
        _ = try await mutation("update-team", params: ["id": id, "name": name], as: EmptyResponse.self)
    }

    /// Renames a project (`rename-project`).
    func renameProject(id: String, name: String) async throws {
        _ = try await mutation("rename-project", params: ["id": id, "name": name], as: EmptyResponse.self)
    }

    /// Renames a file (`rename-file`).
    func renameFile(id: String, name: String) async throws {
        _ = try await mutation("rename-file", params: ["id": id, "name": name], as: EmptyResponse.self)
    }

    /// Duplicates a file into the same project (`duplicate-file`). Omitting `name` lets the
    /// server auto-generate a copy name.
    @discardableResult
    func duplicateFile(id: String, name: String? = nil) async throws -> FileListItem {
        var params: [String: Any] = ["file-id": id]
        if let name { params["name"] = name }
        return try await mutation("duplicate-file", params: params, as: FileListItem.self)
    }

    /// Duplicates a project (with all its files) into the same team (`duplicate-project`).
    @discardableResult
    func duplicateProject(id: String, name: String? = nil) async throws -> Project {
        var params: [String: Any] = ["project-id": id]
        if let name { params["name"] = name }
        return try await mutation("duplicate-project", params: params, as: Project.self)
    }

    /// Moves files into another project (`move-files`); the destination may be in another team.
    func moveFiles(ids: [String], toProjectID: String) async throws {
        _ = try await mutation("move-files", params: ["ids": ids, "project-id": toProjectID], as: EmptyResponse.self)
    }

    /// Moves a project to another team (`move-project`).
    func moveProject(id: String, toTeamID: String) async throws {
        _ = try await mutation("move-project", params: ["project-id": id, "team-id": toTeamID], as: EmptyResponse.self)
    }
}
