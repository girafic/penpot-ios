import SwiftUI
import Observation

/// Device-local user preferences (appearance, app language).
///
/// Kept separate from ``AppState`` and ``SessionStore`` on purpose: these are
/// *device* preferences that must survive logout, whereas `SessionStore.clear()`
/// wipes session state on sign-out. Persisted in `UserDefaults` under its own
/// key namespace and injected via `.environment`, mirroring `AppState`.
///
/// Theme is authoritative **locally**: it drives `.preferredColorScheme` instantly
/// and offline. It is deliberately *not* synced to the Penpot account, because
/// `update-profile` rewrites `fullname`/`lang`/`theme` as a set and the API never
/// returns the current `lang` to preserve — so a theme write would risk nulling the
/// account language. See the plan's degradation notes.
@Observable
final class AppSettings {
    var theme: PenpotTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// The app's own UI language as an iOS/BCP-47 code (e.g. `de`, `pt-BR`), or
    /// `nil` to follow the system. Applied immediately via a `Bundle` override (no relaunch);
    /// the root view is rebuilt on change so `Text` re-resolves in the new language.
    var appLanguage: String? {
        didSet {
            defaults.set(appLanguage, forKey: Keys.appLanguage)
            Bundle.setAppLanguage(appLanguage)
        }
    }

    /// The Penpot **account** language code (underscored, e.g. `pt_br`) the user last set
    /// through this app, or `nil` if never set here. Penpot's API never returns the current
    /// `lang`, so we remember our own writes in order to resend it and avoid nulling it on a
    /// later `update-profile` (which rewrites the whole `fullname`/`lang`/`theme` set).
    var accountLanguage: String? {
        didSet { defaults.set(accountLanguage, forKey: Keys.accountLanguage) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let theme = "settings.theme"
        static let appLanguage = "settings.appLanguage"
        static let accountLanguage = "settings.accountLanguage"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = PenpotTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        appLanguage = defaults.string(forKey: Keys.appLanguage)
        accountLanguage = defaults.string(forKey: Keys.accountLanguage)
        // didSet doesn't fire during init — install the chosen language bundle explicitly.
        Bundle.setAppLanguage(appLanguage)
    }

    /// The SwiftUI color scheme to force, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Locale matching `appLanguage`, for date/number formatting. Falls back to the system.
    var locale: Locale {
        appLanguage.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    /// A value that changes whenever the language does — apply as `.id(...)` on the root so
    /// the view tree rebuilds and every `Text` re-resolves against the new bundle.
    var languageIdentity: String { appLanguage ?? "system" }
}

/// App appearance. Raw values match Penpot's own `theme` strings (`system`/`light`/`dark`)
/// so the same value can be reused if account-side theme sync ever becomes viable.
enum PenpotTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}
