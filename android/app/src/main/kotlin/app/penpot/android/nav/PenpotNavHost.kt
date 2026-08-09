package app.penpot.android.nav

import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import app.penpot.android.AppGraph
import app.penpot.android.features.comments.CommentsInboxScreen
import app.penpot.android.features.dashboard.DeletedFilesScreen
import app.penpot.android.features.dashboard.FontsScreen
import app.penpot.android.features.dashboard.LibrariesScreen
import app.penpot.android.features.dashboard.ProjectFilesScreen
import app.penpot.android.features.dashboard.ProjectsListScreen
import app.penpot.android.features.dashboard.TeamDashboardScreen
import app.penpot.android.features.dashboard.TeamsScreen
import app.penpot.android.features.dashboard.TemplatesScreen
import app.penpot.android.features.settings.AboutScreen
import app.penpot.android.features.settings.AccessTokensScreen
import app.penpot.android.features.settings.AppearanceScreen
import app.penpot.android.features.settings.ChangeEmailScreen
import app.penpot.android.features.settings.DeleteAccountScreen
import app.penpot.android.features.settings.NotificationSettingsScreen
import app.penpot.android.features.settings.PasswordSettingsScreen
import app.penpot.android.features.settings.ProfileSettingsScreen
import app.penpot.android.features.settings.SettingsScreen
import app.penpot.android.features.viewer.BoardDetailScreen
import app.penpot.android.features.viewer.FileViewerScreen
import app.penpot.android.features.viewer.PenpotCanvasScreen

/** The authenticated navigation tree — a single push stack rooted at Teams. */
@Composable
fun PenpotNavHost(graph: AppGraph) {
    val nav = rememberNavController()
    NavHost(navController = nav, startDestination = TeamsRoute) {
        composable<TeamsRoute> { TeamsScreen(graph, nav) }
        composable<TeamDashboardRoute> { entry ->
            TeamDashboardScreen(graph, nav, entry.toRoute())
        }
        composable<ProjectsRoute> { entry -> ProjectsListScreen(graph, nav, entry.toRoute()) }
        composable<ProjectFilesRoute> { entry -> ProjectFilesScreen(graph, nav, entry.toRoute()) }
        composable<LibrariesRoute> { entry -> LibrariesScreen(graph, nav, entry.toRoute()) }
        composable<FontsRoute> { entry -> FontsScreen(graph, nav, entry.toRoute()) }
        composable<TemplatesRoute> { entry -> TemplatesScreen(graph, nav, entry.toRoute()) }
        composable<DeletedFilesRoute> { entry -> DeletedFilesScreen(graph, nav, entry.toRoute()) }
        composable<FileViewerRoute> { entry -> FileViewerScreen(graph, nav, entry.toRoute()) }
        composable<BoardDetailRoute> { entry -> BoardDetailScreen(graph, nav, entry.toRoute()) }
        composable<CanvasRoute> { entry -> PenpotCanvasScreen(graph, nav, entry.toRoute()) }
        composable<CommentsInboxRoute> { CommentsInboxScreen(graph, nav) }
        composable<SettingsRoute> { SettingsScreen(graph, nav) }
        composable<ProfileSettingsRoute> { ProfileSettingsScreen(graph, nav) }
        composable<PasswordSettingsRoute> { PasswordSettingsScreen(graph, nav) }
        composable<NotificationSettingsRoute> { NotificationSettingsScreen(graph, nav) }
        composable<AccessTokensRoute> { AccessTokensScreen(graph, nav) }
        composable<AppearanceRoute> { AppearanceScreen(graph, nav) }
        composable<AboutRoute> { AboutScreen(graph, nav) }
        composable<ChangeEmailRoute> { ChangeEmailScreen(graph, nav) }
        composable<DeleteAccountRoute> { DeleteAccountScreen(graph, nav) }
    }
}
