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
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.AppIcons
import app.penpot.android.common.PenpotAvatar
import app.penpot.android.common.PenpotScreen
import app.penpot.android.features.dashboard.SectionLabel
import app.penpot.android.nav.AboutRoute
import app.penpot.android.nav.AccessTokensRoute
import app.penpot.android.nav.AppearanceRoute
import app.penpot.android.nav.NotificationSettingsRoute
import app.penpot.android.nav.PasswordSettingsRoute
import app.penpot.android.nav.ProfileSettingsRoute

@Composable
fun SettingsScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    val appState = graph.appState
    val profile = appState.profile

    PenpotScreen(title = stringResource(R.string.settings), nav = nav) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
            ) {
                PenpotAvatar(
                    photoId = profile?.photoId,
                    name = profile?.displayName ?: graph.sessions.email,
                    baseUrl = appState.client?.baseUrl,
                    size = 60.dp,
                )
                Column(modifier = Modifier.padding(start = 16.dp)) {
                    Text(
                        text = profile?.displayName ?: stringResource(R.string.unknown),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    val email = profile?.email ?: graph.sessions.email
                    if (!email.isNullOrEmpty()) {
                        Text(
                            text = email,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            SectionLabel(stringResource(R.string.account))
            SettingsRow(AppIcons.user, stringResource(R.string.profile)) { nav.navigate(ProfileSettingsRoute) }
            SettingsRow(AppIcons.lock, stringResource(R.string.password)) { nav.navigate(PasswordSettingsRoute) }
            SettingsRow(AppIcons.notifications, stringResource(R.string.notifications)) {
                nav.navigate(NotificationSettingsRoute)
            }
            SettingsRow(AppIcons.key, stringResource(R.string.access_tokens)) { nav.navigate(AccessTokensRoute) }

            SectionLabel(stringResource(R.string.app))
            SettingsRow(AppIcons.appearance, stringResource(R.string.appearance)) { nav.navigate(AppearanceRoute) }
            SettingsRow(AppIcons.info, stringResource(R.string.about)) { nav.navigate(AboutRoute) }

            HorizontalDivider(Modifier.padding(vertical = 8.dp))

            // Opens the plan/billing page in the browser (no in-app purchase surface).
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        val base = appState.client?.baseUrl?.toString()?.trimEnd('/')
                        val url = if (base != null) "$base/#/settings/subscriptions" else "https://penpot.app/pricing"
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                    }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
            ) {
                Icon(AppIcons.subscription, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
                Text(
                    text = stringResource(R.string.subscription),
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.weight(1f).padding(start = 12.dp),
                )
                Icon(
                    AppIcons.externalLink,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                text = stringResource(R.string.manage_your_penpot_plan_and_billing_in_your_browser),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )

            HorizontalDivider(Modifier.padding(vertical = 8.dp))

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { appState.logout() }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
            ) {
                Icon(AppIcons.logout, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Text(
                    text = stringResource(R.string.log_out),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(start = 12.dp),
                )
            }
        }
    }
}

@Composable
internal fun SettingsRow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f).padding(start = 12.dp),
        )
        app.penpot.android.features.dashboard.ChevronForward()
    }
}
