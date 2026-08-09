package app.penpot.android.features.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.core.network.requestEmailChange
import kotlinx.coroutines.launch

private sealed interface EmailChangeOutcome {
    data class ConfirmationSent(val email: String) : EmailChangeOutcome
    data class ChangedImmediately(val email: String) : EmailChangeOutcome
}

@Composable
fun ChangeEmailScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    val currentEmail = appState.profile?.email ?: graph.sessions.email ?: ""

    var email by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var outcome by remember { mutableStateOf<EmailChangeOutcome?>(null) }

    val isValid = email.contains("@") && email.contains(".") &&
        !email.equals(currentEmail, ignoreCase = true)

    PenpotScreen(title = stringResource(R.string.change_email), nav = nav) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text(stringResource(R.string.new_email)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = stringResource(R.string.penpot_will_email_a_confirmation_link_to_the_new_address_the),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp),
            )
            errorMessage?.let { message ->
                Text(
                    text = message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            Button(
                onClick = {
                    isSending = true
                    errorMessage = null
                    scope.launch {
                        try {
                            val changed = client.requestEmailChange(email.trim())
                            outcome = if (changed) {
                                EmailChangeOutcome.ChangedImmediately(email.trim())
                            } else {
                                EmailChangeOutcome.ConfirmationSent(email.trim())
                            }
                        } catch (e: Exception) {
                            handleAuthFailure(e, appState)
                            errorMessage = e.userMessage(context)
                        } finally {
                            isSending = false
                        }
                    }
                },
                enabled = isValid && !isSending,
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
            ) {
                if (isSending) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp))
                } else {
                    Text(stringResource(R.string.request_change))
                }
            }
        }
    }

    outcome?.let { result ->
        AlertDialog(
            onDismissRequest = {},
            title = {
                Text(
                    stringResource(
                        when (result) {
                            is EmailChangeOutcome.ConfirmationSent -> R.string.check_your_inbox
                            is EmailChangeOutcome.ChangedImmediately -> R.string.email_changed
                        },
                    ),
                )
            },
            text = {
                Text(
                    when (result) {
                        is EmailChangeOutcome.ConfirmationSent ->
                            stringResource(R.string.we_sent_a_confirmation_link_to_s_open_it_to_finish_changing, result.email)
                        is EmailChangeOutcome.ChangedImmediately ->
                            stringResource(R.string.your_email_is_now_s, result.email)
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    outcome = null
                    nav.popBackStack()
                }) { Text(stringResource(R.string.done)) }
            },
        )
    }
}
