package app.penpot.android.features.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3Api
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
import app.penpot.android.common.ErrorState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.features.dashboard.SectionLabel
import app.penpot.core.model.CommentNotification
import app.penpot.core.model.InviteNotification
import app.penpot.core.model.NotificationSettings
import app.penpot.core.network.fetchNotifications
import app.penpot.core.network.updateNotifications
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationSettingsScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var current by remember { mutableStateOf<NotificationSettings?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var isSaving by remember { mutableStateOf(false) }
    var actionError by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        loadError = null
        try {
            // Read path is a no-op update-profile-props (get-profile is Cloudflare-blocked).
            current = client.fetchNotifications()
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            loadError = e.userMessage(context)
        }
    }

    LaunchedEffect(Unit) { load() }

    PenpotScreen(title = stringResource(R.string.notifications), nav = nav) { padding ->
        val settings = current
        when {
            settings == null && loadError == null ->
                LoadingState(stringResource(R.string.loading_notifications), Modifier.padding(padding))
            settings == null ->
                ErrorState(loadError ?: "", Modifier.padding(padding)) { scope.launch { load() } }
            else -> Column(
                modifier = Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = 24.dp),
            ) {
                SectionLabel(stringResource(R.string.dashboard))
                Text(
                    text = stringResource(R.string.comments),
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
                CommentPicker(
                    selection = settings.dashboardComments,
                    onSelect = { current = settings.copy(dashboardComments = it) },
                )

                SectionLabel(stringResource(R.string.email))
                Text(
                    text = stringResource(R.string.comments),
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
                CommentPicker(
                    selection = settings.emailComments,
                    onSelect = { current = settings.copy(emailComments = it) },
                )
                Text(
                    text = stringResource(R.string.team_invitations),
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
                SingleChoiceSegmentedButtonRow(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                ) {
                    InviteNotification.entries.forEachIndexed { index, entry ->
                        SegmentedButton(
                            selected = settings.emailInvites == entry,
                            onClick = { current = settings.copy(emailInvites = entry) },
                            shape = SegmentedButtonDefaults.itemShape(index, InviteNotification.entries.size),
                        ) {
                            Text(
                                stringResource(
                                    when (entry) {
                                        InviteNotification.ALL -> R.string.all
                                        InviteNotification.NONE -> R.string.none
                                    },
                                ),
                            )
                        }
                    }
                }

                Button(
                    onClick = {
                        isSaving = true
                        scope.launch {
                            try {
                                client.updateNotifications(settings)
                                nav.popBackStack()
                            } catch (e: Exception) {
                                handleAuthFailure(e, appState)
                                actionError = e.userMessage(context)
                            } finally {
                                isSaving = false
                            }
                        }
                    },
                    enabled = !isSaving,
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp))
                    } else {
                        Text(stringResource(R.string.save))
                    }
                }
            }
        }
    }

    ActionErrorDialog(actionError) { actionError = null }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CommentPicker(
    selection: CommentNotification,
    onSelect: (CommentNotification) -> Unit,
) {
    SingleChoiceSegmentedButtonRow(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
    ) {
        CommentNotification.entries.forEachIndexed { index, entry ->
            SegmentedButton(
                selected = selection == entry,
                onClick = { onSelect(entry) },
                shape = SegmentedButtonDefaults.itemShape(index, CommentNotification.entries.size),
            ) {
                Text(
                    stringResource(
                        when (entry) {
                            CommentNotification.ALL -> R.string.all
                            CommentNotification.PARTIAL -> R.string.only_mine
                            CommentNotification.NONE -> R.string.none
                        },
                    ),
                )
            }
        }
    }
}
