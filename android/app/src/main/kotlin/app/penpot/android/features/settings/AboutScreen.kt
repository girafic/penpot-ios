package app.penpot.android.features.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.AppIcons
import app.penpot.android.common.PenpotScreen
import app.penpot.android.features.dashboard.SectionLabel

@Composable
fun AboutScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    var cacheCleared by remember { mutableStateOf(false) }

    val packageInfo = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
    }
    val versionName = packageInfo?.versionName ?: "?"
    // PackageInfoCompat: longVersionCode itself needs API 28, minSdk is 26.
    val versionCode = packageInfo
        ?.let { androidx.core.content.pm.PackageInfoCompat.getLongVersionCode(it).toString() }
        ?: "?"

    fun open(url: String) {
        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    }

    PenpotScreen(title = stringResource(R.string.about), nav = nav) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp),
        ) {
            SectionLabel(stringResource(R.string.application))
            LabeledRow(stringResource(R.string.version), versionName)
            LabeledRow(stringResource(R.string.build), versionCode)

            SectionLabel("Penpot")
            LinkRow("penpot.app", AppIcons.externalLink) { open("https://penpot.app") }
            LinkRow(stringResource(R.string.help_documentation), AppIcons.help) {
                open("https://help.penpot.app")
            }
            LabeledRow(
                stringResource(R.string.connected_server),
                graph.appState.client?.baseUrl?.host ?: "—",
            )

            SectionLabel(stringResource(R.string.clear_image_cache))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        graph.clearImageCaches()
                        cacheCleared = true
                    }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
            ) {
                Icon(AppIcons.image, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
                Text(
                    text = stringResource(R.string.clear_image_cache),
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(start = 12.dp),
                )
            }
            Text(
                text = stringResource(
                    if (cacheCleared) R.string.cache_cleared
                    else R.string.removes_downloaded_thumbnails_and_avatars_from_this_device_t,
                ),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}

@Composable
private fun LabeledRow(label: String, value: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Text(text = label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun LinkRow(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.weight(1f),
        )
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
