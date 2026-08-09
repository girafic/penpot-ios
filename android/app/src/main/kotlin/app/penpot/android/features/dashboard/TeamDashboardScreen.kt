package app.penpot.android.features.dashboard

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.AppIcons
import app.penpot.android.common.ErrorState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.nav.DeletedFilesRoute
import app.penpot.android.nav.FontsRoute
import app.penpot.android.nav.LibrariesRoute
import app.penpot.android.nav.ProjectFilesRoute
import app.penpot.android.nav.ProjectsRoute
import app.penpot.android.nav.TeamDashboardRoute
import app.penpot.android.nav.TemplatesRoute
import app.penpot.core.model.Project
import kotlinx.coroutines.launch

/** Per-team menu mirroring Penpot's web sidebar (not a file grid). */
@Composable
fun TeamDashboardScreen(graph: AppGraph, nav: NavController, route: TeamDashboardRoute) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var projects by remember { mutableStateOf<List<Project>?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            projects = client.projects(route.teamId)
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            loadError = e.userMessage(context)
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(Unit) { load() }

    val title = if (route.isDefaultTeam) stringResource(R.string.your_penpot) else route.teamName

    PenpotScreen(title = title, nav = nav) { padding ->
        val current = projects
        when {
            current == null && isLoading ->
                LoadingState(stringResource(R.string.loading_projects), Modifier.padding(padding))
            current == null ->
                ErrorState(loadError ?: "", Modifier.padding(padding)) { scope.launch { load() } }
            else -> {
                val active = current.filter { it.deletedAt == null }
                val drafts = active.firstOrNull { it.isDefaultProject }
                val regular = active.filter { !it.isDefaultProject }
                val pinned = regular.filter { it.isPinnedFlag }

                PullToRefreshBox(
                    isRefreshing = isLoading,
                    onRefresh = { scope.launch { load() } },
                    modifier = Modifier.padding(padding).fillMaxSize(),
                ) {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        item {
                            MenuRow(AppIcons.folder, stringResource(R.string.projects), regular.size) {
                                nav.navigate(ProjectsRoute(route.teamId))
                            }
                        }
                        item {
                            MenuRow(AppIcons.document, stringResource(R.string.drafts), drafts?.fileCount ?: 0) {
                                drafts?.let {
                                    nav.navigate(
                                        ProjectFilesRoute(
                                            teamId = route.teamId,
                                            projectId = it.id,
                                            projectName = it.name,
                                            isDefaultProject = true,
                                        ),
                                    )
                                }
                            }
                        }
                        item { SectionLabel(stringResource(R.string.sources)) }
                        item {
                            MenuRow(AppIcons.text, stringResource(R.string.fonts), null) {
                                nav.navigate(FontsRoute(route.teamId, route.isDefaultTeam))
                            }
                        }
                        item {
                            MenuRow(AppIcons.library, stringResource(R.string.libraries), null) {
                                nav.navigate(LibrariesRoute(route.teamId))
                            }
                        }
                        item {
                            MenuRow(AppIcons.template, stringResource(R.string.templates), null) {
                                nav.navigate(TemplatesRoute(route.teamId))
                            }
                        }
                        item { HorizontalDivider(Modifier.padding(vertical = 8.dp)) }
                        item {
                            MenuRow(AppIcons.delete, stringResource(R.string.recently_deleted), null) {
                                nav.navigate(DeletedFilesRoute(route.teamId))
                            }
                        }
                        item { SectionLabel(stringResource(R.string.pinned_projects)) }
                        if (pinned.isEmpty()) {
                            item {
                                Text(
                                    text = stringResource(R.string.pinned_projects_will_appear_here),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                                )
                            }
                        } else {
                            items(count = pinned.size, key = { pinned[it].id }) { index ->
                                val project = pinned[index]
                                MenuRow(AppIcons.pin, project.name, project.fileCount) {
                                    nav.navigate(
                                        ProjectFilesRoute(
                                            teamId = route.teamId,
                                            projectId = project.id,
                                            projectName = project.name,
                                            isDefaultProject = false,
                                        ),
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MenuRow(icon: ImageVector, label: String, count: Int?, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f).padding(start = 12.dp),
        )
        if (count != null && count > 0) {
            Text(
                text = count.toString(),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(end = 8.dp),
            )
        }
        ChevronForward()
    }
}

@Composable
internal fun SectionLabel(text: String) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp),
    )
}
