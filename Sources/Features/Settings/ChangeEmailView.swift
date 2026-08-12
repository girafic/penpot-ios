import SwiftUI

/// Request an email change (`request-email-change`). On design.penpot.app (SMTP enabled) this
/// sends a confirmation link and the change only completes when the user clicks it, so the app
/// can only confirm the request was sent.
struct ChangeEmailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var newEmail = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var result: Result?

    private enum Result: Identifiable {
        case confirmationSent
        case changed
        var id: Int { hashValue }
    }

    private var canSubmit: Bool {
        newEmail.contains("@") && newEmail.contains(".") && !isSubmitting
            && newEmail.lowercased() != (appState.profile?.email ?? SessionStore.email)?.lowercased()
    }

    var body: some View {
        // Boxed Penpot fields carry their own surface, so they stand on the page
        // directly instead of inside a card (see PenpotCard).
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: $newEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .penpotField(label: "New email")

                    Text("Penpot will email a confirmation link to the new address. The change takes effect once you open that link.")
                        .font(.workSans(.caption))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.workSans(.callout))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PenpotPrimaryButton(title: "Request Change", isBusy: isSubmitting, action: submit)
                    .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .penpotPageBackground()
        .navigationTitle("Change Email")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $result) { result in
            switch result {
            case .confirmationSent:
                Alert(title: Text("Check your inbox"),
                      message: Text("We sent a confirmation link to \(newEmail). Open it to finish changing your email."),
                      dismissButton: .default(Text("OK")) { dismiss() })
            case .changed:
                Alert(title: Text("Email changed"),
                      message: Text("Your email is now \(newEmail)."),
                      dismissButton: .default(Text("OK")) { dismiss() })
            }
        }
    }

    private func submit() {
        guard let client = appState.client, canSubmit else { return }
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                let changedImmediately = try await client.requestEmailChange(to: newEmail)
                result = changedImmediately ? .changed : .confirmationSent
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
