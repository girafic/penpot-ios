package app.penpot.android.app

import android.content.Context
import android.content.SharedPreferences
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import androidx.core.os.LocaleListCompat

/** Theme override; LIGHT/DARK pin the appearance, SYSTEM follows the device. */
enum class PenpotThemeSetting(val raw: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark");

    companion object {
        fun fromRaw(raw: String?): PenpotThemeSetting =
            entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}

/** Dashboard file-list layout. */
enum class FilesLayout(val raw: String) {
    GRID("grid"),
    LIST("list");

    val toggled: FilesLayout get() = if (this == GRID) LIST else GRID

    companion object {
        fun fromRaw(raw: String?): FilesLayout =
            entries.firstOrNull { it.raw == raw } ?: GRID
    }
}

/**
 * App-level preferences, observable from Compose. Deliberately separate from
 * [SessionStore] so preferences survive logout.
 *
 * [theme] is device-local and never synced to the Penpot account: `update-profile`
 * rewrites fullname+lang+theme as a set and the API never returns the current `lang`,
 * so a theme write would risk nulling the account language.
 */
class AppSettings(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("penpot.settings", Context.MODE_PRIVATE)

    var theme: PenpotThemeSetting by mutableStateOf(PenpotThemeSetting.fromRaw(prefs.getString(KEY_THEME, null)))
        private set

    /** BCP-47 tag of the app UI language, or null to follow the system. */
    var appLanguage: String? by mutableStateOf(prefs.getString(KEY_APP_LANGUAGE, null))
        private set

    /**
     * The Penpot account `lang` we last wrote (underscored code, e.g. `pt_br`).
     * The API never returns the current value, so this local memory is what keeps
     * profile saves from nulling the account language.
     */
    var accountLanguage: String? by mutableStateOf(prefs.getString(KEY_ACCOUNT_LANGUAGE, null))
        private set

    /** Maps to the `wasm=` canvas route param (Penpot's beta render engine). */
    var webGLRendering: Boolean by mutableStateOf(prefs.getBoolean(KEY_WEBGL, false))
        private set

    var filesLayout: FilesLayout by mutableStateOf(FilesLayout.fromRaw(prefs.getString(KEY_FILES_LAYOUT, null)))
        private set

    fun setTheme(value: PenpotThemeSetting) {
        theme = value
        prefs.edit { putString(KEY_THEME, value.raw) }
    }

    /** Applies the app language immediately via per-app locales (persisted by AppCompat). */
    fun setAppLanguage(tag: String?) {
        appLanguage = tag
        prefs.edit { putString(KEY_APP_LANGUAGE, tag) }
        AppCompatDelegate.setApplicationLocales(
            if (tag.isNullOrEmpty()) LocaleListCompat.getEmptyLocaleList()
            else LocaleListCompat.forLanguageTags(tag),
        )
    }

    fun setAccountLanguage(code: String?) {
        accountLanguage = code
        prefs.edit { putString(KEY_ACCOUNT_LANGUAGE, code) }
    }

    fun setWebGLRendering(enabled: Boolean) {
        webGLRendering = enabled
        prefs.edit { putBoolean(KEY_WEBGL, enabled) }
    }

    fun setFilesLayout(value: FilesLayout) {
        filesLayout = value
        prefs.edit { putString(KEY_FILES_LAYOUT, value.raw) }
    }

    companion object {
        private const val KEY_THEME = "settings.theme"
        private const val KEY_APP_LANGUAGE = "settings.appLanguage"
        private const val KEY_ACCOUNT_LANGUAGE = "settings.accountLanguage"
        private const val KEY_WEBGL = "settings.webGLRendering"
        private const val KEY_FILES_LAYOUT = "settings.filesLayout"
    }
}
