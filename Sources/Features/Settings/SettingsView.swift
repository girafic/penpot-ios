import SwiftUI

/// The app's Settings hub, mirroring the sections of Penpot's web account settings
/// wherever the RPC API allows, plus iOS-native additions (appearance, about, cache).
///
/// Pushed from the profile row in ``TeamsView``.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PenpotCard {
                    PenpotCardRow(showsChevron: false) { profileHeader }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Account"))
                    PenpotCard {
                        NavigationLink {
                            ProfileSettingsView()
                        } label: {
                            PenpotCardRow { AppIcon.user.label("Profile") }
                        }
                        .buttonStyle(.plain)
                        PenpotCardDivider()
                        NavigationLink {
                            PasswordSettingsView()
                        } label: {
                            PenpotCardRow { AppIcon.lock.label("Password") }
                        }
                        .buttonStyle(.plain)
                        PenpotCardDivider()
                        NavigationLink {
                            NotificationSettingsView()
                        } label: {
                            PenpotCardRow { AppIcon.notifications.label("Notifications") }
                        }
                        .buttonStyle(.plain)
                        PenpotCardDivider()
                        NavigationLink {
                            IntegrationsView()
                        } label: {
                            PenpotCardRow { AppIcon.key.label("Access Tokens") }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("App"))
                    PenpotCard {
                        NavigationLink {
                            AppearanceView()
                        } label: {
                            PenpotCardRow { AppIcon.appearance.label("Appearance") }
                        }
                        .buttonStyle(.plain)
                        PenpotCardDivider()
                        NavigationLink {
                            AboutView()
                        } label: {
                            PenpotCardRow { AppIcon.info.label("About") }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    PenpotCard {
                        Button {
                            openSubscription()
                        } label: {
                            PenpotCardRow(showsChevron: false) {
                                AppIcon.subscription.label("Subscription")
                            } trailing: {
                                AppIcon.externalLink.image
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Manage your Penpot plan and billing in your browser.")
                        .font(.workSans(.caption))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PenpotCard {
                    Button(role: .destructive) {
                        appState.logout()
                    } label: {
                        PenpotCardRow(showsChevron: false) {
                            Text("Log Out")
                                .foregroundStyle(Color.penpotDangerText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .penpotPageBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A former `Section` header, now a label sitting above its card.
    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.workSans(.caption, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Color.penpotIconGray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            PenpotAvatar(
                photoID: appState.profile?.photoId,
                baseURL: appState.client?.baseURL,
                fallbackSymbol: "person.fill",
                initials: appState.profile?.displayName ?? SessionStore.email,
                size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.profile?.displayName ?? SessionStore.email ?? "Account")
                    .font(.workSans(.title3, weight: .semibold))
                if let email = appState.profile?.email ?? SessionStore.email {
                    Text(email).font(.workSans(.subheadline)).foregroundStyle(.secondary)
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
