package app.penpot.android.features.dashboard

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.ActionErrorDialog
import app.penpot.android.common.AppIcons
import app.penpot.android.common.ConfirmDialog
import app.penpot.android.common.EmptyState
import app.penpot.android.common.ErrorState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.TextFieldDialog
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.nav.ProjectFilesRoute
import app.penpot.android.nav.ProjectsRoute
import app.penpot.core.model.Project
import app.penpot.core.network.createProject
import app.penpot.core.network.deleteProject
import app.penpot.core.network.duplicateProject
import app.penpot.core.network.moveProject
import app.penpot.core.network.renameProject
import app.penpot.core.network.setProjectPinned
import kotlinx.coroutines.launch

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ProjectsListScreen(graph: AppGraph, nav: NavController, route: ProjectsRoute) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var projects by remember { mutableStateOf<List<Project>?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var pinning by remember { mutableStateOf<Set<String>>(emptySet()) }

    var showNewProject by remember { mutableStateOf(false) }
    var renameTarget by remember { mutableStateOf<Project?>(null) }
    var deleteTarget by remember { mutableStateOf<Project?>(null) }
    var moveTarget by remember { mutableStateOf<Project?>(null) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            projects = client.projects(route.teamId)
                .filter { it.deletedAt == null && !it.isDefaultProject }
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            loadError = e.userMessage(context)
        } finally {
            isLoading = false
        }
    }

    fun runAction(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
                load()
            } catch (e: Exception) {
                handleAuthFailure(e, appState)
                actionError = e.userMessage(context)
            }
        }
    }

    LaunchedEffect(Unit) { load() }

    PenpotScreen(
        title = stringResource(R.string.projects),
        nav = nav,
        actions = {
            IconButton(onClick = { showNewProject = true }) {
                Icon(AppIcons.add, contentDescription = stringResource(R.string.new_project))
            }
        },
    ) { padding ->
        val current = projects
        when {
            current == null && isLoading ->
                LoadingState(stringResource(R.string.loading_projects), Modifier.padding(padding))
            current == null ->
                ErrorState(loadError ?: "", Modifier.padding(padding)) { scope.launch { load() } }
            else -> PullToRefreshBox(
                isRefreshing = isLoading,
                onRefresh = { scope.launch { load() } },
                modifier = Modifier.padding(padding).fillMaxSize(),
            ) {
                if (current.isEmpty()) {
                    EmptyState(
                        title = stringResource(R.string.no_projects),
                        icon = AppIcons.folder,
                        description = stringResource(R.string.this_team_has_no_projects_yet),
                    )
                } else {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(count = current.size, key = { current[it].id }) { index ->
                            val project = current[index]
                            ProjectRow(
                                project = project,
                                isPinning = project.id in pinning,
                                onOpen = {
                                    nav.navigate(
                                        ProjectFilesRoute(
                                            teamId = route.teamId,
                                            projectId = project.id,
                                            projectName = project.name,
                                            isDefaultProject = false,
                                        ),
                                    )
                                },
                                onRename = { renameTarget = project },
                                onDuplicate = { runAction { client.duplicateProject(project.id) } },
                                onMove = { moveTarget = project },
                                onTogglePin = {
                                    if (project.id !in pinning) {
                                        pinning = pinning + project.id
                                        scope.launch {
                                            try {
                                                client.setProjectPinned(
                                                    route.teamId, project.id, !project.isPinnedFlag,
                                                )
                                                load()
                                            } catch (e: Exception) {
                                                handleAuthFailure(e, appState)
                                                actionError = e.userMessage(context)
                                            } finally {
                                                pinning = pinning - project.id
                                            }
                                        }
                                    }
                                },
                                onDelete = { deleteTarget = project },
                            )
                        }
                    }
                }
            }
        }
    }

    if (showNewProject) {
        TextFieldDialog(
            title = stringResource(R.string.new_project),
            message = stringResource(R.string.enter_a_name_for_the_new_project),
            placeholder = stringResource(R.string.project_name),
            confirmLabel = stringResource(R.string.create),
            onDismiss = { showNewProject = false },
            onConfirm = { name ->
                showNewProject = false
                runAction { client.createProject(route.teamId, name) }
            },
        )
    }

    renameTarget?.let { project ->
        TextFieldDialog(
            title = stringResource(R.string.rename_project),
            message = null,
            placeholder = stringResource(R.string.project_name),
            confirmLabel = stringResource(R.string.rename),
            initialValue = project.name,
            onDismiss = { renameTarget = null },
            onConfirm = { name ->
                renameTarget = null
                runAction { client.renameProject(project.id, name) }
            },
        )
    }

    deleteTarget?.let { project ->
        ConfirmDialog(
            title = stringResource(R.string.delete_project),
            message = stringResource(R.string.s_will_be_moved_to_the_trash, project.name),
            confirmLabel = stringResource(R.string.delete),
            onDismiss = { deleteTarget = null },
            onConfirm = {
                deleteTarget = null
                runAction { client.deleteProject(project.id) }
            },
        )
    }

    moveTarget?.let { project ->
        MoveSheet(
            title = stringResource(R.string.move_to_team),
            load = {
                client.teams()
                    .filter { it.id != route.teamId }
                    .map { MoveTarget(it.id, if (it.isDefaultTeam) context.getString(R.string.your_penpot) else it.name) }
            },
            onDismiss = { moveTarget = null },
            onSelect = { target ->
                client.moveProject(project.id, target.id)
                load()
            },
        )
    }

    ActionErrorDialog(actionError) { actionError = null }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ProjectRow(
    project: Project,
    isPinning: Boolean,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onDuplicate: () -> Unit,
    onMove: () -> Unit,
    onTogglePin: () -> Unit,
    onDelete: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(onClick = onOpen, onLongClick = { showMenu = true })
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(AppIcons.folder, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
            Text(
                text = project.name,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f).padding(start = 12.dp),
            )
            if (project.fileCount > 0) {
                Text(
                    text = project.fileCount.toString(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(end = 8.dp),
                )
            }
            ChevronForward()
        }
        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.rename)) },
                leadingIcon = { Icon(AppIcons.edit, null) },
                onClick = { showMenu = false; onRename() },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.duplicate)) },
                leadingIcon = { Icon(AppIcons.duplicate, null) },
                onClick = { showMenu = false; onDuplicate() },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.move_to_team)) },
                leadingIcon = { Icon(AppIcons.folder, null) },
                onClick = { showMenu = false; onMove() },
            )
            DropdownMenuItem(
                text = {
                    Text(stringResource(if (project.isPinnedFlag) R.string.unpin else R.string.pin))
                },
                leadingIcon = { Icon(AppIcons.pin, null) },
                enabled = !isPinning,
                onClick = { showMenu = false; onTogglePin() },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(AppIcons.delete, null, tint = MaterialTheme.colorScheme.error) },
                onClick = { showMenu = false; onDelete() },
            )
        }
    }
}
