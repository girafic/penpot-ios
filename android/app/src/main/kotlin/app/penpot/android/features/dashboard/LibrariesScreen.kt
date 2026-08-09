package app.penpot.android.features.dashboard

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
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
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
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
import app.penpot.android.nav.LibrariesRoute
import app.penpot.core.model.FileListItem
import app.penpot.core.network.duplicateFile
import app.penpot.core.network.renameFile
import app.penpot.core.network.setFileShared
import app.penpot.core.network.sharedLibraries
import kotlinx.coroutines.launch

@Composable
fun LibrariesScreen(graph: AppGraph, nav: NavController, route: LibrariesRoute) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return
    val settings = graph.settings

    var libraries by remember { mutableStateOf<List<FileListItem>?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var isExporting by remember { mutableStateOf(false) }

    var renameTarget by remember { mutableStateOf<FileListItem?>(null) }
    var unpublishTarget by remember { mutableStateOf<FileListItem?>(null) }

    val exporter = rememberExportController(context) { e -> actionError = e.userMessage(context) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            libraries = client.sharedLibraries(route.teamId)
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
        title = stringResource(R.string.libraries),
        nav = nav,
        actions = { FilesLayoutToggle(settings) },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val current = libraries
            when {
                current == null && isLoading ->
                    LoadingState(stringResource(R.string.loading_libraries))
                current == null ->
                    ErrorState(loadError ?: "") { scope.launch { load() } }
                else -> PullToRefreshBox(
                    isRefreshing = isLoading,
                    onRefresh = { scope.launch { load() } },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    if (current.isEmpty()) {
                        EmptyState(
                            title = stringResource(R.string.no_shared_libraries),
                            icon = AppIcons.library,
                            description = stringResource(R.string.shared_libraries_for_this_team_will_appear_here),
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
                                // The library menu is 4 items: Rename · Duplicate · Download · Unpublish.
                                androidx.compose.material3.DropdownMenuItem(
                                    text = { androidx.compose.material3.Text(stringResource(R.string.rename)) },
                                    leadingIcon = { androidx.compose.material3.Icon(AppIcons.edit, null) },
                                    onClick = { close(); renameTarget = file },
                                )
                                androidx.compose.material3.DropdownMenuItem(
                                    text = { androidx.compose.material3.Text(stringResource(R.string.duplicate)) },
                                    leadingIcon = { androidx.compose.material3.Icon(AppIcons.duplicate, null) },
                                    onClick = {
                                        close()
                                        runAction { client.duplicateFile(file.id) }
                                    },
                                )
                                androidx.compose.material3.DropdownMenuItem(
                                    text = { androidx.compose.material3.Text(stringResource(R.string.download_penpot_file_penpot)) },
                                    leadingIcon = { androidx.compose.material3.Icon(AppIcons.download, null) },
                                    onClick = {
                                        close()
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
                                    },
                                )
                                androidx.compose.material3.DropdownMenuItem(
                                    text = {
                                        androidx.compose.material3.Text(
                                            stringResource(R.string.unpublish_library),
                                            color = androidx.compose.material3.MaterialTheme.colorScheme.error,
                                        )
                                    },
                                    leadingIcon = {
                                        androidx.compose.material3.Icon(
                                            AppIcons.unpublish, null,
                                            tint = androidx.compose.material3.MaterialTheme.colorScheme.error,
                                        )
                                    },
                                    onClick = { close(); unpublishTarget = file },
                                )
                            },
                        )
                    }
                }
            }
            ExportingOverlay(isExporting)
        }
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

    ActionErrorDialog(actionError) { actionError = null }
}
