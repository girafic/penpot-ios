package app.penpot.android.features.dashboard

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
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
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.nav.FontsRoute
import app.penpot.core.model.FontVariant
import app.penpot.core.network.deleteFont
import app.penpot.core.network.deleteFontVariant
import app.penpot.core.network.fontVariants
import kotlinx.coroutines.launch

private fun weightName(weight: Int?): String = when (weight) {
    100 -> "100 Thin"
    200 -> "200 Extra Light"
    300 -> "300 Light"
    400 -> "400 Regular"
    500 -> "500 Medium"
    600 -> "600 Semi Bold"
    700 -> "700 Bold"
    800 -> "800 Extra Bold"
    900 -> "900 Black"
    null -> "Regular"
    else -> weight.toString()
}

internal fun variantLabel(variant: FontVariant): String {
    val name = variant.variantName
    if (!name.isNullOrBlank()) return name
    val base = weightName(variant.fontWeight)
    return if (variant.fontStyle == "italic") "$base Italic" else base
}

private sealed interface FontDeletion {
    data class Variant(val variant: FontVariant) : FontDeletion
    data class Family(val variant: FontVariant) : FontDeletion
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FontsScreen(graph: AppGraph, nav: NavController, route: FontsRoute) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val client = appState.client ?: return

    var variants by remember { mutableStateOf<List<FontVariant>?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var deletion by remember { mutableStateOf<FontDeletion?>(null) }

    suspend fun load() {
        isLoading = true
        loadError = null
        try {
            variants = client.fontVariants(route.teamId)
        } catch (e: Exception) {
            handleAuthFailure(e, appState)
            loadError = e.userMessage(context)
        } finally {
            isLoading = false
        }
    }

    fun runAction(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
                load()
            } catch (e: Exception) {
                handleAuthFailure(e, appState)
                actionError = e.userMessage(context)
            }
        }
    }

    LaunchedEffect(Unit) { load() }

    PenpotScreen(title = stringResource(R.string.fonts), nav = nav) { padding ->
        val current = variants
        when {
            current == null && isLoading ->
                LoadingState(stringResource(R.string.loading_fonts), Modifier.padding(padding))
            current == null ->
                ErrorState(loadError ?: "", Modifier.padding(padding)) { scope.launch { load() } }
            else -> PullToRefreshBox(
                isRefreshing = isLoading,
                onRefresh = { scope.launch { load() } },
                modifier = Modifier.padding(padding).fillMaxSize(),
            ) {
                if (current.isEmpty()) {
                    EmptyState(
                        title = stringResource(R.string.no_fonts),
                        icon = AppIcons.text,
                        description = stringResource(
                            if (route.isDefaultTeam) R.string.fonts_you_upload_will_appear_here
                            else R.string.fonts_uploaded_to_this_team_will_appear_here,
                        ),
                    )
                } else {
                    val families = current
                        .groupBy { it.fontFamily }
                        .toSortedMap(String.CASE_INSENSITIVE_ORDER)
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        for ((family, familyVariants) in families) {
                            item(key = "family-$family") { SectionLabel(family) }
                            val sorted = familyVariants.sortedWith(
                                compareBy({ it.fontWeight ?: 400 }, { it.fontStyle ?: "" }),
                            )
                            items(count = sorted.size, key = { sorted[it].id }) { index ->
                                val variant = sorted[index]
                                VariantRow(
                                    variant = variant,
                                    onDeleteVariant = { deletion = FontDeletion.Variant(variant) },
                                    onDeleteFamily = if (variant.fontId != null) {
                                        { deletion = FontDeletion.Family(variant) }
                                    } else null,
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    when (val target = deletion) {
        is FontDeletion.Variant -> ConfirmDialog(
            title = stringResource(R.string.delete_variant),
            message = stringResource(R.string.s_will_be_removed, variantLabel(target.variant)),
            confirmLabel = stringResource(R.string.delete),
            onDismiss = { deletion = null },
            onConfirm = {
                deletion = null
                runAction { client.deleteFontVariant(route.teamId, target.variant.id) }
            },
        )
        is FontDeletion.Family -> ConfirmDialog(
            title = stringResource(R.string.delete_font_family),
            message = stringResource(R.string.s_and_all_its_variants_will_be_removed, target.variant.fontFamily),
            confirmLabel = stringResource(R.string.delete),
            onDismiss = { deletion = null },
            onConfirm = {
                deletion = null
                runAction { client.deleteFont(route.teamId, target.variant.fontId!!) }
            },
        )
        null -> Unit
    }

    ActionErrorDialog(actionError) { actionError = null }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun VariantRow(
    variant: FontVariant,
    onDeleteVariant: () -> Unit,
    onDeleteFamily: (() -> Unit)?,
) {
    var showMenu by remember { mutableStateOf(false) }
    Box {
        Text(
            text = variantLabel(variant),
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(onClick = {}, onLongClick = { showMenu = true })
                .padding(horizontal = 16.dp, vertical = 12.dp),
        )
        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.delete_variant), color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(AppIcons.delete, null, tint = MaterialTheme.colorScheme.error) },
                onClick = { showMenu = false; onDeleteVariant() },
            )
            if (onDeleteFamily != null) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.delete_font_family), color = MaterialTheme.colorScheme.error) },
                    leadingIcon = { Icon(AppIcons.delete, null, tint = MaterialTheme.colorScheme.error) },
                    onClick = { showMenu = false; onDeleteFamily() },
                )
            }
        }
    }
}
