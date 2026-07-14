import SwiftUI

/// Change-password form (`update-profile-password`). Independent of `get-profile`, so it
/// works despite the Cloudflare block.
struct PasswordSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    /// Penpot's backend only rejects blank/over-long/equals-email; the 8-char minimum is a
    /// frontend rule we mirror here.
    private static let minLength = 8

    private var email: String? { appState.profile?.email ?? SessionStore.email }

    private var validationError: String? {
        guard !newPassword.isEmpty else { return nil }
        if newPassword.count < Self.minLength {
            return String(localized: "Use at least \(Self.minLength) characters.")
        }
        if let email, newPassword.lowercased() == email.lowercased() {
            return String(localized: "Your password can’t be the same as your email.")
        }
        if !confirmPassword.isEmpty, newPassword != confirmPassword {
            return String(localized: "The passwords don’t match.")
        }
        return nil
    }

    private var canSubmit: Bool {
        !oldPassword.isEmpty && !newPassword.isEmpty && newPassword == confirmPassword
            && validationError == nil && !isSubmitting
    }

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $oldPassword)
                    .textContentType(.password)
            }

            Section {
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
            } footer: {
                if let validationError {
                    Text(validationError).foregroundStyle(.red)
                } else {
                    Text("At least \(Self.minLength) characters.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.callout)
                }
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView() } else { Text("Change Password").bold() }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Password changed", isPresented: $didSucceed) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your password has been updated.")
        }
    }

    private func submit() {
        guard let client = appState.client, canSubmit else { return }
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                try await client.updatePassword(new: newPassword, old: oldPassword)
                didSucceed = true
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
