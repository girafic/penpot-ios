package app.penpot.android.features.dashboard

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import app.penpot.android.R
import app.penpot.android.common.AppIcons
import app.penpot.android.common.EmptyState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.userMessage
import kotlinx.coroutines.launch

/** A destination in the reusable move/add picker. */
data class MoveTarget(val id: String, val name: String)

private sealed interface MovePhase {
    data object Loading : MovePhase
    data class Ready(val targets: List<MoveTarget>) : MovePhase
    data class Failed(val message: String) : MovePhase
}

/**
 * Generic modal destination picker — the Android port of the iOS MoveSheet. Used for
 * "Move to Project", "Move to Team" and "Add to project" (templates). Dismisses on
 * success; failures show an alert with [failureTitle] and re-enable the list.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoveSheet(
    title: String,
    failureTitle: String = stringResource(R.string.couldn_t_move),
    load: suspend () -> List<MoveTarget>,
    onDismiss: () -> Unit,
    onSelect: suspend (MoveTarget) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var phase by remember { mutableStateOf<MovePhase>(MovePhase.Loading) }
    var movingId by remember { mutableStateOf<String?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        phase = try {
            MovePhase.Ready(load())
        } catch (e: Exception) {
            MovePhase.Failed(e.userMessage(context))
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(modifier = Modifier.padding(bottom = 24.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            when (val current = phase) {
                is MovePhase.Loading -> Box(Modifier.fillMaxWidth().height(180.dp)) {
                    LoadingState(stringResource(R.string.loading))
                }
                is MovePhase.Failed -> Box(Modifier.fillMaxWidth().height(180.dp)) {
                    Text(
                        text = current.message,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.align(Alignment.Center).padding(16.dp),
                    )
                }
                is MovePhase.Ready -> {
                    if (current.targets.isEmpty()) {
                        Box(Modifier.fillMaxWidth().height(200.dp)) {
                            EmptyState(
                                title = stringResource(R.string.no_destinations_available),
                                icon = AppIcons.folder,
                                description = "",
                            )
                        }
                    } else {
                        LazyColumn {
                            items(count = current.targets.size, key = { current.targets[it].id }) { index ->
                                val target = current.targets[index]
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable(enabled = movingId == null) {
                                            movingId = target.id
                                            scope.launch {
                                                try {
                                                    onSelect(target)
                                                    onDismiss()
                                                } catch (e: Exception) {
                                                    failure = e.userMessage(context)
                                                    movingId = null
                                                }
                                            }
                                        }
                                        .padding(horizontal = 16.dp, vertical = 14.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(
                                        AppIcons.folder,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.secondary,
                                    )
                                    Text(
                                        text = target.name,
                                        style = MaterialTheme.typography.bodyLarge,
                                        modifier = Modifier.weight(1f).padding(start = 12.dp),
                                    )
                                    if (movingId == target.id) {
                                        CircularProgressIndicator(modifier = Modifier.size(20.dp))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    failure?.let { message ->
        AlertDialog(
            onDismissRequest = { failure = null },
            title = { Text(failureTitle) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { failure = null }) { Text(stringResource(R.string.ok)) }
            },
        )
    }
}
