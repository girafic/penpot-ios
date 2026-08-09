package app.penpot.core.network

import app.penpot.core.model.BuiltinTemplate
import app.penpot.core.model.DeletedFile
import app.penpot.core.model.FileListItem
import app.penpot.core.model.FontVariant
import app.penpot.core.model.Project
import app.penpot.core.model.Team
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// Team-dashboard read/write commands (fonts, shared libraries, project pinning).
// Request params are kebab-case; responses are camelCase. See PenpotJson.

/** All font variants installed for a team (`get-font-variants`). */
suspend fun PenpotClient.fontVariants(teamId: String): List<FontVariant> =
    query("get-font-variants", mapOf("team-id" to teamId))

/**
 * The team's shared library files (`get-team-shared-files`). Reuses [FileListItem];
 * library-only keys (`libraryFileIds`, `thumbnailId`) are ignored on decode.
 */
suspend fun PenpotClient.sharedLibraries(teamId: String): List<FileListItem> =
    query("get-team-shared-files", mapOf("team-id" to teamId))

/**
 * Publishes or unpublishes a file as a shared library (`set-file-shared`). Unpublishing
 * (`isShared = false`) removes it from the team's shared libraries and absorbs its assets
 * into the files that depend on it.
 */
suspend fun PenpotClient.setFileShared(id: String, isShared: Boolean) {
    mutationUnit("set-file-shared", buildJsonObject {
        put("id", id)
        put("is-shared", isShared)
    })
}

/**
 * Penpot's built-in starter templates (`get-builtin-templates`, Penpot ≥ 1.19).
 * Not team-scoped and takes no params; each entry carries only an id and a name.
 */
suspend fun PenpotClient.builtinTemplates(): List<BuiltinTemplate> =
    query("get-builtin-templates")

/**
 * Imports a built-in template into a project (`clone-template`). The server streams
 * import progress as server-sent events and the call completes when the stream ends;
 * requires edit permission on the project's team.
 */
suspend fun PenpotClient.cloneTemplate(templateId: String, projectId: String) {
    sseMutation("clone-template", buildJsonObject {
        put("template-id", templateId)
        put("project-id", projectId)
    })
}

/** Pins or unpins a project for the current profile (`update-project-pin`). Returns null. */
suspend fun PenpotClient.setProjectPinned(teamId: String, projectId: String, isPinned: Boolean) {
    mutationUnit("update-project-pin", buildJsonObject {
        put("team-id", teamId)
        put("id", projectId)
        put("is-pinned", isPinned)
    })
}

// ── Create / delete ─────────────────────────────────────────────────────────

/** Creates a team owned by the current profile (`create-team`). */
suspend fun PenpotClient.createTeam(name: String): Team =
    mutation("create-team", buildJsonObject { put("name", name) })

/**
 * Soft-deletes a team with all its projects and files (`delete-team`).
 * Owner-only; the server rejects it for the default team.
 */
suspend fun PenpotClient.deleteTeam(id: String) {
    mutationUnit("delete-team", buildJsonObject { put("id", id) })
}

/** Creates a project in a team (`create-project`). */
suspend fun PenpotClient.createProject(teamId: String, name: String): Project =
    mutation("create-project", buildJsonObject {
        put("team-id", teamId)
        put("name", name)
    })

/** Soft-deletes a project (`delete-project`). Fails for the default "Drafts" project. */
suspend fun PenpotClient.deleteProject(id: String) {
    mutationUnit("delete-project", buildJsonObject { put("id", id) })
}

/**
 * Creates an empty file with a default page in a project (`create-file`). The server
 * builds the file data — the client only supplies name + project.
 */
suspend fun PenpotClient.createFile(projectId: String, name: String): FileListItem =
    mutation("create-file", buildJsonObject {
        put("project-id", projectId)
        put("name", name)
    })

/** Soft-deletes a file (`delete-file`). */
suspend fun PenpotClient.deleteFile(id: String) {
    mutationUnit("delete-file", buildJsonObject { put("id", id) })
}

/** Soft-deletes one font variant (`delete-font-variant`); [id] is the variant id. */
suspend fun PenpotClient.deleteFontVariant(teamId: String, id: String) {
    mutationUnit("delete-font-variant", buildJsonObject {
        put("team-id", teamId)
        put("id", id)
    })
}

/** Soft-deletes a whole font family and its variants (`delete-font`); [fontId] is the `fontId`. */
suspend fun PenpotClient.deleteFont(teamId: String, fontId: String) {
    mutationUnit("delete-font", buildJsonObject {
        put("team-id", teamId)
        put("id", fontId)
    })
}

// ── Trash (recently deleted) ────────────────────────────────────────────────

/**
 * Soft-deleted files of a team that are still recoverable (`get-team-deleted-files`).
 * Includes files whose whole project was deleted. Requires Penpot ≥ 2.12.
 */
suspend fun PenpotClient.deletedFiles(teamId: String): List<DeletedFile> =
    query("get-team-deleted-files", mapOf("team-id" to teamId))

/**
 * Clears the deletion mark from files — and the projects containing them —
 * (`restore-deleted-team-files`, Penpot ≥ 2.13).
 */
suspend fun PenpotClient.restoreDeletedFiles(teamId: String, ids: List<String>) {
    sseMutation("restore-deleted-team-files", buildJsonObject {
        put("team-id", teamId)
        put("ids", JsonArray(ids.map { JsonPrimitive(it) }))
    })
}

/**
 * Schedules trashed files for immediate, irrecoverable deletion
 * (`permanently-delete-team-files`, Penpot ≥ 2.13).
 */
suspend fun PenpotClient.permanentlyDeleteFiles(teamId: String, ids: List<String>) {
    sseMutation("permanently-delete-team-files", buildJsonObject {
        put("team-id", teamId)
        put("ids", JsonArray(ids.map { JsonPrimitive(it) }))
    })
}

// ── Rename / duplicate / move ───────────────────────────────────────────────

/** Renames a team (`update-team`). The server rejects it for the default team. */
suspend fun PenpotClient.renameTeam(id: String, name: String) {
    mutationUnit("update-team", buildJsonObject {
        put("id", id)
        put("name", name)
    })
}

/** Renames a project (`rename-project`). */
suspend fun PenpotClient.renameProject(id: String, name: String) {
    mutationUnit("rename-project", buildJsonObject {
        put("id", id)
        put("name", name)
    })
}

/** Renames a file (`rename-file`). */
suspend fun PenpotClient.renameFile(id: String, name: String) {
    mutationUnit("rename-file", buildJsonObject {
        put("id", id)
        put("name", name)
    })
}

/**
 * Duplicates a file into the same project (`duplicate-file`). Omitting [name] lets the
 * server auto-generate a copy name. Note the id-param inconsistency: rename uses `id`,
 * duplicate uses `file-id`.
 */
suspend fun PenpotClient.duplicateFile(id: String, name: String? = null): FileListItem =
    mutation("duplicate-file", buildJsonObject {
        put("file-id", id)
        if (name != null) put("name", name)
    })

/** Duplicates a project (with all its files) into the same team (`duplicate-project`). */
suspend fun PenpotClient.duplicateProject(id: String, name: String? = null): Project =
    mutation("duplicate-project", buildJsonObject {
        put("project-id", id)
        if (name != null) put("name", name)
    })

/** Moves files into another project (`move-files`); the destination may be in another team. */
suspend fun PenpotClient.moveFiles(ids: List<String>, toProjectId: String) {
    mutationUnit("move-files", buildJsonObject {
        put("ids", JsonArray(ids.map { JsonPrimitive(it) }))
        put("project-id", toProjectId)
    })
}

/** Moves a project to another team (`move-project`). */
suspend fun PenpotClient.moveProject(id: String, toTeamId: String) {
    mutationUnit("move-project", buildJsonObject {
        put("project-id", id)
        put("team-id", toTeamId)
    })
}
