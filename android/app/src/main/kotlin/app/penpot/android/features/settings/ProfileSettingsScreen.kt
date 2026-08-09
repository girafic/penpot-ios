package app.penpot.android.features.settings

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.navigation.NavController
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.AppIcons
import app.penpot.android.common.PenpotAvatar
import app.penpot.android.common.PenpotScreen
import app.penpot.android.common.handleAuthFailure
import app.penpot.android.common.userMessage
import app.penpot.android.features.dashboard.SectionLabel
import app.penpot.android.nav.ChangeEmailRoute
import app.penpot.android.nav.DeleteAccountRoute
import app.penpot.core.model.PenpotLanguage
import app.penpot.core.network.deleteProfilePhoto
import app.penpot.core.network.updateProfile
import app.penpot.core.network.updateProfilePhoto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

private data class Banner(val text: String, val isError: Boolean)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileSettingsScreen(graph: AppGraph, nav: NavController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val appState = graph.appState
    val settings = graph.settings
    val client = appState.client ?: return
    val profile = appState.profile

    var name by rememberSaveable { mutableStateOf(profile?.fullname ?: "") }
    var accountLanguage by rememberSaveable { mutableStateOf(settings.accountLanguage ?: "") }
    var isSaving by remember { mutableStateOf(false) }
    var isUploading by remember { mutableStateOf(false) }
    var banner by remember { mutableStateOf<Banner?>(null) }

    val photoPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        isUploading = true
        scope.launch {
            try {
                val jpeg = withContext(Dispatchers.IO) {
                    val bitmap = context.contentResolver.openInputStream(uri)?.use {
                        BitmapFactory.decodeStream(it)
                    } ?: throw IllegalStateException(context.getString(R.string.couldn_t_read_that_image))
                    ByteArrayOutputStream().use { out ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                        out.toByteArray()
                    }
                }
                client.updateProfilePhoto(jpeg, "image/jpeg", "avatar.jpg")
                // The upload returns no body — re-resolve the new photoId from membership.
                appState.refreshProfile()
            } catch (e: Exception) {
                handleAuthFailure(e, appState)
                banner = Banner(e.userMessage(context), isError = true)
            } finally {
                isUploading = false
            }
        }
    }

    val nameChanged = name.trim() != (profile?.fullname ?: "")
    val languageChanged = accountLanguage != (settings.accountLanguage ?: "")
    val canSave = name.trim().isNotEmpty() && (nameChanged || languageChanged) && !isSaving

    fun save() {
        isSaving = true
        scope.launch {
            try {
                // Set-write: fullname + lang + theme always travel together — an omitted
                // field is nulled server-side, and lang is never readable back.
                val updated = client.updateProfile(
                    fullname = name.trim(),
                    lang = accountLanguage.ifEmpty { null },
                    theme = settings.theme.raw,
                )
                settings.setAccountLanguage(accountLanguage.ifEmpty { null })
                appState.updateProfileLocally(
                    (appState.profile ?: updated).copy(fullname = name.trim()),
                )
                banner = Banner(context.getString(R.string.your_profile_has_been_updated), isError = false)
            } catch (e: Exception) {
                handleAuthFailure(e, appState)
                banner = Banner(e.userMessage(context), isError = true)
            } finally {
                isSaving = false
            }
        }
    }

    PenpotScreen(title = stringResource(R.string.profile), nav = nav) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp),
        ) {
            // ── Avatar ──────────────────────────────────────────────────────
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
            ) {
                Box(
                    modifier = Modifier
                        .alpha(if (isUploading) 0.5f else 1f)
                        .clickable(enabled = !isUploading) {
                            photoPicker.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                            )
                        },
                ) {
                    PenpotAvatar(
                        photoId = profile?.photoId,
                        name = profile?.displayName ?: graph.sessions.email,
                        baseUrl = client.baseUrl,
                        size = 60.dp,
                    )
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(22.dp)
                            .background(MaterialTheme.colorScheme.primary, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            AppIcons.camera,
                            contentDescription = stringResource(R.string.change_photo),
                            tint = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.size(13.dp),
                        )
                    }
                    if (isUploading) {
                        CircularProgressIndicator(
                            modifier = Modifier.align(Alignment.Center).size(24.dp),
                        )
                    }
                }
                Column(modifier = Modifier.padding(start = 16.dp)) {
                    TextButton(onClick = {
                        photoPicker.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    }, enabled = !isUploading) {
                        Text(stringResource(R.string.change_photo))
                    }
                    if (profile?.photoId != null) {
                        TextButton(
                            onClick = {
                                isUploading = true
                                scope.launch {
                                    try {
                                        client.deleteProfilePhoto()
                                        appState.refreshProfile()
                                    } catch (e: Exception) {
                                        handleAuthFailure(e, appState)
                                        banner = Banner(e.userMessage(context), isError = true)
                                    } finally {
                                        isUploading = false
                                    }
                                }
                            },
                            enabled = !isUploading,
                        ) {
                            Text(
                                stringResource(R.string.reset_to_default),
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                }
            }
            Text(
                text = stringResource(R.string.a_new_photo_may_take_a_moment_to_appear_elsewhere_in_the_app),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )

            // ── Profile ─────────────────────────────────────────────────────
            SectionLabel(stringResource(R.string.profile))
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.display_name)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            )
            AccountLanguagePicker(
                current = accountLanguage,
                onSelect = { accountLanguage = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )
            Button(
                onClick = { save() },
                enabled = canSave,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            ) {
                if (isSaving) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp))
                } else {
                    Text(stringResource(R.string.save))
                }
            }
            Text(
                text = stringResource(R.string.account_language_changes_the_penpot_website_and_the_emails_p),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )

            // ── Email ───────────────────────────────────────────────────────
            SectionLabel(stringResource(R.string.email))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
            ) {
                Text(
                    text = stringResource(R.string.current),
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = profile?.email ?: graph.sessions.email ?: "",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            SettingsRow(AppIcons.edit, stringResource(R.string.change_email)) {
                nav.navigate(ChangeEmailRoute)
            }

            // ── Delete account ──────────────────────────────────────────────
            SectionLabel(stringResource(R.string.account))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { nav.navigate(DeleteAccountRoute) }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
            ) {
                Icon(AppIcons.warning, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Text(
                    text = stringResource(R.string.delete_account),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(start = 12.dp),
                )
            }
        }
    }

    banner?.let { current ->
        AlertDialog(
            onDismissRequest = { banner = null },
            title = {
                Text(stringResource(if (current.isError) R.string.error else R.string.saved))
            },
            text = { Text(current.text) },
            confirmButton = {
                TextButton(onClick = { banner = null }) { Text(stringResource(R.string.ok)) }
            },
        )
    }
}

/** Account-language dropdown: "Auto-detect" + all 34 Penpot languages (by penpotCode). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AccountLanguagePicker(
    current: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val currentLabel = PenpotLanguage.all.firstOrNull { it.penpotCode == current }?.nativeName
        ?: stringResource(R.string.auto_detect)
    androidx.compose.material3.ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier,
    ) {
        OutlinedTextField(
            value = currentLabel,
            onValueChange = {},
            readOnly = true,
            singleLine = true,
            label = { Text(stringResource(R.string.account_language)) },
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
                text = { Text(stringResource(R.string.auto_detect)) },
                onClick = {
                    expanded = false
                    onSelect("")
                },
            )
            for (language in PenpotLanguage.all) {
                androidx.compose.material3.DropdownMenuItem(
                    text = { Text(language.nativeName) },
                    onClick = {
                        expanded = false
                        onSelect(language.penpotCode)
                    },
                )
            }
        }
    }
}
