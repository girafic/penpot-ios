import SwiftUI

/// Password recovery: request the email (`request-profile-recovery`, deliberately
/// neutral response — anti-enumeration), then set a new password with the emailed
/// token (`recover-profile`, 15-minute expiry). Token pre-validation isn't possible
/// (the server only checks it on submit), so the reset phase fails gracefully there.
struct RecoveryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let server: URL
    let initialEmail: String
    /// Called when the password changed but no auto-login happened; hands the email
    /// back so the login form can prefill and show a hint.
    var onPasswordChanged: (String) -> Void = { _ in }

    private enum Phase {
        case request
        case sent(email: String)
        case reset
    }

    @State private var phase: Phase = .request
    @State private var email = ""
    @State private var pasteText = ""
    @State private var newPassword = ""
    @State private var repeatPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    /// Cloudflare challenged the request (SaaS bot protection) — offer the website.
    @State private var blockedByServer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch phase {
                    case .request:
                        requestSections
                    case .sent(let sentEmail):
                        sentSections(sentEmail)
                    case .reset:
                        resetSections
                    }

                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorMessage)
                                .foregroundStyle(Color.penpotDangerText)
                                .font(.workSans(.callout))
                            if blockedByServer,
                               let recoveryURL = URL(string: "\(server.absoluteString)/#/auth/recovery/request") {
                                Link("Open the website", destination: recoveryURL)
                                    .font(.workSans(.footnote))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .penpotPageBackground()
            .navigationTitle("Reset your password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .onAppear { if email.isEmpty { email = initialEmail } }
        }
    }

    // MARK: Phases

    @ViewBuilder
    private var requestSections: some View {
        TextField("", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .penpotField(label: "Email")
        PenpotPrimaryButton(title: "Send recovery email", isBusy: isSubmitting) {
            Task { await sendRequest() }
        }
        .disabled(!email.contains("@") || isSubmitting)
        alreadyHaveLinkButton
    }

    @ViewBuilder
    private func sentSections(_ sentEmail: String) -> some View {
        Text("If an account exists for \(sentEmail), we've emailed instructions. The link is valid for 15 minutes.")
            .font(.workSans(.callout))
            .frame(maxWidth: .infinity, alignment: .leading)
        alreadyHaveLinkButton
    }

    /// Offered from both the request and the sent phase — one definition so the two
    /// can't drift apart visually.
    private var alreadyHaveLinkButton: some View {
        Button("I already have a link") { phase = .reset }
            .buttonStyle(.penpot(.ghost, size: .compact, fullWidth: true))
    }

    @ViewBuilder
    private var resetSections: some View {
        VStack(spacing: 12) {
            TextField("", text: $pasteText, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .penpotField(label: "Recovery link")
            SecureField("", text: $newPassword)
                .textContentType(.newPassword)
                .penpotField(label: "New password",
                             error: newPassword.isEmpty || newPassword.count >= 8
                             ? nil : Text("At least 8 characters."))
            SecureField("", text: $repeatPassword)
                .textContentType(.newPassword)
                .penpotField(label: "Repeat password",
                             error: repeatPassword.isEmpty || repeatPassword == newPassword
                             ? nil : Text("Passwords don't match."))
        }
        PenpotPrimaryButton(title: "Change password", isBusy: isSubmitting) {
            Task { await changePassword() }
        }
        .disabled(newPassword.count < 8 || newPassword != repeatPassword
                  || pasteText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
    }

    // MARK: Actions

    private func sendRequest() async {
        isSubmitting = true
        errorMessage = nil
        blockedByServer = false
        defer { isSubmitting = false }
        let client = PenpotClient(baseURL: server)
        do {
            try await client.requestProfileRecovery(email: email)
            phase = .sent(email: email)
        } catch let error as PenpotError {
            switch error.serverErrorCode {
            // Legacy self-hosted servers answer with specifics; map the actionable ones.
            case "profile-not-verified":
                errorMessage = .appLocalized("Verify your email address first — check your inbox for the registration email.")
            case "profile-is-muted", "email-has-permanent-bounces", "email-has-complaints":
                errorMessage = .appLocalized("We can't send email to this address. Contact your server admin.")
            default:
                if case .forbidden = error {
                    blockedByServer = true
                    errorMessage = .appLocalized("The server blocked this request. Please try again or use the website.")
                } else {
                    // Anti-enumeration: unmapped failures get the same neutral message.
                    phase = .sent(email: email)
                }
            }
        } catch {
            phase = .sent(email: email)
        }
    }

    private func changePassword() async {
        guard let token = PenpotClient.authToken(fromPastedText: pasteText) else {
            errorMessage = .appLocalized("That link isn't valid — make sure you copied the entire link from the email.")
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let client = PenpotClient(baseURL: server)
        do {
            try await client.recoverProfile(token: token, password: newPassword)
            // Auto-login when the email is known; otherwise back to a prefilled login.
            if email.contains("@"), (try? await appState.login(server: server, email: email,
                                                               password: newPassword)) != nil {
                dismiss()
            } else {
                onPasswordChanged(email)
                dismiss()
            }
        } catch let error as PenpotError where error.serverErrorReason == "token-expired" {
            errorMessage = .appLocalized("This link has expired (they last 15 minutes). Request a new one.")
        } catch let error as PenpotError where error.serverErrorCode == "invalid-token" {
            errorMessage = .appLocalized("That link isn't valid — make sure you copied the entire link from the email.")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
