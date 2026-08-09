package app.penpot.android.features.dashboard

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import app.penpot.android.common.DateFormatting
import app.penpot.android.common.EmptyState
import app.penpot.android.common.ErrorState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.nav.DeletedFilesRoute
import app.penpot.core.model.DeletedFile
import app.penpot.core.model.Project
import app.penpot.core.network.deletedFiles
import app.penpot.core.network.permanentlyDeleteFiles
import app.penpot.core.network.restoreDeletedFiles
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DeletedFilesScreen(graph: AppGraph, nav: NavController, route: DeletedFilesRoute) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var files by remember { mutableStateOf<List<DeletedFile>?>(null) }
    var projects by remember { mutableStateOf<List<Project>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var purgeTarget by remember { mutableStateOf<DeletedFile?>(null) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            coroutineScope {
                val deleted = async { client.deletedFiles(route.teamId) }
                // Project names are best-effort; deleted projects may not resolve.
                val loadedProjects = async { runCatching { client.projects(route.teamId) }.getOrDefault(emptyList()) }
                files = deleted.await()
                projects = loadedProjects.await()
            }
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

    PenpotScreen(title = stringResource(R.string.recently_deleted), nav = nav) { padding ->
        val current = files
        when {
            current == null && isLoading ->
                LoadingState(stringResource(R.string.loading_deleted_files), Modifier.padding(padding))
            current == null ->
                ErrorState(loadError ?: "", Modifier.padding(padding)) { scope.launch { load() } }
            else -> PullToRefreshBox(
                isRefreshing = isLoading,
                onRefresh = { scope.launch { load() } },
                modifier = Modifier.padding(padding).fillMaxSize(),
            ) {
                if (current.isEmpty()) {
                    EmptyState(
                        title = stringResource(R.string.no_deleted_items),
                        icon = AppIcons.delete,
                        description = stringResource(R.string.deleted_files_can_be_restored_here_for_a_limited_time),
                    )
                } else {
                    // Group by project, preserving the server's most-recently-modified
                    // order (an ordered grouping, not a plain groupBy re-sort).
                    val groups = LinkedHashMap<String?, MutableList<DeletedFile>>()
                    for (file in current) {
                        groups.getOrPut(file.projectId) { mutableListOf() }.add(file)
                    }
                    val projectsById = projects.associateBy { it.id }
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        for ((projectId, groupFiles) in groups) {
                            val project = projectId?.let { projectsById[it] }
                            val header = when {
                                project?.isDefaultProject == true -> context.getString(R.string.drafts)
                                project != null -> project.name
                                else -> context.getString(R.string.project)
                            }
                            item(key = "header-${projectId ?: "unknown"}") { SectionLabel(header) }
                            items(count = groupFiles.size, key = { groupFiles[it].id }) { index ->
                                val file = groupFiles[index]
                                DeletedFileRow(
                                    file = file,
                                    onRestore = {
                                        runAction { client.restoreDeletedFiles(route.teamId, listOf(file.id)) }
                                    },
                                    onDeleteForever = { purgeTarget = file },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    purgeTarget?.let { file ->
        ConfirmDialog(
            title = stringResource(R.string.delete_forever),
            message = stringResource(R.string.s_will_be_permanently_deleted_this_cannot_be_undone, file.name),
            confirmLabel = stringResource(R.string.delete_forever),
            onDismiss = { purgeTarget = null },
            onConfirm = {
                purgeTarget = null
                runAction { client.permanentlyDeleteFiles(route.teamId, listOf(file.id)) }
            },
        )
    }

    ActionErrorDialog(actionError) { actionError = null }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DeletedFileRow(
    file: DeletedFile,
    onRestore: () -> Unit,
    onDeleteForever: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    Box {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(onClick = { showMenu = true }, onLongClick = { showMenu = true })
                .padding(horizontal = 16.dp, vertical = 10.dp),
        ) {
            Text(text = file.name, style = MaterialTheme.typography.bodyLarge)
            val deadline = DateFormatting.relative(file.willBeDeletedAt)
            if (!deadline.isNullOrEmpty()) {
                Text(
                    text = stringResource(R.string.will_be_permanently_deleted_s, deadline),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.restore)) },
                leadingIcon = { Icon(AppIcons.restore, null) },
                onClick = { showMenu = false; onRestore() },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.delete_forever), color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(AppIcons.delete, null, tint = MaterialTheme.colorScheme.error) },
                onClick = { showMenu = false; onDeleteForever() },
            )
        }
    }
}
