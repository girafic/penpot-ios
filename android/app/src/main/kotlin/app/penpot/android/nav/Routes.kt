package app.penpot.android.nav

import kotlinx.serialization.Serializable

// Type-safe Navigation-Compose routes. The app mirrors iOS: one push stack rooted at
// Teams; sheets (comment thread, new comment, move/rename dialogs) are not routes.

@Serializable
object TeamsRoute

@Serializable
data class TeamDashboardRoute(
    val teamId: String,
    val teamName: String,
    val isDefaultTeam: Boolean,
)

@Serializable
data class ProjectsRoute(val teamId: String)

@Serializable
data class ProjectFilesRoute(
    val teamId: String,
    val projectId: String,
    val projectName: String,
    val isDefaultProject: Boolean,
)

@Serializable
data class LibrariesRoute(val teamId: String)

@Serializable
data class FontsRoute(val teamId: String, val isDefaultTeam: Boolean)

@Serializable
data class TemplatesRoute(val teamId: String)

@Serializable
data class DeletedFilesRoute(val teamId: String)

@Serializable
data class FileViewerRoute(val teamId: String, val fileId: String, val fileName: String)

/** Board geometry travels in the route so the detail screen can render before any load. */
@Serializable
data class BoardDetailRoute(
    val teamId: String,
    val fileId: String,
    val pageId: String,
    val boardId: String,
    val boardName: String,
    val selX: Double,
    val selY: Double,
    val selWidth: Double,
    val selHeight: Double,
    val mediaId: String? = null,
)

/** Fullscreen live canvas (WebView). The screen loads the file itself for the page switcher. */
@Serializable
data class CanvasRoute(val teamId: String, val fileId: String, val pageId: String)

@Serializable
object CommentsInboxRoute

@Serializable
object SettingsRoute

@Serializable
object ProfileSettingsRoute

@Serializable
object PasswordSettingsRoute

@Serializable
object NotificationSettingsRoute

@Serializable
object AccessTokensRoute

@Serializable
object AppearanceRoute

@Serializable
object AboutRoute

@Serializable
object ChangeEmailRoute

@Serializable
object DeleteAccountRoute
