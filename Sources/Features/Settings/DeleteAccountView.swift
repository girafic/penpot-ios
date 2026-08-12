import SwiftUI

/// Permanently delete the account (`delete-profile`). Requires typing the account email to
/// confirm. On success the session is invalidated, so we log out locally.
struct DeleteAccountView: View {
    @Environment(AppState.self) private var appState

    @State private var confirmText = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var email: String { appState.profile?.email ?? SessionStore.email ?? "" }
    private var canDelete: Bool {
        !email.isEmpty && confirmText.trimmingCharacters(in: .whitespaces).lowercased() == email.lowercased()
            && !isDeleting
    }

    var body: some View {
        // The warning keeps a card; the confirmation box and the CTA carry their own
        // surface and stand on the page directly (see PenpotCard).
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PenpotCard {
                    Label {
                        Text("This permanently deletes your Penpot account and all data in it. This can’t be undone.")
                    } icon: {
                        AppIcon.warning.image.foregroundStyle(.red)
                    }
                    .font(.workSans(.body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: $confirmText)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .penpotField(label: "Type your email to confirm")

                    Text("Enter \(email) to enable deletion.")
                        .font(.workSans(.caption))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.workSans(.callout))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(role: .destructive, action: deleteAccount) {
                    if isDeleting { ProgressView() } else { Text("Delete Account") }
                }
                .buttonStyle(.penpot(.destructive, fullWidth: true))
                .disabled(!canDelete)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .penpotPageBackground()
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteAccount() {
        guard let client = appState.client, canDelete else { return }
        errorMessage = nil
        isDeleting = true
        Task {
            do {
                try await client.deleteProfile()
                appState.logout()
            } catch {
                errorMessage = friendlyMessage(for: error)
                isDeleting = false
            }
        }
    }

    /// Penpot rejects deletion with `owner-teams-with-people` when the user still owns a team
    /// that has other members.
    private func friendlyMessage(for error: Error) -> String {
        if case let PenpotError.server(_, body) = error,
           let body, body.contains("owner-teams-with-people") {
            return .appLocalized("You own one or more teams with other members. Transfer ownership or remove those members in Penpot, then try again.")
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
