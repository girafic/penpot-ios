package app.penpot.android.common

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.penpot.android.ui.theme.WorkSans
import androidx.compose.ui.unit.sp
import okhttp3.HttpUrl

/**
 * Circular avatar with the Penpot fallback chain: photo → initials on a dark circle →
 * an optional fallback icon. Initials follow Penpot's convention: first letter of the
 * first + last word ("Ada Lovelace" → "AL"), a single letter for one word or an email.
 */
@Composable
fun PenpotAvatar(
    photoId: String?,
    name: String?,
    baseUrl: HttpUrl?,
    size: Dp = 44.dp,
    fallbackIcon: ImageVector? = null,
    modifier: Modifier = Modifier,
) {
    val shapeModifier = modifier
        .size(size)
        .clip(CircleShape)
    val url = if (photoId != null && baseUrl != null) assetUrl(baseUrl, photoId) else null
    when {
        url != null -> RemoteImage(
            url = url,
            contentDescription = name,
            modifier = shapeModifier,
            contentScale = ContentScale.Crop,
            placeholder = { InitialsOrIcon(name, size, fallbackIcon) },
        )
        else -> Box(shapeModifier) { InitialsOrIcon(name, size, fallbackIcon) }
    }
}

@Composable
private fun InitialsOrIcon(name: String?, size: Dp, fallbackIcon: ImageVector?) {
    val initials = initials(name)
    if (initials != null) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF1A1A1A), CircleShape)
                .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            val fraction = if (initials.length >= 2) 0.38f else 0.45f
            Text(
                text = initials,
                color = Color.White,
                fontFamily = WorkSans,
                fontWeight = FontWeight.SemiBold,
                fontSize = (size.value * fraction).sp,
            )
        }
    } else {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = fallbackIcon ?: AppIcons.user,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(size * 0.45f),
            )
        }
    }
}

/** "Ada Lovelace" → "AL"; "ada@example.com" → "A"; blank → null. */
internal fun initials(name: String?): String? {
    val trimmed = name?.trim().orEmpty()
    if (trimmed.isEmpty()) return null
    val words = trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }
    return when {
        words.size >= 2 -> "${words.first().first().uppercaseChar()}${words.last().first().uppercaseChar()}"
        else -> words.first().first().uppercaseChar().toString()
    }
}
