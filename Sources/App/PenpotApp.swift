import SwiftUI

@main
struct PenpotApp: App {
    /// Only for an external display's scene (``ExternalDisplay``).
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var appState = AppState()
    @State private var settings = AppSettings()

    init() {
        Self.applyWorkSansChrome()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Resting icons/controls use Penpot's neutral gray; the brand accent
                // (purple/green) is reserved for active/selected states, applied
                // explicitly at those call sites. The `AccentColor` asset alone doesn't
                // reach SwiftUI's tint, so drive it here (and on the nav bar via UIKit).
                .tint(Color.penpotIconGray)
                .environment(appState)
                .environment(settings)
                .environment(\.locale, settings.locale)
                .environment(\.layoutDirection, settings.layoutDirection)
                // Default every un-styled `Text` to Work Sans (Penpot's UI typeface).
                // Explicitly-styled text uses `.font(.workSans(...))` at the call site.
                .environment(\.font, .workSans(.body))
                .preferredColorScheme(settings.colorScheme)
                .task { await appState.bootstrap() }
        }
    }

    /// Navigation-bar chrome (titles, back button) is drawn by UIKit and ignores SwiftUI's
    /// environment font, so restyle it with Work Sans + Penpot's own back chevron.
    private static func applyWorkSansChrome() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes[.font] = WorkSans.uiFont(for: .semibold, size: 17)
        appearance.largeTitleTextAttributes[.font] = WorkSans.uiFont(for: .bold, size: 34)

        // Work Sans on the back-button label.
        let backFont = WorkSans.uiFont(for: .regular, size: 17)
        appearance.backButtonAppearance.normal.titleTextAttributes[.font] = backFont
        appearance.backButtonAppearance.highlighted.titleTextAttributes[.font] = backFont

        // Replace the system chevron with Penpot's `arrow-left`, sized to match.
        if let chevron = penpotTemplateImage("ic-arrow-left", side: 20) {
            appearance.setBackIndicatorImage(chevron, transitionMaskImage: chevron)
        }

        // `.searchable` is UIKit's search bar: swap its magnifier and clear glyphs too.
        let searchBar = UISearchBar.appearance()
        if let magnifier = penpotTemplateImage("ic-search", side: 16) {
            searchBar.setImage(magnifier, for: .search, state: .normal)
        }
        if let clear = penpotTemplateImage("ic-close", side: 14) {
            searchBar.setImage(clear, for: .clear, state: .normal)
        }

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        // Toolbar bar-button icons (＋, ⋮, back chevron) render in Penpot's resting gray.
        bar.tintColor = .penpotIconGray
    }

    /// A Penpot icon asset as a template UIImage at a fixed point size, for UIKit chrome
    /// that ignores SwiftUI frames.
    private static func penpotTemplateImage(_ name: String, side: CGFloat) -> UIImage? {
        guard let base = UIImage(named: name) else { return nil }
        let size = CGSize(width: side, height: side)
        let scaled = UIGraphicsImageRenderer(size: size).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.withRenderingMode(.alwaysTemplate)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    var body: some View {
        // No `.id(languageIdentity)` here on purpose: re-keying the root would rebuild the
        // whole tree and reset navigation (dropping you back at the dashboard) on every
        // language change. Instead, the app root injects `.environment(\.locale, settings.locale)`,
        // which changes with `appLanguage`; SwiftUI re-resolves every `Text` in place against
        // the newly installed language bundle — a live switch that keeps the current screen.
        content
    }

    @ViewBuilder
    private var content: some View {
        switch appState.phase {
        case .loading:
            SplashView()
        case .login:
            LoginView()
        case .authenticated:
            // Another account is another app: its own navigation from the top.
            TeamsView()
                .id(appState.accountID)
        }
    }
}

/// Shown while the persisted session is validated. Deliberately identical to the static
/// launch screen, so the handover from launch image to live UI is invisible: the same
/// `LaunchLogo` (mark plus "Viewer / for Penpot", light and dark variants) at its natural
/// size, centred on the whole screen as `UILaunchScreen` centres it — not on the safe area.
private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            Image("LaunchLogo")
                .accessibilityLabel(Text(verbatim: "Viewer for Penpot"))
        }
        .ignoresSafeArea()
    }
}
