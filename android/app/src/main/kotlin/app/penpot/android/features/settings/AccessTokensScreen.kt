package app.penpot.android.features.settings

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
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
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.core.model.AccessToken
import app.penpot.core.model.TokenExpiration
import app.penpot.core.network.accessTokens
import app.penpot.core.network.createAccessToken
import app.penpot.core.network.deleteAccessToken
import kotlinx.coroutines.launch

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AccessTokensScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var tokens by remember { mutableStateOf<List<AccessToken>?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var showCreate by remember { mutableStateOf(false) }
    var createdToken by remember { mutableStateOf<AccessToken?>(null) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            tokens = client.accessTokens()
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            loadError = e.userMessage(context)
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(Unit) { load() }

    PenpotScreen(
        title = stringResource(R.string.access_tokens),
        nav = nav,
        actions = {
            IconButton(onClick = { showCreate = true }) {
                Icon(AppIcons.add, contentDescription = stringResource(R.string.new_token))
            }
        },
    ) { padding ->
        val current = tokens
        when {
            current == null && isLoading ->
                LoadingState(stringResource(R.string.loading_tokens), Modifier.padding(padding))
            current == null ->
                ErrorState(loadError ?: "", Modifier.padding(padding)) { scope.launch { load() } }
            else -> PullToRefreshBox(
                isRefreshing = isLoading,
                onRefresh = { scope.launch { load() } },
                modifier = Modifier.padding(padding).fillMaxSize(),
            ) {
                if (current.isEmpty()) {
                    EmptyState(
                        title = stringResource(R.string.no_access_tokens),
                        icon = AppIcons.key,
                        description = stringResource(R.string.create_a_personal_access_token_to_use_the_penpot_api),
                    ) {
                        Button(onClick = { showCreate = true }) {
                            Text(stringResource(R.string.create_token))
                        }
                    }
                } else {
                    Column {
                        LazyColumn(modifier = Modifier.weight(1f)) {
                            items(count = current.size, key = { current[it].id }) { index ->
                                val token = current[index]
                                TokenRow(token) {
                                    scope.launch {
                                        try {
                                            client.deleteAccessToken(token.id)
                                            load()
                                        } catch (e: Exception) {
                                            handleAuthFailure(e, appState)
                                            actionError = e.userMessage(context)
                                        }
                                    }
                                }
                            }
                        }
                        Text(
                            text = stringResource(R.string.tokens_grant_full_api_access_to_your_account_delete_any_you),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                }
            }
        }
    }

    if (showCreate) {
        CreateTokenDialog(
            onDismiss = { showCreate = false },
            onCreate = { name, expiration ->
                scope.launch {
                    try {
                        val token = client.createAccessToken(name, expiration)
                        showCreate = false
                        createdToken = token
                        load()
                    } catch (e: Exception) {
                        handleAuthFailure(e, appState)
                        actionError = e.userMessage(context)
                    }
                }
            },
        )
    }

    createdToken?.let { token ->
        TokenSecretDialog(token) { createdToken = null }
    }

    ActionErrorDialog(actionError) { actionError = null }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TokenRow(token: AccessToken, onDelete: () -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    Box {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(onClick = {}, onLongClick = { menuOpen = true })
                .padding(horizontal = 16.dp, vertical = 10.dp),
        ) {
            Text(text = token.name, style = MaterialTheme.typography.bodyLarge)
            val expires = token.expiresAt
            Text(
                text = if (expires != null) {
                    stringResource(R.string.expires_s, DateFormatting.relative(expires) ?: expires)
                } else {
                    stringResource(R.string.never_expires)
                },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(AppIcons.delete, null, tint = MaterialTheme.colorScheme.error) },
                onClick = { menuOpen = false; onDelete() },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateTokenDialog(
    onDismiss: () -> Unit,
    onCreate: (String, TokenExpiration) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var expiration by remember { mutableStateOf(TokenExpiration.NEVER) }
    var isCreating by remember { mutableStateOf(false) }
    var expirationOpen by remember { mutableStateOf(false) }

    @Composable
    fun expirationLabel(value: TokenExpiration): String = when (value) {
        TokenExpiration.NEVER -> stringResource(R.string.never)
        TokenExpiration.DAYS_30 -> stringResource(R.string.n_30_days)
        TokenExpiration.DAYS_60 -> stringResource(R.string.n_60_days)
        TokenExpiration.DAYS_90 -> stringResource(R.string.n_90_days)
        TokenExpiration.DAYS_180 -> stringResource(R.string.n_180_days)
    }

    AlertDialog(
        onDismissRequest = { if (!isCreating) onDismiss() },
        title = { Text(stringResource(R.string.new_token)) },
        text = {
            Column {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(stringResource(R.string.name)) },
                    placeholder = { Text(stringResource(R.string.e_g_ci_pipeline)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                androidx.compose.material3.ExposedDropdownMenuBox(
                    expanded = expirationOpen,
                    onExpandedChange = { expirationOpen = it },
                    modifier = Modifier.padding(top = 8.dp),
                ) {
                    OutlinedTextField(
                        value = expirationLabel(expiration),
                        onValueChange = {},
                        readOnly = true,
                        singleLine = true,
                        label = { Text(stringResource(R.string.expiration)) },
                        trailingIcon = {
                            androidx.compose.material3.ExposedDropdownMenuDefaults.TrailingIcon(expirationOpen)
                        },
                        modifier = Modifier
                            .menuAnchor(androidx.compose.material3.MenuAnchorType.PrimaryNotEditable)
                            .fillMaxWidth(),
                    )
                    // Scope member of ExposedDropdownMenuBoxScope — must be called unqualified.
                    ExposedDropdownMenu(
                        expanded = expirationOpen,
                        onDismissRequest = { expirationOpen = false },
                    ) {
                        for (option in TokenExpiration.entries) {
                            DropdownMenuItem(
                                text = { Text(expirationLabel(option)) },
                                onClick = {
                                    expirationOpen = false
                                    expiration = option
                                },
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    isCreating = true
                    onCreate(name.trim(), expiration)
                },
                enabled = name.trim().isNotEmpty() && !isCreating,
            ) {
                if (isCreating) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp))
                } else {
                    Text(stringResource(R.string.create))
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isCreating) {
                Text(stringResource(R.string.cancel))
            }
        },
    )
}

/** Shows the freshly created secret — the only moment Penpot exposes it. */
@Composable
private fun TokenSecretDialog(token: AccessToken, onDismiss: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(token.name) },
        text = {
            Column {
                Text(
                    text = token.token.orEmpty(),
                    style = MaterialTheme.typography.labelMedium.copy(fontFamily = FontFamily.Monospace),
                )
                Text(
                    text = stringResource(R.string.copy_this_token_now_for_security_penpot_won_t_show_it_again),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
        },
        confirmButton = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = {
                    clipboard.setText(AnnotatedString(token.token.orEmpty()))
                    copied = true
                }) {
                    Icon(
                        if (copied) AppIcons.tick else AppIcons.copy,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                }
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) }
            }
        },
    )
}
