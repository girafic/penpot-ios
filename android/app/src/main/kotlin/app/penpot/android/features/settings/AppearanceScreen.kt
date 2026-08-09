package app.penpot.android.features.settings

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.app.PenpotThemeSetting
import app.penpot.android.common.PenpotScreen
import app.penpot.android.features.auth.AppLanguagePicker
import app.penpot.android.features.dashboard.SectionLabel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppearanceScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    val settings = graph.settings

    PenpotScreen(title = stringResource(R.string.appearance), nav = nav) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp),
        ) {
            SectionLabel(stringResource(R.string.theme))
            SingleChoiceSegmentedButtonRow(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            ) {
                PenpotThemeSetting.entries.forEachIndexed { index, entry ->
                    SegmentedButton(
                        selected = settings.theme == entry,
                        onClick = { settings.setTheme(entry) },
                        shape = SegmentedButtonDefaults.itemShape(index, PenpotThemeSetting.entries.size),
                    ) {
                        Text(
                            stringResource(
                                when (entry) {
                                    PenpotThemeSetting.SYSTEM -> R.string.system
                                    PenpotThemeSetting.LIGHT -> R.string.light
                                    PenpotThemeSetting.DARK -> R.string.dark
                                },
                            ),
                        )
                    }
                }
            }
            Text(
                text = stringResource(R.string.choose_how_penpot_looks_on_this_device_system_follows_your_i),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            SectionLabel(stringResource(R.string.app_language))
            Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                AppLanguagePicker(
                    current = settings.appLanguage,
                    onSelect = { settings.setAppLanguage(it) },
                )
            }
            TextButton(
                onClick = {
                    runCatching {
                        context.startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", context.packageName, null),
                            ),
                        )
                    }
                },
                modifier = Modifier.padding(horizontal = 8.dp),
            ) {
                Text(stringResource(R.string.change_in_system_settings))
            }
            Text(
                text = stringResource(R.string.sets_this_app_s_language_applied_instantly_to_change_the_pen),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )

            SectionLabel(stringResource(R.string.canvas))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            ) {
                Text(
                    text = stringResource(R.string.webgl_rendering),
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.weight(1f),
                )
                Switch(
                    checked = settings.webGLRendering,
                    onCheckedChange = { settings.setWebGLRendering(it) },
                )
            }
            Text(
                text = stringResource(R.string.uses_penpot_s_new_render_engine_beta_for_the_canvas_view_it),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}
