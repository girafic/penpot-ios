package app.penpot.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// ── Notifications ───────────────────────────────────────────────────────────

/** Comment-notification frequency (`props.notifications.*`). */
@Serializable
enum class CommentNotification(val raw: String) {
    @SerialName("all") ALL("all"),
    @SerialName("partial") PARTIAL("partial"),
    @SerialName("none") NONE("none"),
}

/** Invite-notification frequency. Unlike comments, Penpot offers no "partial". */
@Serializable
enum class InviteNotification(val raw: String) {
    @SerialName("all") ALL("all"),
    @SerialName("none") NONE("none"),
}

/**
 * The three notification preferences.
 *
 * Reads decode from `props.notifications`, whose keys arrive **camelCase**
 * (`dashboardComments`) via Penpot's response encoder — matching these property names.
 * Writes go through `update-profile-notifications`, whose params are **kebab-case**
 * (`dashboard-comments`) and are emitted explicitly in `PenpotClient.updateNotifications`.
 * Missing keys default to Penpot's default (`all`) rather than throwing.
 */
@Serializable
data class NotificationSettings(
    val dashboardComments: CommentNotification = CommentNotification.ALL,
    val emailComments: CommentNotification = CommentNotification.ALL,
    val emailInvites: InviteNotification = InviteNotification.ALL,
)

/**
 * The Penpot profile "props" bag (a free-form JSONB map). We model only the keys we use;
 * unmodelled keys are ignored. Keys arrive camelCase, matching these property names.
 */
@Serializable
data class ProfileProps(
    val notifications: NotificationSettings? = null,
    val newsletterUpdates: Boolean? = null,
    val newsletterNews: Boolean? = null,
)

// ── Access tokens ───────────────────────────────────────────────────────────

/**
 * A personal access token (Integrations tab). The full [token] secret is present **only**
 * in the `create-access-token` response — the list never re-exposes it.
 */
@Serializable
data class AccessToken(
    val id: String,
    val name: String,
    val createdAt: String? = null,
    val expiresAt: String? = null,
    val token: String? = null,
)

/**
 * Expiration choices offered by Penpot's web UI for a new token.
 * [param] is the raw value sent to `create-access-token`; NEVER is expressed by
 * omitting the param entirely.
 */
enum class TokenExpiration(val param: String?) {
    NEVER(null),
    DAYS_30("720h"),
    DAYS_60("1440h"),
    DAYS_90("2160h"),
    DAYS_180("4320h"),
}

// ── Languages ───────────────────────────────────────────────────────────────

/**
 * A Penpot-supported language, mapping Penpot's account `lang` code (underscored, e.g.
 * `pt_br`) to the BCP-47 tag (`pt-BR`) used for the app's own localization. The mapping
 * is not a plain underscore→hyphen swap — Chinese uses script subtags.
 */
data class PenpotLanguage(
    /** Penpot account `lang` value (underscored). Empty string means "auto-detect". */
    val penpotCode: String,
    /** BCP-47 tag for Android per-app locales and resource qualifiers. */
    val tag: String,
    val nativeName: String,
    /** Whether this app ships a translation for this language. */
    val appLocalized: Boolean,
) {
    companion object {
        /** All 34 languages Penpot's account picker supports. */
        val all: List<PenpotLanguage> = listOf(
            PenpotLanguage("en", "en", "English", true),
            PenpotLanguage("es", "es", "Español", true),
            PenpotLanguage("de", "de", "Deutsch", true),
            PenpotLanguage("fr", "fr", "Français", true),
            PenpotLanguage("pt_br", "pt-BR", "Português (Brasil)", true),
            PenpotLanguage("ru", "ru", "Русский", true),
            PenpotLanguage("ca", "ca", "Català", false),
            PenpotLanguage("nl", "nl", "Nederlands", false),
            PenpotLanguage("eu", "eu", "Euskara", false),
            PenpotLanguage("fr_ca", "fr-CA", "Français (Canada)", false),
            PenpotLanguage("gl", "gl", "Galego", false),
            PenpotLanguage("ha", "ha", "Hausa", false),
            PenpotLanguage("hr", "hr", "Hrvatski", false),
            PenpotLanguage("it", "it", "Italiano", false),
            PenpotLanguage("nb_no", "nb-NO", "Norsk Bokmål", false),
            PenpotLanguage("pl", "pl", "Polski", false),
            PenpotLanguage("pt_pt", "pt-PT", "Português (Portugal)", false),
            PenpotLanguage("id", "id", "Bahasa Indonesia", false),
            PenpotLanguage("ro", "ro", "Română", false),
            PenpotLanguage("tr", "tr", "Türkçe", false),
            PenpotLanguage("el", "el", "Ελληνικά", false),
            PenpotLanguage("uk", "uk", "Українська", false),
            PenpotLanguage("cs", "cs", "Čeština", false),
            PenpotLanguage("lv", "lv", "Latviešu", false),
            PenpotLanguage("sr", "sr", "Српски", false),
            PenpotLanguage("fo", "fo", "Føroyskt", false),
            PenpotLanguage("ko", "ko", "한국어", false),
            PenpotLanguage("he", "he", "עברית", false),
            PenpotLanguage("hi", "hi", "हिन्दी", false),
            PenpotLanguage("ar", "ar", "العربية", false),
            PenpotLanguage("fa", "fa", "فارسی", false),
            PenpotLanguage("ja_jp", "ja-JP", "日本語", false),
            PenpotLanguage("zh_cn", "zh-Hans", "简体中文", false),
            PenpotLanguage("zh_hant", "zh-Hant", "繁體中文", false),
        )

        /** The languages this app itself is translated into (offered by the app-language picker). */
        val appLocalizedLanguages: List<PenpotLanguage> = all.filter { it.appLocalized }
    }
}
