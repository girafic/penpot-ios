package app.penpot.android.features.viewer

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.AppIcons
import app.penpot.android.common.EmptyState
import app.penpot.android.common.ErrorState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.RemoteImage
import app.penpot.android.common.assetUrl
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.nav.BoardDetailRoute
import app.penpot.android.nav.CanvasRoute
import app.penpot.android.nav.FileViewerRoute
import app.penpot.core.model.Board
import app.penpot.core.model.PenpotFile
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

@Composable
fun FileViewerScreen(graph: AppGraph, nav: NavController, route: FileViewerRoute) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var file by remember { mutableStateOf<PenpotFile?>(null) }
    var thumbnails by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            coroutineScope {
                val fileAsync = async { client.file(route.fileId) }
                val thumbsAsync = async { runCatching { client.objectThumbnails(route.fileId) }.getOrDefault(emptyMap()) }
                file = fileAsync.await()
                thumbnails = thumbsAsync.await()
            }
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            loadError = e.userMessage(context)
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(Unit) { load() }

    fun openCanvas(pageId: String) {
        nav.navigate(CanvasRoute(teamId = route.teamId, fileId = route.fileId, pageId = pageId))
    }

    PenpotScreen(title = route.fileName, nav = nav) { padding ->
        val current = file
        when {
            current == null && isLoading ->
                LoadingState(stringResource(R.string.loading_file), Modifier.padding(padding))
            current == null ->
                ErrorState(loadError ?: "", Modifier.padding(padding)) { scope.launch { load() } }
            else -> PullToRefreshBox(
                isRefreshing = isLoading,
                onRefresh = { scope.launch { load() } },
                modifier = Modifier.padding(padding).fillMaxSize(),
            ) {
                val pages = current.pages
                val hasAnyContent = pages.any { it.hasContent }
                if (!hasAnyContent) {
                    EmptyState(
                        title = stringResource(R.string.file_is_empty),
                        icon = AppIcons.board,
                        description = stringResource(R.string.this_file_has_no_boards_or_objects_yet_use_penpot_on_your_co),
                    ) {
                        Button(onClick = { pages.firstOrNull()?.let { openCanvas(it.id) } }) {
                            Icon(AppIcons.expand, null, modifier = Modifier.size(18.dp))
                            Text(
                                stringResource(R.string.open_canvas),
                                modifier = Modifier.padding(start = 8.dp),
                            )
                        }
                    }
                } else {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(28.dp),
                    ) {
                        for (page in pages) {
                            PageSection(
                                graph = graph,
                                route = route,
                                nav = nav,
                                pageId = page.id,
                                pageName = page.name,
                                boards = page.boards,
                                canvasObjectCount = page.canvasObjectCount,
                                thumbnails = thumbnails,
                                onOpenCanvas = { openCanvas(page.id) },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PageSection(
    graph: AppGraph,
    route: FileViewerRoute,
    nav: NavController,
    pageId: String,
    pageName: String,
    boards: List<Board>,
    canvasObjectCount: Int,
    thumbnails: Map<String, String>,
    onOpenCanvas: () -> Unit,
) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = pageName,
                style = MaterialTheme.typography.titleLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = pluralStringResource(R.plurals.d_boards, boards.size, boards.size),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            IconButton(onClick = onOpenCanvas) {
                Icon(
                    AppIcons.expand,
                    contentDescription = stringResource(R.string.open_live_canvas),
                    modifier = Modifier.size(18.dp),
                )
            }
        }
        when {
            boards.isNotEmpty() -> Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                for (rowBoards in boards.chunked(2)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        for (board in rowBoards) {
                            BoardThumbnailCard(
                                graph = graph,
                                board = board,
                                mediaId = thumbnails[board.id],
                                modifier = Modifier.weight(1f),
                            ) {
                                nav.navigate(
                                    BoardDetailRoute(
                                        teamId = route.teamId,
                                        fileId = route.fileId,
                                        pageId = pageId,
                                        boardId = board.id,
                                        boardName = board.name,
                                        selX = board.selrect.x,
                                        selY = board.selrect.y,
                                        selWidth = board.selrect.width,
                                        selHeight = board.selrect.height,
                                        mediaId = thumbnails[board.id],
                                    ),
                                )
                            }
                        }
                        if (rowBoards.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
            canvasObjectCount > 0 -> CanvasContentCard(canvasObjectCount, onOpenCanvas)
            else -> Text(
                text = stringResource(R.string.no_boards_on_this_page),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun BoardThumbnailCard(
    graph: AppGraph,
    board: Board,
    mediaId: String?,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val baseUrl = graph.appState.client?.baseUrl
    val shape = RoundedCornerShape(10.dp)
    Column(modifier = modifier.clickable(onClick = onClick)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(140.dp)
                .clip(shape)
                .background(MaterialTheme.colorScheme.surface)
                .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, shape),
        ) {
            RemoteImage(
                url = if (mediaId != null && baseUrl != null) assetUrl(baseUrl, mediaId) else null,
                contentDescription = board.name,
                modifier = Modifier.fillMaxSize().padding(8.dp),
            )
        }
        Text(
            text = board.name,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 6.dp),
        )
    }
}

/** Dashed card for loose canvas shapes — visible only in the live canvas. */
@Composable
private fun CanvasContentCard(count: Int, onOpenCanvas: () -> Unit) {
    val shape = RoundedCornerShape(10.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, shape)
            .clickable(onClick = onOpenCanvas)
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            AppIcons.board,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(28.dp),
        )
        Text(
            text = pluralStringResource(R.plurals.d_objects_on_the_canvas, count, count),
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = 8.dp),
        )
        Text(
            text = stringResource(R.string.not_inside_a_board_open_the_canvas_to_view_them),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 2.dp),
        )
    }
}
