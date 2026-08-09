package app.penpot.android.features.dashboard

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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.ActionErrorDialog
import app.penpot.android.common.AppIcons
import app.penpot.android.common.ConfirmDialog
import app.penpot.android.common.EmptyState
import app.penpot.android.common.ErrorState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotAvatar
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.TextFieldDialog
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.nav.CommentsInboxRoute
import app.penpot.android.nav.SettingsRoute
import app.penpot.android.nav.TeamDashboardRoute
import app.penpot.core.model.Team
import app.penpot.core.network.createTeam
import app.penpot.core.network.deleteTeam
import app.penpot.core.network.renameTeam
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun TeamsScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var teams by remember { mutableStateOf<List<Team>?>(null) }
    var unreadCount by remember { mutableStateOf(0) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }

    var showNewTeam by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var renameTarget by remember { mutableStateOf<Team?>(null) }
    var deleteTarget by remember { mutableStateOf<Team?>(null) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            val loaded = client.teams()
            teams = loaded
            loaded.firstOrNull()?.let { appState.resolveProfileIfNeeded(it.id) }
            // A failure here must not blank the team list.
            unreadCount = runCatching { client.unreadCommentThreads(loaded).size }.getOrDefault(unreadCount)
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            loadError = e.userMessage(context)
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(Unit) { load() }

    PenpotScreen(
        title = stringResource(R.string.dashboard),
        nav = null,
        actions = {
            IconButton(onClick = { showNewTeam = true }) {
                Icon(AppIcons.add, contentDescription = stringResource(R.string.new_team))
            }
            Box {
                IconButton(onClick = { showMenu = true }) {
                    Icon(AppIcons.more, contentDescription = stringResource(R.string.account_options))
                }
                DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.log_out), color = MaterialTheme.colorScheme.error) },
                        leadingIcon = {
                            Icon(AppIcons.logout, null, tint = MaterialTheme.colorScheme.error)
                        },
                        onClick = {
                            showMenu = false
                            appState.logout()
                        },
                    )
                }
            }
        },
    ) { padding ->
        val current = teams
        when {
            current == null && isLoading ->
                LoadingState(stringResource(R.string.loading_teams), Modifier.padding(padding))
            current == null && loadError != null ->
                ErrorState(loadError!!, Modifier.padding(padding)) { scope.launch { load() } }
            else -> PullToRefreshBox(
                isRefreshing = isLoading,
                onRefresh = { scope.launch { load() } },
                modifier = Modifier.padding(padding).fillMaxSize(),
            ) {
                if (current.isNullOrEmpty()) {
                    EmptyState(
                        title = stringResource(R.string.no_teams),
                        icon = AppIcons.teams,
                        description = "",
                    )
                } else {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        item(key = "profile") {
                            ProfileRow(graph) { nav.navigate(SettingsRoute) }
                            HorizontalDivider()
                        }
                        item(key = "comments") {
                            CommentsRow(unreadCount) { nav.navigate(CommentsInboxRoute) }
                            HorizontalDivider()
                        }
                        items(count = current.size, key = { current[it].id }) { index ->
                            val team = current[index]
                            TeamRow(
                                graph = graph,
                                team = team,
                                onOpen = {
                                    nav.navigate(
                                        TeamDashboardRoute(
                                            teamId = team.id,
                                            teamName = team.name,
                                            isDefaultTeam = team.isDefaultTeam,
                                        ),
                                    )
                                },
                                onRename = { renameTarget = team },
                                onDelete = { deleteTarget = team },
                            )
                        }
                    }
                }
            }
        }
    }

    if (showNewTeam) {
        TextFieldDialog(
            title = stringResource(R.string.new_team),
            message = stringResource(R.string.enter_a_name_for_the_new_team),
            placeholder = stringResource(R.string.team_name),
            confirmLabel = stringResource(R.string.create),
            onDismiss = { showNewTeam = false },
            onConfirm = { name ->
                showNewTeam = false
                scope.launch {
                    try {
                        client.createTeam(name)
                        load()
                    } catch (e: Exception) {
                        handleAuthFailure(e, appState)
                        actionError = e.userMessage(context)
                    }
                }
            },
        )
    }

    renameTarget?.let { team ->
        TextFieldDialog(
            title = stringResource(R.string.rename_team),
            message = null,
            placeholder = stringResource(R.string.team_name),
            confirmLabel = stringResource(R.string.rename),
            initialValue = team.name,
            onDismiss = { renameTarget = null },
            onConfirm = { name ->
                renameTarget = null
                scope.launch {
                    try {
                        client.renameTeam(team.id, name)
                        load()
                    } catch (e: Exception) {
                        handleAuthFailure(e, appState)
                        actionError = e.userMessage(context)
                    }
                }
            },
        )
    }

    deleteTarget?.let { team ->
        ConfirmDialog(
            title = stringResource(R.string.delete_team),
            message = stringResource(R.string.s_and_all_of_its_projects_and_files_will_be_deleted, team.name),
            confirmLabel = stringResource(R.string.delete),
            onDismiss = { deleteTarget = null },
            onConfirm = {
                deleteTarget = null
                scope.launch {
                    try {
                        client.deleteTeam(team.id)
                        load()
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
private fun ProfileRow(graph: AppGraph, onClick: () -> Unit) {
    val profile = graph.appState.profile
    val baseUrl = graph.appState.client?.baseUrl
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PenpotAvatar(
            photoId = profile?.photoId,
            name = profile?.displayName ?: graph.sessions.email,
            baseUrl = baseUrl,
            size = 44.dp,
        )
        Column(modifier = Modifier.weight(1f).padding(start = 12.dp)) {
            Text(
                text = profile?.displayName ?: stringResource(R.string.unknown),
                style = MaterialTheme.typography.titleMedium,
            )
            val email = profile?.email ?: graph.sessions.email
            if (!email.isNullOrEmpty()) {
                Text(
                    text = email,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        ChevronForward()
    }
}

@Composable
private fun CommentsRow(unreadCount: Int, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(AppIcons.comments, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
        Text(
            text = stringResource(R.string.comments),
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f).padding(start = 12.dp),
        )
        // Count before the chevron, matching the iOS "Comments … 1 >" layout.
        if (unreadCount > 0) {
            Text(
                text = unreadCount.toString(),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(end = 8.dp),
            )
        }
        ChevronForward()
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TeamRow(
    graph: AppGraph,
    team: Team,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClick = onOpen,
                    // Server rejects rename/delete for the default team — no menu there.
                    onLongClick = { if (!team.isDefaultTeam) showMenu = true },
                )
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PenpotAvatar(
                photoId = team.photoId,
                name = if (team.isDefaultTeam) null else team.name,
                baseUrl = graph.appState.client?.baseUrl,
                size = 28.dp,
                fallbackIcon = if (team.isDefaultTeam) AppIcons.board else null,
            )
            Text(
                text = if (team.isDefaultTeam) stringResource(R.string.your_penpot) else team.name,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f).padding(start = 12.dp),
            )
            ChevronForward()
        }
        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.rename)) },
                leadingIcon = { Icon(AppIcons.edit, null) },
                onClick = {
                    showMenu = false
                    onRename()
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(AppIcons.delete, null, tint = MaterialTheme.colorScheme.error) },
                onClick = {
                    showMenu = false
                    onDelete()
                },
            )
        }
    }
}

@Composable
internal fun ChevronForward() {
    Icon(
        imageVector = androidx.compose.material.icons.Icons.AutoMirrored.Filled.KeyboardArrowRight,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
        modifier = Modifier.size(20.dp),
    )
}
