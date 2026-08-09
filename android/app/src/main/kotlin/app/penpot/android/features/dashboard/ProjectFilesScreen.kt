package app.penpot.android.features.dashboard

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.app.FilesLayout
import app.penpot.android.common.ActionErrorDialog
import app.penpot.android.common.AppIcons
import app.penpot.android.common.ConfirmDialog
import app.penpot.android.common.EmptyState
import app.penpot.android.common.ErrorState
import app.penpot.android.common.ExportingOverlay
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.TextFieldDialog
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.penpotExportFilename
import app.penpot.android.common.rememberExportController
import app.penpot.android.common.userMessage
import app.penpot.android.nav.FileViewerRoute
import app.penpot.android.nav.ProjectFilesRoute
import app.penpot.core.model.FileListItem
import app.penpot.core.network.createFile
import app.penpot.core.network.deleteFile
import app.penpot.core.network.duplicateFile
import app.penpot.core.network.moveFiles
import app.penpot.core.network.renameFile
import app.penpot.core.network.setFileShared
import kotlinx.coroutines.launch

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ProjectFilesScreen(graph: AppGraph, nav: NavController, route: ProjectFilesRoute) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return
    val settings = graph.settings

    var files by remember { mutableStateOf<List<FileListItem>?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var isExporting by remember { mutableStateOf(false) }

    var showNewFile by remember { mutableStateOf(false) }
    var renameTarget by remember { mutableStateOf<FileListItem?>(null) }
    var deleteTarget by remember { mutableStateOf<FileListItem?>(null) }
    var unpublishTarget by remember { mutableStateOf<FileListItem?>(null) }
    var moveTarget by remember { mutableStateOf<FileListItem?>(null) }

    val exporter = rememberExportController(context) { e -> actionError = e.userMessage(context) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            files = client.projectFiles(route.projectId)
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

    fun export(file: FileListItem) {
        isExporting = true
        scope.launch {
            try {
                val bytes = client.exportBinfile(file.id)
                exporter.save(bytes, penpotExportFilename(file.name))
            } catch (e: Exception) {
                handleAuthFailure(e, appState)
                actionError = e.userMessage(context)
            } finally {
                isExporting = false
            }
        }
    }

    LaunchedEffect(Unit) { load() }

    val title = if (route.isDefaultProject) stringResource(R.string.drafts) else route.projectName

    PenpotScreen(
        title = title,
        nav = nav,
        actions = {
            FilesLayoutToggle(settings)
            IconButton(onClick = { showNewFile = true }) {
                Icon(AppIcons.add, contentDescription = stringResource(R.string.new_file))
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val current = files
            when {
                current == null && isLoading ->
                    LoadingState(stringResource(R.string.loading_files))
                current == null ->
                    ErrorState(loadError ?: "") { scope.launch { load() } }
                else -> PullToRefreshBox(
                    isRefreshing = isLoading,
                    onRefresh = { scope.launch { load() } },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    if (current.isEmpty()) {
                        EmptyState(
                            title = stringResource(R.string.no_files),
                            icon = AppIcons.document,
                            description = stringResource(R.string.this_project_has_no_files_yet),
                        )
                    } else {
                        FilesContent(
                            graph = graph,
                            files = current,
                            layout = settings.filesLayout,
                            onOpen = { file ->
                                nav.navigate(
                                    FileViewerRoute(
                                        teamId = route.teamId,
                                        fileId = file.id,
                                        fileName = file.name,
                                    ),
                                )
                            },
                            menuItems = { file, close ->
                                FileContextMenuItems(
                                    file = file,
                                    close = close,
                                    onRename = { renameTarget = file },
                                    onDuplicate = { runAction { client.duplicateFile(file.id) } },
                                    onToggleShared = {
                                        if (file.isShared == true) {
                                            unpublishTarget = file
                                        } else {
                                            runAction { client.setFileShared(file.id, true) }
                                        }
                                    },
                                    onDownload = { export(file) },
                                    onMove = { moveTarget = file },
                                    onDelete = { deleteTarget = file },
                                )
                            },
                        )
                    }
                }
            }
            ExportingOverlay(isExporting)
        }
    }

    if (showNewFile) {
        TextFieldDialog(
            title = stringResource(R.string.new_file),
            message = stringResource(R.string.enter_a_name_for_the_new_file),
            placeholder = stringResource(R.string.file_name),
            confirmLabel = stringResource(R.string.create),
            onDismiss = { showNewFile = false },
            onConfirm = { name ->
                showNewFile = false
                runAction { client.createFile(route.projectId, name) }
            },
        )
    }

    renameTarget?.let { file ->
        TextFieldDialog(
            title = stringResource(R.string.rename_file),
            message = null,
            placeholder = stringResource(R.string.file_name),
            confirmLabel = stringResource(R.string.rename),
            initialValue = file.name,
            onDismiss = { renameTarget = null },
            onConfirm = { name ->
                renameTarget = null
                runAction { client.renameFile(file.id, name) }
            },
        )
    }

    deleteTarget?.let { file ->
        ConfirmDialog(
            title = stringResource(R.string.delete_file),
            message = stringResource(R.string.s_will_be_moved_to_the_trash, file.name),
            confirmLabel = stringResource(R.string.delete),
            onDismiss = { deleteTarget = null },
            onConfirm = {
                deleteTarget = null
                runAction { client.deleteFile(file.id) }
            },
        )
    }

    unpublishTarget?.let { file ->
        ConfirmDialog(
            title = stringResource(R.string.unpublish_library),
            message = stringResource(R.string.s_will_stop_being_a_shared_library, file.name),
            confirmLabel = stringResource(R.string.unpublish),
            onDismiss = { unpublishTarget = null },
            onConfirm = {
                unpublishTarget = null
                runAction { client.setFileShared(file.id, false) }
            },
        )
    }

    moveTarget?.let { file ->
        MoveSheet(
            title = stringResource(R.string.move_to_project),
            load = {
                client.projects(route.teamId)
                    .filter { it.deletedAt == null && it.id != route.projectId }
                    .map { project ->
                        MoveTarget(
                            id = project.id,
                            name = if (project.isDefaultProject) context.getString(R.string.drafts) else project.name,
                        )
                    }
            },
            onDismiss = { moveTarget = null },
            onSelect = { target ->
                client.moveFiles(listOf(file.id), target.id)
                load()
            },
        )
    }

    ActionErrorDialog(actionError) { actionError = null }
}

/** Grid or list of files with a long-press context menu per item. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FilesContent(
    graph: AppGraph,
    files: List<FileListItem>,
    layout: FilesLayout,
    onOpen: (FileListItem) -> Unit,
    menuItems: @Composable (FileListItem, () -> Unit) -> Unit,
) {
    when (layout) {
        FilesLayout.GRID -> LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 150.dp),
            contentPadding = PaddingValues(16.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            items(count = files.size, key = { files[it].id }) { index ->
                val file = files[index]
                var showMenu by remember { mutableStateOf(false) }
                Box {
                    FileCardView(
                        graph = graph,
                        file = file,
                        modifier = Modifier
                            .fillMaxWidth()
                            .combinedClickable(
                                onClick = { onOpen(file) },
                                onLongClick = { showMenu = true },
                            ),
                    )
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        menuItems(file) { showMenu = false }
                    }
                }
            }
        }
        FilesLayout.LIST -> LazyColumn(
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            items(count = files.size, key = { files[it].id }) { index ->
                val file = files[index]
                var showMenu by remember { mutableStateOf(false) }
                Box {
                    FileRowView(
                        graph = graph,
                        file = file,
                        modifier = Modifier
                            .fillMaxWidth()
                            .combinedClickable(
                                onClick = { onOpen(file) },
                                onLongClick = { showMenu = true },
                            ),
                    )
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        menuItems(file) { showMenu = false }
                    }
                }
            }
        }
    }
}

/** The 6-item file context menu (Rename · Duplicate · Publish/Unpublish · Download · Move · Delete). */
@Composable
fun FileContextMenuItems(
    file: FileListItem,
    close: () -> Unit,
    onRename: () -> Unit,
    onDuplicate: () -> Unit,
    onToggleShared: (() -> Unit)?,
    onDownload: () -> Unit,
    onMove: (() -> Unit)?,
    onDelete: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(stringResource(R.string.rename)) },
        leadingIcon = { Icon(AppIcons.edit, null) },
        onClick = { close(); onRename() },
    )
    DropdownMenuItem(
        text = { Text(stringResource(R.string.duplicate)) },
        leadingIcon = { Icon(AppIcons.duplicate, null) },
        onClick = { close(); onDuplicate() },
    )
    if (onToggleShared != null) {
        if (file.isShared == true) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.unpublish_library), color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(AppIcons.unpublish, null, tint = MaterialTheme.colorScheme.error) },
                onClick = { close(); onToggleShared() },
            )
        } else {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.add_as_shared_library)) },
                leadingIcon = { Icon(AppIcons.library, null) },
                onClick = { close(); onToggleShared() },
            )
        }
    }
    DropdownMenuItem(
        text = { Text(stringResource(R.string.download_penpot_file_penpot)) },
        leadingIcon = { Icon(AppIcons.download, null) },
        onClick = { close(); onDownload() },
    )
    if (onMove != null) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.move_to_project)) },
            leadingIcon = { Icon(AppIcons.folder, null) },
            onClick = { close(); onMove() },
        )
    }
    DropdownMenuItem(
        text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
        leadingIcon = { Icon(AppIcons.delete, null, tint = MaterialTheme.colorScheme.error) },
        onClick = { close(); onDelete() },
    )
}
