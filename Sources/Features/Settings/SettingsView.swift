import SwiftUI

/// The app's Settings hub, mirroring the sections of Penpot's web account settings
/// wherever the RPC API allows, plus iOS-native additions (appearance, about, cache).
///
/// Pushed from the profile row in ``TeamsView``.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                profileHeader
            }

            Section("Account") {
                NavigationLink {
                    ProfileSettingsView()
                } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                NavigationLink {
                    PasswordSettingsView()
                } label: {
                    Label("Password", systemImage: "lock")
                }
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
                NavigationLink {
                    IntegrationsView()
                } label: {
                    Label("Access Tokens", systemImage: "key")
                }
            }

            Section("App") {
                NavigationLink {
                    AppearanceView()
                } label: {
                    Label("Appearance", systemImage: "paintbrush")
                }
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }

            Section {
                Button {
                    openSubscription()
                } label: {
                    HStack {
                        Label("Subscription", systemImage: "creditcard")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            } footer: {
                Text("Manage your Penpot plan and billing in your browser.")
            }

            Section {
                Button("Log Out", role: .destructive) {
                    appState.logout()
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            PenpotAvatar(
                photoID: appState.profile?.photoId,
                baseURL: appState.client?.baseURL,
                fallbackSymbol: "person.fill",
                size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.profile?.displayName ?? SessionStore.email ?? "Account")
                    .font(.title3.weight(.semibold))
                if let email = appState.profile?.email ?? SessionStore.email {
                    Text(email).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    /// Opens the Penpot subscription page in the browser. There is no public RPC for
    /// billing — it's cloud-only — so we deep-link to the web app, falling back to the
    /// public pricing page.
    private func openSubscription() {
        if let base = appState.client?.baseURL,
           let url = URL(string: "\(base.absoluteString)/#/settings/subscriptions") {
            openURL(url)
        } else {
            openURL(URL(string: "https://penpot.app/pricing")!)
        }
    }
}
