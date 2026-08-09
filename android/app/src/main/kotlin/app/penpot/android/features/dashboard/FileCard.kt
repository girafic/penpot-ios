package app.penpot.android.features.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.app.AppSettings
import app.penpot.android.app.FilesLayout
import app.penpot.android.common.AppIcons
import app.penpot.android.common.DateFormatting
import app.penpot.android.common.RemoteImage
import app.penpot.android.common.assetUrl
import app.penpot.android.ui.theme.PenpotMint
import app.penpot.core.model.FileListItem

/**
 * Loads the file's preview thumbnail: one `get-file-object-thumbnails` call per card,
 * an arbitrary board's media id is "the file's thumbnail" (same as iOS).
 */
@Composable
fun FileThumbnail(
    graph: AppGraph,
    file: FileListItem,
    modifier: Modifier = Modifier,
    badgeSize: Dp = 28.dp,
) {
    val client = graph.appState.client
    val mediaId by produceState<String?>(initialValue = null, key1 = file.id) {
        value = runCatching { client?.objectThumbnails(file.id)?.values?.firstOrNull() }.getOrNull()
    }
    val shape = RoundedCornerShape(10.dp)
    Box(
        modifier = modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, shape),
    ) {
        val url = mediaId?.let { id -> client?.let { assetUrl(it.baseUrl, id) } }
        RemoteImage(
            url = url,
            contentDescription = file.name,
            modifier = Modifier.fillMaxWidth().padding(6.dp),
        )
        if (file.isShared == true) {
            SharedLibraryBadge(
                size = badgeSize,
                modifier = Modifier.align(Alignment.TopEnd).padding(6.dp),
            )
        }
    }
}

/** Black library glyph on Penpot mint — the shared-library marker. */
@Composable
fun SharedLibraryBadge(size: Dp, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(size)
            .background(PenpotMint, RoundedCornerShape(size * 0.22f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = AppIcons.library,
            contentDescription = stringResource(R.string.shared_library),
            tint = Color.Black,
            modifier = Modifier.size(size * 0.5f),
        )
    }
}

/** Toolbar button showing the icon of the layout it switches *to*. */
@Composable
fun FilesLayoutToggle(settings: AppSettings) {
    IconButton(onClick = { settings.setFilesLayout(settings.filesLayout.toggled) }) {
        Icon(
            imageVector = if (settings.filesLayout == FilesLayout.GRID) AppIcons.listLayout else AppIcons.gridLayout,
            contentDescription = stringResource(
                if (settings.filesLayout == FilesLayout.GRID) R.string.view_as_list else R.string.view_as_grid,
            ),
        )
    }
}

/** Grid cell: thumbnail, name, relative modified date. */
@Composable
fun FileCardView(graph: AppGraph, file: FileListItem, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        FileThumbnail(graph, file, modifier = Modifier.fillMaxWidth().height(110.dp))
        Text(
            text = file.name,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 8.dp),
        )
        val modified = DateFormatting.relative(file.modifiedAt)
        if (!modified.isNullOrEmpty()) {
            Text(
                text = modified,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** List row: small thumbnail + the same two-line text. */
@Composable
fun FileRowView(graph: AppGraph, file: FileListItem, modifier: Modifier = Modifier) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        FileThumbnail(
            graph,
            file,
            modifier = Modifier.size(width = 72.dp, height = 54.dp),
            badgeSize = 18.dp,
        )
        Column(modifier = Modifier.weight(1f).padding(start = 12.dp)) {
            Text(
                text = file.name,
                style = MaterialTheme.typography.bodySmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val modified = DateFormatting.relative(file.modifiedAt)
            if (!modified.isNullOrEmpty()) {
                Text(
                    text = modified,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
