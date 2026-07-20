import Foundation

// MARK: - Notifications

/// Comment-notification frequency (`get-profile` → `props.notifications.*`).
enum CommentNotification: String, CaseIterable, Codable, Identifiable {
    case all
    case partial
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: .appLocalized("All")
        case .partial: .appLocalized("Only mine")
        case .none: .appLocalized("None")
        }
    }
}

/// Invite-notification frequency. Unlike comments, Penpot offers no "partial".
enum InviteNotification: String, CaseIterable, Codable, Identifiable {
    case all
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: .appLocalized("All")
        case .none: .appLocalized("None")
        }
    }
}

/// The three notification preferences.
///
/// Reads decode from `props.notifications`, whose keys arrive **camelCase**
/// (`dashboardComments`) via Penpot's response encoder — matching these property names, so
/// no `CodingKeys` are needed. Writes go through `update-profile-notifications`, whose
/// params are **kebab-case** (`dashboard-comments`) and are emitted explicitly in
/// ``PenpotClient/updateNotifications(_:)``. Missing keys default to Penpot's default (`all`)
/// rather than throwing.
struct NotificationSettings: Codable, Equatable {
    var dashboardComments: CommentNotification
    var emailComments: CommentNotification
    var emailInvites: InviteNotification

    init(dashboardComments: CommentNotification = .all,
         emailComments: CommentNotification = .all,
         emailInvites: InviteNotification = .all) {
        self.dashboardComments = dashboardComments
        self.emailComments = emailComments
        self.emailInvites = emailInvites
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dashboardComments = try c.decodeIfPresent(CommentNotification.self, forKey: .dashboardComments) ?? .all
        emailComments = try c.decodeIfPresent(CommentNotification.self, forKey: .emailComments) ?? .all
        emailInvites = try c.decodeIfPresent(InviteNotification.self, forKey: .emailInvites) ?? .all
    }
}

/// The Penpot profile "props" bag (a free-form JSONB map). We model only the keys we use;
/// unmodelled keys are ignored. Keys arrive camelCase, matching these property names.
struct ProfileProps: Decodable, Equatable {
    let notifications: NotificationSettings?
    let newsletterUpdates: Bool?
    let newsletterNews: Bool?
}

// MARK: - Access tokens

/// A personal access token (Integrations tab). The full `token` secret is present **only**
/// in the `create-access-token` response — the list never re-exposes it.
struct AccessToken: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let createdAt: String?
    let expiresAt: String?
    let token: String?
}

/// Expiration choices offered by Penpot's web UI for a new token.
enum TokenExpiration: String, CaseIterable, Identifiable {
    case never
    case days30 = "720h"
    case days60 = "1440h"
    case days90 = "2160h"
    case days180 = "4320h"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: .appLocalized("Never")
        case .days30: .appLocalized("30 days")
        case .days60: .appLocalized("60 days")
        case .days90: .appLocalized("90 days")
        case .days180: .appLocalized("180 days")
        }
    }
}

// MARK: - Languages

/// A Penpot-supported language, mapping Penpot's account `lang` code (underscored, e.g.
/// `pt_br`) to the iOS/BCP-47 code (`pt-BR`) used for the app's own localization.
struct PenpotLanguage: Identifiable, Hashable {
    /// Penpot account `lang` value (underscored). Empty string means "auto-detect".
    let penpotCode: String
    /// iOS/BCP-47 code for `AppleLanguages` and the String Catalog.
    let iosCode: String
    let nativeName: String
    /// Whether the iOS app ships a translation for this language.
    let appLocalized: Bool

    var id: String { penpotCode }

    /// All 34 languages Penpot's account picker supports.
    static let all: [PenpotLanguage] = [
        .init(penpotCode: "en", iosCode: "en", nativeName: "English", appLocalized: true),
        .init(penpotCode: "es", iosCode: "es", nativeName: "Español", appLocalized: true),
        .init(penpotCode: "de", iosCode: "de", nativeName: "Deutsch", appLocalized: true),
        .init(penpotCode: "fr", iosCode: "fr", nativeName: "Français", appLocalized: true),
        .init(penpotCode: "pt_br", iosCode: "pt-BR", nativeName: "Português (Brasil)", appLocalized: true),
        .init(penpotCode: "ru", iosCode: "ru", nativeName: "Русский", appLocalized: true),
        .init(penpotCode: "ca", iosCode: "ca", nativeName: "Català", appLocalized: false),
        .init(penpotCode: "nl", iosCode: "nl", nativeName: "Nederlands", appLocalized: false),
        .init(penpotCode: "eu", iosCode: "eu", nativeName: "Euskara", appLocalized: false),
        .init(penpotCode: "fr_ca", iosCode: "fr-CA", nativeName: "Français (Canada)", appLocalized: false),
        .init(penpotCode: "gl", iosCode: "gl", nativeName: "Galego", appLocalized: false),
        .init(penpotCode: "ha", iosCode: "ha", nativeName: "Hausa", appLocalized: false),
        .init(penpotCode: "hr", iosCode: "hr", nativeName: "Hrvatski", appLocalized: false),
        .init(penpotCode: "it", iosCode: "it", nativeName: "Italiano", appLocalized: false),
        .init(penpotCode: "nb_no", iosCode: "nb-NO", nativeName: "Norsk Bokmål", appLocalized: false),
        .init(penpotCode: "pl", iosCode: "pl", nativeName: "Polski", appLocalized: false),
        .init(penpotCode: "pt_pt", iosCode: "pt-PT", nativeName: "Português (Portugal)", appLocalized: false),
        .init(penpotCode: "id", iosCode: "id", nativeName: "Bahasa Indonesia", appLocalized: false),
        .init(penpotCode: "ro", iosCode: "ro", nativeName: "Română", appLocalized: false),
        .init(penpotCode: "tr", iosCode: "tr", nativeName: "Türkçe", appLocalized: false),
        .init(penpotCode: "el", iosCode: "el", nativeName: "Ελληνικά", appLocalized: false),
        .init(penpotCode: "uk", iosCode: "uk", nativeName: "Українська", appLocalized: false),
        .init(penpotCode: "cs", iosCode: "cs", nativeName: "Čeština", appLocalized: false),
        .init(penpotCode: "lv", iosCode: "lv", nativeName: "Latviešu", appLocalized: false),
        .init(penpotCode: "sr", iosCode: "sr", nativeName: "Српски", appLocalized: false),
        .init(penpotCode: "fo", iosCode: "fo", nativeName: "Føroyskt", appLocalized: false),
        .init(penpotCode: "ko", iosCode: "ko", nativeName: "한국어", appLocalized: false),
        .init(penpotCode: "he", iosCode: "he", nativeName: "עברית", appLocalized: false),
        .init(penpotCode: "hi", iosCode: "hi", nativeName: "हिन्दी", appLocalized: false),
        .init(penpotCode: "ar", iosCode: "ar", nativeName: "العربية", appLocalized: false),
        .init(penpotCode: "fa", iosCode: "fa", nativeName: "فارسی", appLocalized: false),
        .init(penpotCode: "ja_jp", iosCode: "ja-JP", nativeName: "日本語", appLocalized: false),
        .init(penpotCode: "zh_cn", iosCode: "zh-Hans", nativeName: "简体中文", appLocalized: false),
        .init(penpotCode: "zh_hant", iosCode: "zh-Hant", nativeName: "繁體中文", appLocalized: false),
    ]

    /// The languages the iOS app itself is translated into (offered by the app-language picker).
    static let appLocalizedLanguages: [PenpotLanguage] = all.filter(\.appLocalized)
}
