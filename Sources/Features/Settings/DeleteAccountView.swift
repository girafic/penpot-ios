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
        Form {
            Section {
                Label {
                    Text("This permanently deletes your Penpot account and all data in it. This can’t be undone.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }

            Section {
                TextField("Type your email to confirm", text: $confirmText)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Enter \(email) to enable deletion.")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            }

            Section {
                Button(role: .destructive, action: deleteAccount) {
                    HStack {
                        Spacer()
                        if isDeleting { ProgressView() } else { Text("Delete Account").bold() }
                        Spacer()
                    }
                }
                .disabled(!canDelete)
            }
        }
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
            return String(localized: "You own one or more teams with other members. Transfer ownership or remove those members in Penpot, then try again.")
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
