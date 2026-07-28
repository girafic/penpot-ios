import SwiftUI

@main
struct PenpotApp: App {
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
        if let chevron = penpotBackChevron() {
            appearance.setBackIndicatorImage(chevron, transitionMaskImage: chevron)
        }

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        // Toolbar bar-button icons (＋, ⋮, back chevron) render in Penpot's resting gray.
        bar.tintColor = .penpotIconGray
    }

    /// Penpot's `arrow-left` icon as a template UIImage, scaled to a back-indicator size.
    private static func penpotBackChevron() -> UIImage? {
        guard let base = UIImage(named: "ic-arrow-left") else { return nil }
        let size = CGSize(width: 20, height: 20)
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
            LoadingView(message: "Connecting…")
        case .login:
            LoginView()
        case .authenticated:
            TeamsView()
        }
    }
}
