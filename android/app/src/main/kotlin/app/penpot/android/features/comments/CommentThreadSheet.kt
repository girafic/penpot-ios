package app.penpot.android.features.comments

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.ActionErrorDialog
import app.penpot.android.common.AppIcons
import app.penpot.android.common.ConfirmDialog
import app.penpot.android.common.DateFormatting
import app.penpot.android.common.LoadingState
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.core.model.Comment
import app.penpot.core.model.CommentThread
import app.penpot.core.model.Profile
import app.penpot.core.network.PenpotError
import kotlinx.coroutines.launch

/**
 * Thread sheet: comment list + composer, resolve/reopen, owner-gated edit/delete.
 * Port of the iOS CommentThreadSheet including its careful delete semantics.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommentThreadSheet(
    graph: AppGraph,
    fileId: String,
    thread: CommentThread,
    seedProfiles: Map<String, Profile> = emptyMap(),
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var comments by remember { mutableStateOf<List<Comment>?>(null) }
    var profiles by remember { mutableStateOf(seedProfiles) }
    var isResolved by remember { mutableStateOf(thread.isResolved == true) }
    var reply by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var actionError by remember { mutableStateOf<String?>(null) }

    var menuOpen by remember { mutableStateOf(false) }
    var editTarget by remember { mutableStateOf<Comment?>(null) }
    var deleteCommentTarget by remember { mutableStateOf<Comment?>(null) }
    var confirmDeleteThread by remember { mutableStateOf(false) }

    val myProfileId = appState.profile?.id

    suspend fun loadComments() {
        try {
            comments = client.comments(thread.id)
            if (profiles.isEmpty()) {
                runCatching { client.commentProfiles(fileId) }.getOrNull()?.let { profiles = it }
            }
            // Marking read is best-effort.
            runCatching { client.markThreadRead(thread.id) }
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            actionError = e.userMessage(context)
        }
    }

    LaunchedEffect(thread.id) { loadComments() }

    fun authorName(comment: Comment): String {
        profiles[comment.ownerId]?.displayName?.let { return it }
        if (comment.ownerId != null && comment.ownerId == thread.ownerId) {
            thread.ownerFullname?.let { return it }
        }
        return context.getString(R.string.unknown)
    }

    /**
     * Delete with the iOS semantics: re-fetch after success (empty → dismiss); a 404 on
     * re-fetch means the whole thread vanished with its first comment → dismiss; any
     * other refetch failure removes locally and dismisses only if that empties the list —
     * a transient failure must not be mistaken for an emptied thread.
     */
    fun deleteComment(comment: Comment) {
        scope.launch {
            try {
                client.deleteComment(comment.id)
            } catch (e: Exception) {
                handleAuthFailure(e, appState)
                actionError = e.userMessage(context)
                return@launch
            }
            try {
                val remaining = client.comments(thread.id)
                comments = remaining
                if (remaining.isEmpty()) onDismiss()
            } catch (e: Exception) {
                if (e is PenpotError.Server && e.status == 404) {
                    onDismiss()
                } else {
                    val remaining = (comments ?: emptyList()).filter { it.id != comment.id }
                    comments = remaining
                    if (remaining.isEmpty()) onDismiss()
                }
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(modifier = Modifier.fillMaxHeight(0.92f).imePadding()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            ) {
                Text(
                    text = stringResource(R.string.comments),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                Box {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(AppIcons.more, contentDescription = stringResource(R.string.thread_actions))
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = {
                                Text(stringResource(if (isResolved) R.string.reopen else R.string.resolve))
                            },
                            leadingIcon = {
                                Icon(if (isResolved) AppIcons.unresolve else AppIcons.tick, null)
                            },
                            onClick = {
                                menuOpen = false
                                scope.launch {
                                    try {
                                        client.setThreadResolved(thread.id, !isResolved)
                                        isResolved = !isResolved
                                    } catch (e: Exception) {
                                        handleAuthFailure(e, appState)
                                        actionError = e.userMessage(context)
                                    }
                                }
                            },
                        )
                        if (thread.ownerId != null && thread.ownerId == myProfileId) {
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        stringResource(R.string.delete_thread),
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                },
                                leadingIcon = {
                                    Icon(AppIcons.delete, null, tint = MaterialTheme.colorScheme.error)
                                },
                                onClick = {
                                    menuOpen = false
                                    confirmDeleteThread = true
                                },
                            )
                        }
                    }
                }
            }

            val current = comments
            if (current == null) {
                Box(Modifier.weight(1f)) { LoadingState(stringResource(R.string.loading_comments)) }
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(count = current.size, key = { current[it].id }) { index ->
                        val comment = current[index]
                        CommentRow(
                            comment = comment,
                            authorName = authorName(comment),
                            isMine = comment.ownerId != null && comment.ownerId == myProfileId,
                            onEdit = { editTarget = comment },
                            onDelete = { deleteCommentTarget = comment },
                        )
                    }
                }
            }

            HorizontalDivider()
            Row(
                verticalAlignment = Alignment.Bottom,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
            ) {
                OutlinedTextField(
                    value = reply,
                    onValueChange = { reply = it },
                    placeholder = { Text(stringResource(R.string.reply)) },
                    minLines = 1,
                    maxLines = 4,
                    modifier = Modifier.weight(1f),
                )
                IconButton(
                    onClick = {
                        val content = reply.trim()
                        if (content.isEmpty()) return@IconButton
                        isSending = true
                        scope.launch {
                            try {
                                client.createComment(thread.id, content)
                                reply = ""
                                loadComments()
                            } catch (e: Exception) {
                                handleAuthFailure(e, appState)
                                actionError = e.userMessage(context)
                            } finally {
                                isSending = false
                            }
                        }
                    },
                    enabled = reply.trim().isNotEmpty() && !isSending,
                    modifier = Modifier.padding(start = 8.dp),
                ) {
                    if (isSending) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp))
                    } else {
                        Icon(AppIcons.send, contentDescription = stringResource(R.string.post))
                    }
                }
            }
        }
    }

    editTarget?.let { comment ->
        EditCommentDialog(
            initial = comment.content.orEmpty(),
            onDismiss = { editTarget = null },
            onSave = { newContent ->
                scope.launch {
                    try {
                        client.updateComment(comment.id, newContent)
                        editTarget = null
                        loadComments()
                    } catch (e: Exception) {
                        handleAuthFailure(e, appState)
                        actionError = e.userMessage(context)
                    }
                }
            },
        )
    }

    deleteCommentTarget?.let { comment ->
        ConfirmDialog(
            title = stringResource(R.string.delete),
            message = stringResource(R.string.delete_this_comment),
            confirmLabel = stringResource(R.string.delete),
            onDismiss = { deleteCommentTarget = null },
            onConfirm = {
                deleteCommentTarget = null
                deleteComment(comment)
            },
        )
    }

    if (confirmDeleteThread) {
        ConfirmDialog(
            title = stringResource(R.string.delete_thread),
            message = stringResource(R.string.delete_this_thread_and_all_of_its_comments),
            confirmLabel = stringResource(R.string.delete),
            onDismiss = { confirmDeleteThread = false },
            onConfirm = {
                confirmDeleteThread = false
                scope.launch {
                    try {
                        client.deleteCommentThread(thread.id)
                        onDismiss()
                    } catch (e: Exception) {
                        handleAuthFailure(e, appState)
                        actionError = e.userMessage(context)
                    }
                }
            },
        )
    }

    ActionErrorDialog(actionError) { actionError = null }
}

@Composable
private fun CommentRow(
    comment: Comment,
    authorName: String,
    isMine: Boolean,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp))
            .padding(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = authorName,
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f),
            )
            val created = DateFormatting.relative(comment.createdAt)
            if (!created.isNullOrEmpty()) {
                Text(
                    text = created,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (isMine) {
                Box {
                    IconButton(onClick = { menuOpen = true }, modifier = Modifier.size(28.dp)) {
                        Icon(
                            AppIcons.moreInline,
                            contentDescription = stringResource(R.string.comment_actions),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.edit)) },
                            leadingIcon = { Icon(AppIcons.edit, null) },
                            onClick = { menuOpen = false; onEdit() },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(AppIcons.delete, null, tint = MaterialTheme.colorScheme.error) },
                            onClick = { menuOpen = false; onDelete() },
                        )
                    }
                }
            }
        }
        Text(
            text = comment.content.orEmpty(),
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

@Composable
private fun EditCommentDialog(
    initial: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
) {
    var value by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.edit_comment)) },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it },
                placeholder = { Text(stringResource(R.string.edit_comment_2)) },
                minLines = 3,
                maxLines = 8,
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(value.trim()) },
                enabled = value.trim().isNotEmpty(),
            ) { Text(stringResource(R.string.save)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    )
}
