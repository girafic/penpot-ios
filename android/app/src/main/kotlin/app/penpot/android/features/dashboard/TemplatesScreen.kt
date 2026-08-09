package app.penpot.android.features.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.AppIcons
import app.penpot.android.common.EmptyState
import app.penpot.android.common.ErrorState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.RemoteImage
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.nav.TemplatesRoute
import app.penpot.core.model.BuiltinTemplate
import app.penpot.core.network.builtinTemplates
import app.penpot.core.network.cloneTemplate
import kotlinx.coroutines.launch

@Composable
fun TemplatesScreen(graph: AppGraph, nav: NavController, route: TemplatesRoute) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var templates by remember { mutableStateOf<List<BuiltinTemplate>?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var pickerTarget by remember { mutableStateOf<BuiltinTemplate?>(null) }
    var importedName by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            templates = client.builtinTemplates()
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            loadError = e.userMessage(context)
        } finally {
            isLoading = false
        }
    }

    LaunchedEffect(Unit) { load() }

    PenpotScreen(title = stringResource(R.string.templates), nav = nav) { padding ->
        val current = templates
        when {
            current == null && isLoading ->
                LoadingState(stringResource(R.string.loading_templates), Modifier.padding(padding))
            current == null ->
                ErrorState(loadError ?: "", Modifier.padding(padding)) { scope.launch { load() } }
            else -> PullToRefreshBox(
                isRefreshing = isLoading,
                onRefresh = { scope.launch { load() } },
                modifier = Modifier.padding(padding).fillMaxSize(),
            ) {
                if (current.isEmpty()) {
                    EmptyState(
                        title = stringResource(R.string.no_templates),
                        icon = AppIcons.template,
                        description = stringResource(R.string.this_server_offers_no_built_in_templates),
                    )
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = 150.dp),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(count = current.size, key = { current[it].id }) { index ->
                            val template = current[index]
                            TemplateCard(graph, template) { pickerTarget = template }
                        }
                    }
                }
            }
        }
    }

    pickerTarget?.let { template ->
        MoveSheet(
            title = stringResource(R.string.add_to_project),
            failureTitle = stringResource(R.string.couldn_t_add_template),
            load = {
                client.projects(route.teamId)
                    .filter { it.deletedAt == null }
                    .map { project ->
                        MoveTarget(
                            id = project.id,
                            name = if (project.isDefaultProject) context.getString(R.string.drafts) else project.name,
                        )
                    }
            },
            onDismiss = { pickerTarget = null },
            onSelect = { target ->
                client.cloneTemplate(template.id, target.id)
                importedName = template.name
            },
        )
    }

    importedName?.let { name ->
        AlertDialog(
            onDismissRequest = { importedName = null },
            title = { Text(stringResource(R.string.template_added)) },
            text = { Text(stringResource(R.string.s_was_imported_open_the_project_to_view_it, name)) },
            confirmButton = {
                TextButton(onClick = { importedName = null }) { Text(stringResource(R.string.ok)) }
            },
        )
    }
}

@Composable
private fun TemplateCard(graph: AppGraph, template: BuiltinTemplate, onClick: () -> Unit) {
    val baseUrl = graph.appState.client?.baseUrl
    val shape = RoundedCornerShape(10.dp)
    Column(modifier = Modifier.clickable(onClick = onClick)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(110.dp)
                .clip(shape)
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, shape),
        ) {
            // Preview URL is derived from the id; some templates (e.g. "welcome") 404 —
            // RemoteImage silently falls back to the placeholder.
            RemoteImage(
                url = baseUrl?.let { template.thumbnailUrl(it).toString() },
                contentDescription = template.name,
                modifier = Modifier.fillMaxSize().padding(6.dp),
            )
        }
        Text(
            text = template.name,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 2,
            minLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}
