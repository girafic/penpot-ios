package app.penpot.android.features.comments

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.ActionErrorDialog
import app.penpot.android.common.AppIcons
import app.penpot.android.common.DateFormatting
import app.penpot.android.common.EmptyState
import app.penpot.android.common.ErrorState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotAvatar
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.features.dashboard.SectionLabel
import app.penpot.android.ui.theme.LocalPenpotColors
import app.penpot.core.model.CommentThread
import kotlinx.coroutines.launch

/**
 * Inbox of **unread** threads across every team, grouped by file. Penpot exposes no
 * team-wide "all threads" query (`get-comment-threads` requires a file-id despite its
 * documented team param) — read threads are reachable only from inside their file,
 * same as the web dashboard.
 */
@Composable
fun CommentsInboxScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var threads by remember { mutableStateOf<List<CommentThread>?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<CommentThread?>(null) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            threads = client.unreadCommentThreads(client.teams())
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            loadError = e.userMessage(context)
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(Unit) { load() }

    PenpotScreen(
        title = stringResource(R.string.comments),
        nav = nav,
        actions = {
            if (!threads.isNullOrEmpty()) {
                TextButton(onClick = {
                    scope.launch {
                        try {
                            client.markThreadsRead(threads.orEmpty().map { it.id })
                            threads = emptyList()
                        } catch (e: Exception) {
                            handleAuthFailure(e, appState)
                            actionError = e.userMessage(context)
                        }
                    }
                }) {
                    Text(stringResource(R.string.mark_all_read))
                }
            }
        },
    ) { padding ->
        val current = threads
        when {
            current == null && isLoading ->
                LoadingState(stringResource(R.string.loading_comments), Modifier.padding(padding))
            current == null ->
                ErrorState(loadError ?: "", Modifier.padding(padding)) { scope.launch { load() } }
            else -> PullToRefreshBox(
                isRefreshing = isLoading,
                onRefresh = { scope.launch { load() } },
                modifier = Modifier.padding(padding).fillMaxSize(),
            ) {
                if (current.isEmpty()) {
                    EmptyState(
                        title = stringResource(R.string.no_unread_comments),
                        icon = AppIcons.comments,
                        description = stringResource(R.string.new_comments_on_your_team_s_files_show_up_here),
                    )
                } else {
                    // Group by file, ordered by each file's most recent thread (the
                    // client already returns threads newest-first).
                    val groups = LinkedHashMap<String?, MutableList<CommentThread>>()
                    for (thread in current) {
                        groups.getOrPut(thread.fileId) { mutableListOf() }.add(thread)
                    }
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        for ((fileId, fileThreads) in groups) {
                            val fileName = fileThreads.firstOrNull()?.fileName
                            item(key = "file-${fileId ?: "unknown"}") {
                                SectionLabel(fileName ?: stringResource(R.string.unknown))
                            }
                            items(count = fileThreads.size, key = { fileThreads[it].id }) { index ->
                                val thread = fileThreads[index]
                                ThreadRow(graph, thread) { selected = thread }
                            }
                        }
                    }
                }
            }
        }
    }

    selected?.let { thread ->
        val fileId = thread.fileId
        if (fileId != null) {
            CommentThreadSheet(
                graph = graph,
                fileId = fileId,
                thread = thread,
                onDismiss = {
                    selected = null
                    // Reading marks read — re-sync on dismiss rather than pulling rows
                    // out from under the open sheet.
                    scope.launch { load() }
                },
            )
        }
    }

    ActionErrorDialog(actionError) { actionError = null }
}

@Composable
private fun ThreadRow(graph: AppGraph, thread: CommentThread, onClick: () -> Unit) {
    val colors = LocalPenpotColors.current
    Row(
        verticalAlignment = Alignment.Top,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        PenpotAvatar(
            photoId = thread.ownerPhotoId,
            name = thread.ownerFullname,
            baseUrl = graph.appState.client?.baseUrl,
            size = 32.dp,
            fallbackIcon = AppIcons.user,
        )
        Column(modifier = Modifier.weight(1f).padding(start = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = thread.ownerFullname ?: stringResource(R.string.unknown),
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                val date = DateFormatting.relative(thread.modifiedAt ?: thread.createdAt)
                if (!date.isNullOrEmpty()) {
                    Text(
                        text = date,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Text(
                text = thread.content.orEmpty(),
                style = MaterialTheme.typography.bodySmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 4.dp),
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = 4.dp),
            ) {
                thread.seqn?.let { seqn ->
                    Text(
                        text = stringResource(R.string.s, seqn.toString()),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(6.dp))
                }
                thread.countComments?.let { count ->
                    Text(
                        text = pluralStringResource(R.plurals.d_comments, count, count),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.weight(1f))
                if (thread.unreadCount > 0) {
                    Text(
                        text = stringResource(R.string.d_new, thread.unreadCount),
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.onAccent,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(colors.accent)
                            .padding(horizontal = 7.dp, vertical = 2.dp),
                    )
                }
            }
        }
    }
}
