import SwiftUI

/// Notification preferences. Reads current values via a no-op `update-profile-props` (which
/// returns `props.notifications` and isn't Cloudflare-blocked) and writes via
/// `update-profile-notifications`.
struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var settings = NotificationSettings()
    @State private var phase: Phase = .loading
    @State private var isSaving = false
    @State private var saveError: String?

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                LoadingView(message: "Loading notifications…")
            case let .failed(message):
                ErrorStateView(message: message) { Task { await load() } }
            case .ready:
                form
            }
        }
        .penpotPageBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { if phase == .loading { await load() } }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Dashboard"))
                    PenpotCard {
                        PenpotCardRow(showsChevron: false) {
                            Text("Comments")
                        } trailing: {
                            PenpotMenuPicker(
                                title: "Comments",
                                selection: $settings.dashboardComments,
                                options: CommentNotification.allCases.map { ($0, Text($0.label)) })
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Email"))
                    PenpotCard {
                        PenpotCardRow(showsChevron: false) {
                            Text("Comments")
                        } trailing: {
                            PenpotMenuPicker(
                                title: "Comments",
                                selection: $settings.emailComments,
                                options: CommentNotification.allCases.map { ($0, Text($0.label)) })
                        }
                        PenpotCardDivider()
                        PenpotCardRow(showsChevron: false) {
                            Text("Team invitations")
                        } trailing: {
                            PenpotMenuPicker(
                                title: "Team invitations",
                                selection: $settings.emailInvites,
                                options: InviteNotification.allCases.map { ($0, Text($0.label)) })
                        }
                    }
                }

                if let saveError {
                    PenpotCard {
                        PenpotCardRow(showsChevron: false) {
                            Text(saveError).foregroundStyle(.red).font(.workSans(.callout))
                        }
                    }
                }

                PenpotPrimaryButton(title: "Save", isBusy: isSaving, action: save)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
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

    private func load() async {
        guard let client = appState.client else { return }
        phase = .loading
        do {
            settings = try await client.fetchNotifications()
            phase = .ready
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func save() {
        guard let client = appState.client else { return }
        saveError = nil
        isSaving = true
        Task {
            do {
                try await client.updateNotifications(settings)
            } catch {
                saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}
