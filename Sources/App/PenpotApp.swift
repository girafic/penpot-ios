import SwiftUI

@main
struct PenpotApp: App {
    @State private var appState = AppState()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(settings)
                .environment(\.locale, settings.locale)
                .preferredColorScheme(settings.colorScheme)
                .task { await appState.bootstrap() }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    var body: some View {
        content
            // Rebuild the whole tree when the language changes so every `Text` re-resolves
            // against the newly installed language bundle (live switch, no relaunch).
            .id(settings.languageIdentity)
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
