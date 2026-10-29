import SwiftUI

/// Native account registration (two-step `prepare-register-profile` → `register-profile`).
/// Servers without email verification hand back a session immediately; SaaS sends a
/// verification mail — the check-email phase lets the user paste the emailed link,
/// resend it (server-throttled), or log in after clicking it in a browser.
struct RegisterView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let server: URL
    let config: PenpotClient.ServerAuthConfig
    /// Hands the email back to the login form ("Log in instead").
    var onLogin: (String) -> Void = { _ in }

    @State private var fullname = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptedTerms = false
    @State private var newsletter = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var emailExists = false
    /// Cloudflare challenged the request (SaaS bot-signup protection) — offer the
    /// website as the honest way through instead of fighting the challenge.
    @State private var blockedByServer = false
    @State private var checkEmail: CheckEmailState?
    @State private var pasteText = ""
    @State private var canResend = false

    private struct CheckEmailState: Equatable {
        let email: String
        let prepareToken: String
        var resendAvailableAt: Date
    }

    /// Server-side resend throttle window.
    private static let resendInterval: TimeInterval = 15 * 60

    private var trimmedName: String { fullname.trimmingCharacters(in: .whitespaces) }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && email.contains("@") && password.count >= 8
            && password.lowercased() != email.lowercased()
            && (!config.requiresTermsCheckbox || acceptedTerms)
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let state = checkEmail {
                        checkEmailSections(state)
                    } else {
                        formSections
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .penpotPageBackground()
            .navigationTitle(checkEmail == nil ? "Create your account" : "Check your email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .task(id: checkEmail?.resendAvailableAt) {
                guard let availableAt = checkEmail?.resendAvailableAt else { return }
                canResend = false
                let wait = availableAt.timeIntervalSinceNow
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled else { return }
                canResend = true
            }
        }
    }

    // MARK: Form

    @ViewBuilder
    private var formSections: some View {
        VStack(spacing: 12) {
            TextField("", text: $fullname)
                .textContentType(.name)
                .penpotField(label: "Full name")
            TextField("", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                // The one genuinely field-specific error worth pinning to a box.
                .penpotField(label: "Email",
                             error: emailExists ? Text("An account with this email already exists.") : nil)
            SecureField("", text: $password)
                .textContentType(.newPassword)
                .penpotField(label: "Password", error: passwordError)
        }

        if config.requiresTermsCheckbox {
            PenpotCard {
                // Not a PenpotCardRow: a Toggle needs the full row width to push its
                // switch to the trailing edge, so it carries the row's padding itself.
                Toggle("I accept the Terms of Service and Privacy Policy.", isOn: $acceptedTerms)
                    .font(.workSans(.footnote))
                    .toggleStyle(.penpot)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                PenpotCardDivider()
                PenpotCardRow(showsChevron: false) {
                    HStack(spacing: 16) {
                        if let termsURL = config.termsURL {
                            Link("Terms of Service", destination: termsURL)
                        }
                        if let privacyURL = config.privacyURL {
                            Link("Privacy Policy", destination: privacyURL)
                        }
                    }
                    .font(.workSans(.caption))
                }
            }
        }

        if config.offersNewsletter {
            PenpotCard {
                Toggle("Subscribe to Penpot news", isOn: $newsletter)
                    .font(.workSans(.footnote))
                    .toggleStyle(.penpot)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }

        if let errorMessage, !emailExists {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorMessage)
                    .foregroundStyle(Color.penpotDangerText)
                    .font(.workSans(.callout))
                if blockedByServer,
                   let registerURL = URL(string: "\(server.absoluteString)/#/auth/register") {
                    Link("Register on the website", destination: registerURL)
                        .font(.workSans(.footnote))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        VStack(spacing: 12) {
            if emailExists {
                Button("Log in instead") {
                    onLogin(email)
                    dismiss()
                }
                .buttonStyle(.penpot(.secondary, size: .compact, fullWidth: true))
            }
            PenpotPrimaryButton(title: "Sign Up", isBusy: isSubmitting) {
                Task { await submit() }
            }
            .disabled(!canSubmit)
        }
    }

    /// Local password-rule feedback, shown inside the password box.
    private var passwordError: Text? {
        guard !password.isEmpty else { return nil }
        if password.count < 8 { return Text("At least 8 characters.") }
        if password.lowercased() == email.lowercased() {
            return Text("The password can't be your email address.")
        }
        return nil
    }

    // MARK: Check-email phase

    @ViewBuilder
    private func checkEmailSections(_ state: CheckEmailState) -> some View {
        PenpotCard {
            PenpotCardRow(showsChevron: false) {
                Text("We sent a verification link to \(state.email).")
                    .font(.workSans(.callout))
            }
        }

        VStack(spacing: 12) {
            TextField("", text: $pasteText, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .penpotField(label: "Paste the link from the email")
            Button("Verify") { Task { await verifyPasted() } }
                .buttonStyle(.penpot(.secondary, size: .compact, fullWidth: true))
                .disabled(pasteText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
        }

        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(Color.penpotDangerText)
                .font(.workSans(.callout))
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 12) {
                Button("I clicked the link — log in") { Task { await loginAfterVerification(state) } }
                    .buttonStyle(.penpot(.ghost, size: .compact, fullWidth: true))
                    .disabled(isSubmitting)
                Button("Resend email") { Task { await resend(state) } }
                    .buttonStyle(.penpot(.ghost, size: .compact, fullWidth: true))
                    .disabled(!canResend || isSubmitting)
            }
            if !canResend {
                // Live countdown to the server's resend-throttle window.
                HStack(spacing: 4) {
                    Text("Resend available in")
                    Text(timerInterval: Date.now...state.resendAvailableAt, countsDown: true)
                }
                .font(.workSans(.caption))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func submit() async {
        guard let clean = HTTPCookieStorage.shared.cookies(for: server) else { return runSubmit() }
        clean.forEach(HTTPCookieStorage.shared.deleteCookie)
        runSubmit()
    }

    private func runSubmit() {
        isSubmitting = true
        errorMessage = nil
        emailExists = false
        blockedByServer = false
        Task {
            defer { isSubmitting = false }
            let client = PenpotClient(baseURL: server)
            do {
                let token = try await client.prepareRegister(fullname: trimmedName,
                                                            email: email, password: password)
                let result = try await client.registerProfile(token: token, acceptNewsletter: newsletter)
                if result.profile != nil || result.invitationToken != nil {
                    // Full profile ⇒ the server set the session cookie right here.
                    try await appState.completeRegistration(server: server, email: email,
                                                            profile: result.profile, client: client)
                    dismiss()
                } else {
                    checkEmail = CheckEmailState(email: email, prepareToken: token,
                                                 resendAvailableAt: .now.addingTimeInterval(Self.resendInterval))
                }
            } catch {
                handle(error)
            }
        }
    }

    private func verifyPasted() async {
        guard let state = checkEmail else { return }
        guard let token = PenpotClient.authToken(fromPastedText: pasteText) else {
            errorMessage = .appLocalized("That doesn't look like a Penpot link — copy the entire link from the email.")
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let client = PenpotClient(baseURL: server)
        do {
            try await client.verifyToken(token)
            try await appState.completeRegistration(server: server, email: state.email,
                                                    profile: nil, client: client)
            dismiss()
        } catch let error as PenpotError where error.serverErrorReason == "token-expired" {
            errorMessage = .appLocalized("The link expired — resend the email.")
        } catch {
            handle(error)
        }
    }

    /// Poll-free path for users who opened the link in a browser: the account is active
    /// now, so a normal login with the still-known credentials succeeds.
    private func loginAfterVerification(_ state: CheckEmailState) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await appState.login(server: server, email: state.email, password: password)
            dismiss()
        } catch {
            errorMessage = .appLocalized("Not verified yet — click the link in the email first.")
        }
    }

    /// Redeeming the same prepare token again re-sends the verification email.
    private func resend(_ state: CheckEmailState) async {
        errorMessage = nil
        do {
            _ = try await PenpotClient(baseURL: server)
                .registerProfile(token: state.prepareToken, acceptNewsletter: newsletter)
            checkEmail?.resendAvailableAt = .now.addingTimeInterval(Self.resendInterval)
        } catch let error as PenpotError where error.serverErrorReason == "token-expired" {
            // The 7-day prepare token itself expired — start over.
            checkEmail = nil
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        if let penpotError = error as? PenpotError {
            if penpotError.isUnknownCommand {
                errorMessage = .appLocalized("This server doesn't support in-app registration.")
                return
            }
            switch penpotError.serverErrorCode {
            case "email-already-exists":
                emailExists = true
                errorMessage = .appLocalized("An account with this email already exists.")
                return
            case "registration-disabled":
                errorMessage = .appLocalized("This server does not allow new registrations.")
                return
            case "email-domain-is-not-allowed":
                errorMessage = .appLocalized("This email domain is not allowed on this server.")
                return
            case "email-as-password":
                errorMessage = .appLocalized("The password can't be your email address.")
                return
            case "email-has-permanent-bounces", "email-has-complaints":
                errorMessage = .appLocalized("This email address can't receive our messages.")
                return
            default:
                break
            }
            if case .forbidden = penpotError {
                blockedByServer = true
                errorMessage = .appLocalized("The server blocked this request. Please try again or use the website.")
                return
            }
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
