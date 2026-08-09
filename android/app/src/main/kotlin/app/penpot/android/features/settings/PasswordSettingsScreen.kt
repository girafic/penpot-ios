package app.penpot.android.features.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.core.network.updatePassword
import kotlinx.coroutines.launch

private const val MIN_PASSWORD_LENGTH = 8

@Composable
fun PasswordSettingsScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var current by remember { mutableStateOf("") }
    var new by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var succeeded by remember { mutableStateOf(false) }

    val email = appState.profile?.email ?: graph.sessions.email

    // Client-side validation mirroring Penpot's frontend.
    val validationError: String? = when {
        new.isEmpty() -> null
        new.length < MIN_PASSWORD_LENGTH ->
            stringResource(R.string.use_at_least_d_characters, MIN_PASSWORD_LENGTH)
        email != null && new.equals(email, ignoreCase = true) ->
            stringResource(R.string.your_password_can_t_be_the_same_as_your_email)
        confirm.isNotEmpty() && confirm != new ->
            stringResource(R.string.the_passwords_don_t_match)
        else -> null
    }
    val canSubmit = current.isNotEmpty() && new.length >= MIN_PASSWORD_LENGTH &&
        confirm == new && validationError == null && !isSaving

    PenpotScreen(title = stringResource(R.string.password), nav = nav) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            OutlinedTextField(
                value = current,
                onValueChange = { current = it },
                label = { Text(stringResource(R.string.current_password)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = new,
                onValueChange = { new = it },
                label = { Text(stringResource(R.string.new_password)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            )
            OutlinedTextField(
                value = confirm,
                onValueChange = { confirm = it },
                label = { Text(stringResource(R.string.confirm_new_password)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            )
            Text(
                text = validationError
                    ?: stringResource(R.string.at_least_d_characters, MIN_PASSWORD_LENGTH),
                style = MaterialTheme.typography.labelMedium,
                color = if (validationError != null) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurfaceVariant,
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
                    isSaving = true
                    errorMessage = null
                    scope.launch {
                        try {
                            client.updatePassword(new = new, old = current)
                            succeeded = true
                        } catch (e: Exception) {
                            handleAuthFailure(e, appState)
                            errorMessage = e.userMessage(context)
                        } finally {
                            isSaving = false
                        }
                    }
                },
                enabled = canSubmit,
                modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
            ) {
                if (isSaving) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp))
                } else {
                    Text(stringResource(R.string.change_password))
                }
            }
        }
    }

    if (succeeded) {
        AlertDialog(
            onDismissRequest = {},
            title = { Text(stringResource(R.string.password_changed)) },
            text = { Text(stringResource(R.string.your_password_has_been_updated)) },
            confirmButton = {
                TextButton(onClick = {
                    succeeded = false
                    nav.popBackStack()
                }) { Text(stringResource(R.string.done)) }
            },
        )
    }
}
