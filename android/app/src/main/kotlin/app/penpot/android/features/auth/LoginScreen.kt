package app.penpot.android.features.auth

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.app.PenpotThemeSetting
import app.penpot.android.app.SessionStore
import app.penpot.android.common.userMessage
import app.penpot.core.model.PenpotLanguage
import kotlinx.coroutines.launch
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

private data class ServerPreset(val label: String, val url: String)

// Preset labels are developer shorthand and deliberately unlocalized (as on iOS).
private val presets = listOf(
    ServerPreset("Penpot Cloud", "https://design.penpot.app"),
    ServerPreset("Local :9001", "http://localhost:9001"),
    ServerPreset("Dev :3449", "https://localhost:3449"),
    ServerPreset("Dev :3450", "http://localhost:3450"),
)

/**
 * Same normalization as the iOS LoginView: trim, default to https://, strip trailing
 * slashes, require a host. Also drives preset-chip selection.
 */
internal fun normalizeServerUrl(raw: String): HttpUrl? {
    var text = raw.trim()
    if (text.isEmpty()) return null
    if (!text.lowercase().startsWith("http")) text = "https://$text"
    text = text.trimEnd('/')
    val url = text.toHttpUrlOrNull() ?: return null
    return if (url.host.isEmpty()) null else url
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(graph: AppGraph) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val settings = graph.settings

    var serverString by rememberSaveable {
        mutableStateOf(graph.sessions.serverUrl ?: SessionStore.DEFAULT_SERVER_URL)
    }
    var email by rememberSaveable { mutableStateOf(graph.sessions.email ?: "") }
    var password by rememberSaveable { mutableStateOf("") }
    var isSubmitting by rememberSaveable { mutableStateOf(false) }
    var errorMessage by rememberSaveable { mutableStateOf<String?>(null) }

    val normalizedServer = normalizeServerUrl(serverString)
    val canSubmit = email.isNotEmpty() && password.isNotEmpty() && normalizedServer != null && !isSubmitting

    fun submit() {
        val server = normalizeServerUrl(serverString)
        if (server == null) {
            errorMessage = context.getString(R.string.invalid_server_url)
            return
        }
        isSubmitting = true
        errorMessage = null
        scope.launch {
            try {
                graph.appState.login(server, email.trim(), password)
            } catch (e: Exception) {
                errorMessage = e.userMessage(context)
            } finally {
                isSubmitting = false
            }
        }
    }

    fun demoLogin() {
        val server = normalizeServerUrl(serverString) ?: return
        isSubmitting = true
        errorMessage = null
        scope.launch {
            try {
                graph.appState.loginWithDemoAccount(server)
            } catch (e: Exception) {
                errorMessage = e.userMessage(context)
            } finally {
                isSubmitting = false
            }
        }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Penpot", style = MaterialTheme.typography.headlineLarge) }) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // ── Server ──────────────────────────────────────────────────────
            SectionHeader(stringResource(R.string.penpot_server))
            OutlinedTextField(
                value = serverString,
                onValueChange = { serverString = it },
                placeholder = { Text(SessionStore.DEFAULT_SERVER_URL) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next),
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                for (preset in presets) {
                    val selected = normalizedServer != null &&
                        normalizeServerUrl(preset.url) == normalizedServer
                    FilterChip(
                        selected = selected,
                        onClick = { serverString = preset.url },
                        label = { Text(preset.label) },
                    )
                }
            }

            // ── Account ─────────────────────────────────────────────────────
            SectionHeader(stringResource(R.string.account))
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text(stringResource(R.string.email)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text(stringResource(R.string.password)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { if (canSubmit) submit() }),
                modifier = Modifier.fillMaxWidth(),
            )

            errorMessage?.let { message ->
                Text(
                    text = message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }

            Button(
                onClick = { submit() },
                enabled = canSubmit,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(modifier = Modifier.padding(4.dp))
                } else {
                    Text(stringResource(R.string.log_in))
                }
            }

            TextButton(
                onClick = { demoLogin() },
                enabled = normalizedServer != null && !isSubmitting,
                modifier = Modifier.align(Alignment.CenterHorizontally),
            ) {
                Text(stringResource(R.string.log_in_as_demo_user), style = MaterialTheme.typography.labelMedium)
            }

            // ── Appearance ──────────────────────────────────────────────────
            SectionHeader(stringResource(R.string.appearance))
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                PenpotThemeSetting.entries.forEachIndexed { index, entry ->
                    SegmentedButton(
                        selected = settings.theme == entry,
                        onClick = { settings.setTheme(entry) },
                        shape = SegmentedButtonDefaults.itemShape(index, PenpotThemeSetting.entries.size),
                    ) {
                        Text(
                            when (entry) {
                                PenpotThemeSetting.SYSTEM -> stringResource(R.string.system)
                                PenpotThemeSetting.LIGHT -> stringResource(R.string.light)
                                PenpotThemeSetting.DARK -> stringResource(R.string.dark)
                            },
                        )
                    }
                }
            }

            // ── Language ────────────────────────────────────────────────────
            SectionHeader(stringResource(R.string.language))
            AppLanguagePicker(
                current = settings.appLanguage,
                onSelect = { settings.setAppLanguage(it) },
            )
            androidx.compose.foundation.layout.Spacer(Modifier.padding(bottom = 24.dp))
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 16.dp),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppLanguagePicker(current: String?, onSelect: (String?) -> Unit) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val currentLabel = PenpotLanguage.appLocalizedLanguages.firstOrNull { it.tag == current }?.nativeName
        ?: stringResource(R.string.system)
    androidx.compose.material3.ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
    ) {
        OutlinedTextField(
            value = currentLabel,
            onValueChange = {},
            readOnly = true,
            singleLine = true,
            trailingIcon = { androidx.compose.material3.ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier
                .menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable)
                .fillMaxWidth(),
        )
        // Scope member of ExposedDropdownMenuBoxScope — must be called unqualified.
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            androidx.compose.material3.DropdownMenuItem(
                text = { Text(stringResource(R.string.system)) },
                onClick = {
                    expanded = false
                    onSelect(null)
                },
            )
            for (language in PenpotLanguage.appLocalizedLanguages) {
                androidx.compose.material3.DropdownMenuItem(
                    text = { Text(language.nativeName) },
                    onClick = {
                        expanded = false
                        onSelect(language.tag)
                    },
                )
            }
        }
    }
}
