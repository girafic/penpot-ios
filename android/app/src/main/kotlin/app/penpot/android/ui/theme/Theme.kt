package app.penpot.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** Extra brand colors that have no Material3 slot. */
data class PenpotColors(
    val accent: Color,
    val onAccent: Color,
    val iconGray: Color,
    val mint: Color,
    val isDark: Boolean,
)

val LocalPenpotColors = staticCompositionLocalOf {
    PenpotColors(
        accent = PenpotAccentLight,
        onAccent = PenpotOnAccentLight,
        iconGray = PenpotIconGrayLight,
        mint = PenpotMint,
        isDark = false,
    )
}

private val LightColors = lightColorScheme(
    primary = PenpotAccentLight,
    onPrimary = PenpotOnAccentLight,
    secondary = PenpotIconGrayLight,
    tertiary = PenpotAccentLight,
)

private val DarkColors = darkColorScheme(
    primary = PenpotAccentDark,
    onPrimary = PenpotOnAccentDark,
    secondary = PenpotIconGrayDark,
    tertiary = PenpotAccentDark,
)

/**
 * App theme. [darkTheme] is resolved by the caller from AppSettings.theme
 * (system / light / dark) — the theme is local-only and never synced to the
 * Penpot account (see the update-profile set-write hazard).
 */
@Composable
fun PenpotTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val penpotColors = PenpotColors(
        accent = if (darkTheme) PenpotAccentDark else PenpotAccentLight,
        onAccent = if (darkTheme) PenpotOnAccentDark else PenpotOnAccentLight,
        iconGray = if (darkTheme) PenpotIconGrayDark else PenpotIconGrayLight,
        mint = PenpotMint,
        isDark = darkTheme,
    )
    CompositionLocalProvider(LocalPenpotColors provides penpotColors) {
        MaterialTheme(
            colorScheme = if (darkTheme) DarkColors else LightColors,
            typography = PenpotTypography,
            content = content,
        )
    }
}
