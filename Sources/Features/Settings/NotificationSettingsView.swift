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
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { if phase == .loading { await load() } }
    }

    private var form: some View {
        Form {
            Section("Dashboard") {
                Picker("Comments", selection: $settings.dashboardComments) {
                    ForEach(CommentNotification.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Email") {
                Picker("Comments", selection: $settings.emailComments) {
                    ForEach(CommentNotification.allCases) { Text($0.label).tag($0) }
                }
                Picker("Team invitations", selection: $settings.emailInvites) {
                    ForEach(InviteNotification.allCases) { Text($0.label).tag($0) }
                }
            }

            if let saveError {
                Section { Text(saveError).foregroundStyle(.red).font(.workSans(.callout)) }
            }

            Section {
                Button(action: save) {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() } else { Text("Save").font(.workSans(.body, weight: .bold)) }
                        Spacer()
                    }
                }
                .disabled(isSaving)
            }
        }
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
