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
    /// `nil` to follow the system. Applied immediately via a `Bundle` override (no relaunch).
    /// Changing it moves `locale`, and the root's `.environment(\.locale, …)` makes SwiftUI
    /// re-resolve every `Text` in place — without rebuilding the tree, so navigation is kept.
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

    /// Mirrors Penpot's "WebGL rendering (Beta)" account setting for the embedded canvas,
    /// passed as the `wasm` route override (which trumps profile and team flags). Off by
    /// default: the wasm/Skia engine can exhaust the texture memory iOS grants a WKWebView
    /// and abort on zoom, so the classic SVG renderer is the stable choice here.
    var webGLRendering: Bool {
        didSet { defaults.set(webGLRendering, forKey: Keys.webGLRendering) }
    }

    /// How file listings (project files, libraries) are laid out — grid of cards or rows.
    var filesLayout: FilesLayout {
        didSet { defaults.set(filesLayout.rawValue, forKey: Keys.filesLayout) }
    }

    /// Which comment threads boards show ("All / Only yours / Mentions").
    var commentFilterMode: CommentFilterMode {
        didSet { defaults.set(commentFilterMode.rawValue, forKey: Keys.commentFilterMode) }
    }

    /// Whether resolved comment threads render on boards. Defaults to off — web parity.
    var showResolvedComments: Bool {
        didSet { defaults.set(showResolvedComments, forKey: Keys.showResolvedComments) }
    }

    /// Whether the prototype player shows Penpot's previous / next / first-board buttons
    /// and the board counter. On by default, as in Penpot.
    var prototypeNavigation: Bool {
        didSet { defaults.set(prototypeNavigation, forKey: Keys.prototypeNavigation) }
    }

    /// The active thread filter as one value.
    var commentFilters: CommentFilters {
        CommentFilters(mode: commentFilterMode, showResolved: showResolvedComments)
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let theme = "settings.theme"
        static let appLanguage = "settings.appLanguage"
        static let accountLanguage = "settings.accountLanguage"
        static let webGLRendering = "settings.webGLRendering"
        static let filesLayout = "settings.filesLayout"
        static let commentFilterMode = "settings.commentFilterMode"
        static let showResolvedComments = "settings.showResolvedComments"
        static let prototypeNavigation = "settings.prototypeNavigation"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = PenpotTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        appLanguage = defaults.string(forKey: Keys.appLanguage)
        accountLanguage = defaults.string(forKey: Keys.accountLanguage)
        webGLRendering = defaults.bool(forKey: Keys.webGLRendering)
        filesLayout = FilesLayout(rawValue: defaults.string(forKey: Keys.filesLayout) ?? "") ?? .grid
        commentFilterMode = CommentFilterMode(rawValue: defaults.string(forKey: Keys.commentFilterMode) ?? "") ?? .all
        showResolvedComments = defaults.bool(forKey: Keys.showResolvedComments)
        prototypeNavigation = defaults.object(forKey: Keys.prototypeNavigation) as? Bool ?? true
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

    /// Locale matching `appLanguage`, for date/number formatting and driving SwiftUI's live
    /// `Text` re-resolution when the language changes. Falls back to the system.
    var locale: Locale {
        appLanguage.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    /// Writing direction of `locale`. The in-app language can differ from the system's, and
    /// SwiftUI derives its direction from the system, so Arabic, Hebrew and Persian need it
    /// set explicitly.
    var layoutDirection: LayoutDirection {
        Locale.Language(identifier: locale.identifier).characterDirection == .rightToLeft
            ? .rightToLeft : .leftToRight
    }
}

/// Layout for file listings.
enum FilesLayout: String {
    case grid
    case list

    /// The other layout — what a toggle button switches to.
    var toggled: FilesLayout { self == .grid ? .list : .grid }
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
