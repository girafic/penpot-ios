import SwiftUI

@main
struct PenpotApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task { await appState.bootstrap() }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
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
