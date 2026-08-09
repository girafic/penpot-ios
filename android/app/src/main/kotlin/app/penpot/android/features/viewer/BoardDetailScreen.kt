package app.penpot.android.features.viewer

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.ActionErrorDialog
import app.penpot.android.common.AppIcons
import app.penpot.android.common.RemoteImage
import app.penpot.android.common.assetUrl
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.common.PenpotScreen
import app.penpot.android.features.comments.CommentThreadSheet
import app.penpot.android.features.comments.NewCommentSheet
import app.penpot.android.nav.BoardDetailRoute
import app.penpot.android.nav.CanvasRoute
import app.penpot.core.model.CommentThread
import app.penpot.core.model.PinMath
import app.penpot.core.model.Point
import app.penpot.core.model.Profile
import app.penpot.core.model.Selrect
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

private data class PinDrag(val threadId: String, val position: Offset)

/**
 * Board detail: the static board thumbnail with pinch-zoom (1×–6×) and pan, and the
 * native comment-pin overlay. Pins live in the same coordinate space as the board
 * (PinMath); long-press-drag moves a pin (optimistic, with per-pin rollback), tapping
 * in add-mode places a new comment thread. Port of the iOS BoardDetailView.
 */
@Composable
fun BoardDetailScreen(graph: AppGraph, nav: NavController, route: BoardDetailRoute) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val appState = graph.appState
    val client = appState.client ?: return

    val selrect = Selrect(route.selX, route.selY, route.selWidth, route.selHeight)

    var threads by remember { mutableStateOf<List<CommentThread>>(emptyList()) }
    var profiles by remember { mutableStateOf<Map<String, Profile>>(emptyMap()) }
    var loadJob by remember { mutableStateOf<Job?>(null) }

    var scale by remember { mutableStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var addMode by remember { mutableStateOf(false) }
    var showMoveHint by remember { mutableStateOf(false) }
    var pinDrag by remember { mutableStateOf<PinDrag?>(null) }

    var selectedThread by remember { mutableStateOf<CommentThread?>(null) }
    var newCommentPosition by remember { mutableStateOf<Point?>(null) }
    var moveError by remember { mutableStateOf<String?>(null) }

    fun reload() {
        loadJob?.cancel()
        loadJob = scope.launch {
            try {
                val loaded = client.commentThreads(route.fileId)
                val loadedProfiles = runCatching { client.commentProfiles(route.fileId) }.getOrNull()
                threads = loaded
                if (loadedProfiles != null) profiles = loadedProfiles
            } catch (e: Exception) {
                handleAuthFailure(e, appState)
            }
        }
    }

    LaunchedEffect(Unit) { reload() }

    LaunchedEffect(showMoveHint) {
        if (showMoveHint) {
            delay(4_000)
            showMoveHint = false
        }
    }

    fun moveThread(thread: CommentThread, newPosition: Point) {
        // Cancel any in-flight load so a stale snapshot can't overwrite the move.
        loadJob?.cancel()
        val oldPosition = thread.position
        threads = threads.map { if (it.id == thread.id) it.copy(position = newPosition) else it }
        scope.launch {
            try {
                client.updateThreadPosition(thread.id, route.boardId, newPosition)
            } catch (e: Exception) {
                handleAuthFailure(e, appState)
                // Revert only this one pin, not the whole array.
                threads = threads.map { if (it.id == thread.id) it.copy(position = oldPosition) else it }
                moveError = e.userMessage(context)
            }
        }
    }

    PenpotScreen(
        title = route.boardName,
        nav = nav,
        actions = {
            IconButton(onClick = {
                nav.navigate(CanvasRoute(route.teamId, route.fileId, route.pageId))
            }) {
                Icon(AppIcons.expand, contentDescription = stringResource(R.string.open_live_canvas))
            }
            IconButton(onClick = { addMode = !addMode }) {
                Icon(
                    imageVector = if (addMode) AppIcons.closeFilled else AppIcons.addComment,
                    contentDescription = stringResource(R.string.new_comment),
                )
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.surfaceVariant),
        ) {
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val availableW = constraints.maxWidth.toFloat()
                val availableH = constraints.maxHeight.toFloat()
                val fitted = PinMath.fittedSize(selrect, availableW.toDouble(), availableH.toDouble())
                val fittedW = fitted.width.toFloat()
                val fittedH = fitted.height.toFloat()
                val fittedWDp = with(density) { fittedW.toDp() }
                val fittedHDp = with(density) { fittedH.toDp() }
                val pinSizePx = with(density) { 28.dp.toPx() }

                // Zoom/pan on the whole surface (suspended while placing a comment).
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .pointerInput(addMode) {
                            if (!addMode) {
                                detectTransformGestures { _, pan, zoom, _ ->
                                    scale = (scale * zoom).coerceIn(1f, 6f)
                                    offset += pan
                                }
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    // The board layer: image + pins share one transform, like on iOS.
                    Box(
                        modifier = Modifier
                            .size(fittedWDp, fittedHDp)
                            .graphicsLayer {
                                scaleX = scale
                                scaleY = scale
                                translationX = offset.x
                                translationY = offset.y
                            },
                    ) {
                        RemoteImage(
                            url = route.mediaId?.let { assetUrl(client.baseUrl, it) },
                            contentDescription = route.boardName,
                            modifier = Modifier
                                .fillMaxSize()
                                .pointerInput(addMode) {
                                    if (addMode) {
                                        detectTapGestures { tap ->
                                            if (fittedW > 0 && fittedH > 0) {
                                                val norm = PinMath.NormPoint(
                                                    x = (tap.x / fittedW).toDouble(),
                                                    y = (tap.y / fittedH).toDouble(),
                                                )
                                                newCommentPosition = PinMath.canvasPosition(norm, selrect)
                                                addMode = false
                                            }
                                        }
                                    }
                                },
                        )

                        for (thread in threads) {
                            if (thread.frameId != route.boardId) continue
                            val position = thread.position ?: continue
                            val dragging = pinDrag?.threadId == thread.id
                            val resting = run {
                                val norm = PinMath.normalized(position, selrect)
                                Offset((norm.x * fittedW).toFloat(), (norm.y * fittedH).toFloat())
                            }
                            val shown = if (dragging) pinDrag!!.position else resting
                            CommentPin(
                                thread = thread,
                                modifier = Modifier
                                    .offset {
                                        IntOffset(
                                            (shown.x - pinSizePx / 2).roundToInt(),
                                            (shown.y - pinSizePx / 2).roundToInt(),
                                        )
                                    }
                                    .scale(if (dragging) 1.3f else 1f)
                                    .shadow(if (dragging) 6.dp else 0.dp, shape = androidx.compose.foundation.shape.CircleShape)
                                    // `thread`/`position` in the keys: the pointer coroutines
                                    // capture per-composition snapshots (`resting`, `thread`) and
                                    // must restart when the pin moves or the thread reloads.
                                    .pointerInput(thread) {
                                        detectTapGestures { selectedThread = thread }
                                    }
                                    .pointerInput(thread.id, thread.position, fittedW, fittedH) {
                                        // Long-press gate is deliberate: a plain drag would
                                        // steal pans/pinches that start on a pin.
                                        detectDragGesturesAfterLongPress(
                                            onDragStart = {
                                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                                pinDrag = PinDrag(thread.id, resting)
                                            },
                                            onDrag = { change, amount ->
                                                change.consume()
                                                pinDrag = pinDrag?.let { drag ->
                                                    drag.copy(
                                                        position = Offset(
                                                            (drag.position.x + amount.x).coerceIn(0f, fittedW),
                                                            (drag.position.y + amount.y).coerceIn(0f, fittedH),
                                                        ),
                                                    )
                                                }
                                            },
                                            onDragEnd = {
                                                val drag = pinDrag
                                                pinDrag = null
                                                if (drag != null && fittedW > 0 && fittedH > 0) {
                                                    val norm = PinMath.NormPoint(
                                                        x = (drag.position.x / fittedW).toDouble(),
                                                        y = (drag.position.y / fittedH).toDouble(),
                                                    )
                                                    moveThread(thread, PinMath.canvasPosition(norm, selrect))
                                                }
                                            },
                                            onDragCancel = { pinDrag = null },
                                        )
                                    },
                            )
                        }
                    }
                }
            }

            // Hint banners under the top bar (thin surface, full width).
            val banner = when {
                addMode -> stringResource(R.string.tap_the_board_to_place_a_comment)
                showMoveHint -> stringResource(R.string.touch_and_hold_a_pin_to_move_it)
                else -> null
            }
            if (banner != null) {
                Surface(
                    tonalElevation = 3.dp,
                    modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter),
                ) {
                    Text(
                        text = banner,
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.padding(8.dp).fillMaxWidth(),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
            }
        }
    }

    selectedThread?.let { thread ->
        CommentThreadSheet(
            graph = graph,
            fileId = route.fileId,
            thread = thread,
            seedProfiles = profiles,
            onDismiss = {
                selectedThread = null
                reload()
            },
        )
    }

    newCommentPosition?.let { position ->
        NewCommentSheet(
            graph = graph,
            fileId = route.fileId,
            pageId = route.pageId,
            frameId = route.boardId,
            position = position,
            onDismiss = { newCommentPosition = null },
            onCreated = {
                newCommentPosition = null
                showMoveHint = true
                reload()
            },
        )
    }

    ActionErrorDialog(moveError) { moveError = null }
}
