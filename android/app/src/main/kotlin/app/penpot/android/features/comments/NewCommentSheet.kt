package app.penpot.android.features.comments

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.core.model.Point
import kotlinx.coroutines.launch

/** New-comment composer for a tapped board position (creates a thread). */
@Composable
fun NewCommentSheet(
    graph: AppGraph,
    fileId: String,
    pageId: String,
    frameId: String,
    position: Point,
    onDismiss: () -> Unit,
    onCreated: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var content by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!isSending) onDismiss() },
        title = { Text(stringResource(R.string.new_comment)) },
        text = {
            Column {
                OutlinedTextField(
                    value = content,
                    onValueChange = { content = it },
                    placeholder = { Text(stringResource(R.string.write_a_comment)) },
                    minLines = 3,
                    maxLines = 8,
                    modifier = Modifier.fillMaxWidth(),
                )
                errorMessage?.let { message ->
                    Text(
                        text = message,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val trimmed = content.trim()
                    if (trimmed.isEmpty()) return@TextButton
                    isSending = true
                    errorMessage = null
                    scope.launch {
                        try {
                            client.createCommentThread(
                                fileId = fileId,
                                pageId = pageId,
                                frameId = frameId,
                                position = position,
                                content = trimmed,
                            )
                            onCreated()
                        } catch (e: Exception) {
                            handleAuthFailure(e, appState)
                            errorMessage = e.userMessage(context)
                        } finally {
                            isSending = false
                        }
                    }
                },
                enabled = content.trim().isNotEmpty() && !isSending,
            ) { Text(stringResource(R.string.post)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isSending) {
                Text(stringResource(R.string.cancel))
            }
        },
    )
}
