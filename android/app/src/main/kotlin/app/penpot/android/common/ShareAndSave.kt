package app.penpot.android.common

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.penpot.android.R

/** `.penpot` archives are opaque binary bundles. */
const val PENPOT_MIME_TYPE = "application/octet-stream"

/** "My File/v2" → "My File-v2.penpot" (same sanitization as the iOS ExportedDocument). */
fun penpotExportFilename(name: String): String {
    val sanitized = name.map { c -> if (c in "/\\:") '-' else c }.joinToString("")
    return "$sanitized.penpot"
}

/**
 * Save-file flow for exported `.penpot` archives via the system document picker
 * (ACTION_CREATE_DOCUMENT — Android's counterpart of the iOS share sheet for files).
 * Call [ExportController.save] with the bytes and the suggested file name.
 */
class ExportController internal constructor(
    private val launch: (String) -> Unit,
) {
    internal var pendingBytes: ByteArray? = null

    fun save(bytes: ByteArray, suggestedName: String) {
        pendingBytes = bytes
        launch(suggestedName)
    }
}

@Composable
fun rememberExportController(context: Context, onError: (Exception) -> Unit): ExportController {
    val holder = remember { arrayOfNulls<ExportController>(1) }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument(PENPOT_MIME_TYPE),
    ) { uri: Uri? ->
        val controller = holder[0]
        val bytes = controller?.pendingBytes
        controller?.pendingBytes = null
        if (uri != null && bytes != null) {
            try {
                context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
            } catch (e: Exception) {
                onError(e)
            }
        }
    }
    return remember {
        ExportController { name -> launcher.launch(name) }.also { holder[0] = it }
    }
}

/** Blocking overlay while `export-binfile` runs — the iOS "Preparing download…" treatment. */
@Composable
fun ExportingOverlay(visible: Boolean) {
    if (!visible) return
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.25f)),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            shape = MaterialTheme.shapes.medium,
            tonalElevation = 4.dp,
        ) {
            Box(modifier = Modifier.padding(24.dp), contentAlignment = Alignment.Center) {
                androidx.compose.foundation.layout.Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    CircularProgressIndicator()
                    Text(
                        text = stringResource(R.string.preparing_download),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(top = 12.dp),
                    )
                }
            }
        }
    }
}
