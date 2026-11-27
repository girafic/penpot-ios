import SwiftUI

/// The app's Settings hub, mirroring the sections of Penpot's web account settings
/// wherever the RPC API allows, plus iOS-native additions (appearance, about, cache).
///
/// Pushed from the profile avatar in ``TeamsView``'s toolbar.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // The active account, then the others to switch to, and one more to add.
                PenpotCard {
                    PenpotCardRow(showsChevron: false) { profileHeader }
                    AccountRows()
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

                // No link to Penpot's subscription or pricing page: App Review treats a
                // path to purchases outside In-App Purchase as steering (guideline 3.1.1).

                PenpotCard {
                    Button(role: .destructive) {
                        appState.logout(deletingLocalData: true)
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
                fallbackIcon: .user,
                initials: appState.profile?.displayName ?? SessionStore.email,
                size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.profile?.displayName ?? SessionStore.email ?? "Account")
                    .font(.workSans(.title3, weight: .semibold))
                if let email = appState.profile?.email ?? SessionStore.email {
                    Text(email).font(.workSans(.subheadline)).foregroundStyle(.secondary)
                }
                // Which server, once there is more than one account to tell apart.
                if appState.accounts.count > 1, let account = SessionStore.activeAccount {
                    Text(verbatim: account.serverLabel).font(.workSans(.subheadline)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
