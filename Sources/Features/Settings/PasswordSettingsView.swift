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
            return String(format: .appLocalized("Use at least %lld characters."), Self.minLength)
        }
        if let email, newPassword.lowercased() == email.lowercased() {
            return .appLocalized("Your password can’t be the same as your email.")
        }
        if !confirmPassword.isEmpty, newPassword != confirmPassword {
            return .appLocalized("The passwords don’t match.")
        }
        return nil
    }

    private var canSubmit: Bool {
        !oldPassword.isEmpty && !newPassword.isEmpty && newPassword == confirmPassword
            && validationError == nil && !isSubmitting
    }

    var body: some View {
        // Boxed Penpot fields carry their own surface, so they stand on the page
        // directly instead of inside a card (see PenpotCard).
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SecureField("", text: $oldPassword)
                    .textContentType(.password)
                    .penpotField(label: "Current password")

                VStack(alignment: .leading, spacing: 8) {
                    SecureField("", text: $newPassword)
                        .textContentType(.newPassword)
                        .penpotField(label: "New password")
                    SecureField("", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .penpotField(label: "Confirm new password")

                    Group {
                        if let validationError {
                            Text(validationError).foregroundStyle(.red)
                        } else {
                            Text("At least \(Self.minLength) characters.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.workSans(.caption))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.workSans(.callout))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PenpotPrimaryButton(title: "Change Password", isBusy: isSubmitting, action: submit)
                    .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .penpotPageBackground()
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
