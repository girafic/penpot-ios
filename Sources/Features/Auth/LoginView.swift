import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    /// Signing in to one more account, from Settings: a sheet with a way back, and the
    /// form starts empty instead of with the last login.
    let isAddingAccount: Bool

    @State private var serverString: String
    @State private var email: String
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var authConfig: PenpotClient.ServerAuthConfig = .fallback
    @State private var showRegister = false
    @State private var showRecovery = false

    init(isAddingAccount: Bool = false) {
        self.isAddingAccount = isAddingAccount
        let server = isAddingAccount ? nil : SessionStore.serverURL
        _serverString = State(initialValue: (server ?? SessionStore.defaultServerURL).absoluteString)
        _email = State(initialValue: isAddingAccount ? "" : SessionStore.email ?? "")
    }

    /// Accounts still signed in besides the one this form is for: one tap away, so an
    /// account the server signed out doesn't lock the others out.
    private var otherAccounts: [StoredAccount] {
        appState.accounts.filter { $0.id != appState.accountID && SessionStore.isSignedIn($0) }
    }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && normalizedServerURL != nil && !isSubmitting
    }

    /// A demo login only needs a valid server — credentials are minted by the server.
    private var canSubmitDemo: Bool {
        normalizedServerURL != nil && !isSubmitting
    }

    private var normalizedServerURL: URL? { Self.normalize(serverString) }

    /// Normalizes a user- or preset-supplied server string into a comparable URL:
    /// prepends `https://` when no scheme is given, and drops trailing slashes.
    private static func normalize(_ string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http") {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    /// Quick-pick servers surfaced as chips above the URL field. The two dev
    /// entries target `localhost`, which the Simulator resolves to the host Mac.
    private struct ServerPreset: Identifiable {
        var id: String { url }
        let label: String
        let url: String
    }

    private let serverPresets: [ServerPreset] = [
        .init(label: "Penpot Cloud", url: SessionStore.defaultServerURL.absoluteString),
        .init(label: "Local :9001", url: "http://localhost:9001"),
        .init(label: "Dev :3449", url: "https://localhost:3449"),
        .init(label: "Dev :3450", url: "http://localhost:3450"),
    ]

    private func isSelected(_ preset: ServerPreset) -> Bool {
        guard let current = normalizedServerURL, let presetURL = Self.normalize(preset.url) else {
            return false
        }
        return current == presetURL
    }

    var body: some View {
        @Bindable var settings = settings
        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        TextField("https://design.penpot.app", text: $serverString)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .penpotField(label: "Penpot server")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(serverPresets) { preset in
                                    serverChip(preset)
                                }
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        // The label carries the name now, so the placeholder would only
                        // duplicate it while the field is empty.
                        TextField("", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .penpotField(label: "Email")
                        SecureField("", text: $password)
                            .textContentType(.password)
                            .onSubmit { submit() }
                            .penpotField(label: "Password")
                    }

                    // A login failure is rarely field-specific (bad credentials, unreachable
                    // server, Cloudflare) — keep it as a banner rather than pinning it to one box.
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(Color.penpotDangerText)
                            .font(.workSans(.callout))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let infoMessage {
                        Text(infoMessage)
                            .foregroundStyle(.secondary)
                            .font(.workSans(.callout))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PenpotPrimaryButton(title: "Log In", isBusy: isSubmitting, action: submit)
                        .disabled(!canSubmit)

                    VStack(spacing: 12) {
                        // All three are plain text links on the web, sharing one rule
                        // (`demo-account-link` / `forgot-pass-link` / `register-link`).
                        // Penpot gates the demo link on the same `demo-users` flag.
                        if authConfig.demoUsersEnabled {
                            Button("Log in as demo user", action: submitDemo)
                                .buttonStyle(.penpot(.link, fullWidth: true))
                                .disabled(!canSubmitDemo)
                        }

                        HStack {
                            Button("Forgot password?") { showRecovery = true }
                            Spacer()
                            if authConfig.registrationEnabled {
                                Button("Create account") { showRegister = true }
                            }
                        }
                        .buttonStyle(.penpot(.link))
                        .disabled(normalizedServerURL == nil || isSubmitting)
                    }

                    if !isAddingAccount, !otherAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SettingsSectionHeader(title: Text("Switch Account"))
                            PenpotCard {
                                ForEach(Array(otherAccounts.enumerated()), id: \.element.id) { index, account in
                                    if index > 0 { PenpotCardDivider() }
                                    Button {
                                        Task { await appState.switchAccount(to: account.id) }
                                    } label: {
                                        PenpotCardRow { AccountLabel(account: account) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !isAddingAccount {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Appearance")
                                .font(.workSans(.caption, weight: .semibold))
                                .textCase(.uppercase)
                                .kerning(0.5)
                                .foregroundStyle(Color.penpotIconGray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PenpotSegmentedPicker(selection: $settings.theme,
                                                  segments: PenpotTheme.allCases.map { ($0, Text($0.label)) })
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Language")
                                .font(.workSans(.caption, weight: .semibold))
                                .textCase(.uppercase)
                                .kerning(0.5)
                                .foregroundStyle(Color.penpotIconGray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PenpotCard {
                                PenpotCardRow(showsChevron: false) {
                                    Text("App Language")
                                } trailing: {
                                    PenpotMenuPicker(
                                        title: "App Language",
                                        selection: appLanguageBinding,
                                        options: [("", Text("System"))]
                                            + PenpotLanguage.appLocalizedLanguages.map {
                                                ($0.iosCode, Text($0.nativeName))
                                            })
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .penpotPageBackground()
            // The app's own name, never "Penpot" alone (Kaleidos' trademark). Not translated;
            // 303 pt in Work Sans Bold 34, so it fits an iPhone mini's large title.
            .navigationTitle(isAddingAccount ? Text("Add Account") : Text(verbatim: "Viewer for Penpot"))
            .navigationBarTitleDisplayMode(isAddingAccount ? .inline : .automatic)
            .toolbar {
                if isAddingAccount {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            // A login that didn't happen may have taken the active account's cookie of the
            // same server with it.
            .onDisappear { if isAddingAccount { appState.restoreActiveCookie() } }
            // Capability probe (registration/terms/newsletter) — best-effort, debounced
            // via task identity while the server field is being edited.
            .task(id: normalizedServerURL) {
                guard let server = normalizedServerURL else { return }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                authConfig = await PenpotClient(baseURL: server).fetchAuthConfig()
            }
            .sheet(isPresented: $showRegister) {
                if let server = normalizedServerURL {
                    RegisterView(server: server, config: authConfig, onLogin: { existing in
                        email = existing
                        infoMessage = nil
                    })
                }
            }
            .sheet(isPresented: $showRecovery) {
                if let server = normalizedServerURL {
                    RecoveryView(server: server, initialEmail: email, onPasswordChanged: { changed in
                        email = changed
                        password = ""
                        infoMessage = .appLocalized("Password changed — log in with your new password.")
                    })
                }
            }
        }
    }

    /// Sets the app language, applied live (see ``AppSettings/appLanguage``). Bound to a plain
    /// `String` because `Picker` can't tag an optional; "" means “System”.
    private var appLanguageBinding: Binding<String> {
        Binding(
            get: { settings.appLanguage ?? "" },
            set: { newValue in
                let code: String? = newValue.isEmpty ? nil : newValue
                guard code != settings.appLanguage else { return }
                settings.appLanguage = code
            }
        )
    }

    /// A tappable server preset. Selected when the field currently matches it.
    private func serverChip(_ preset: ServerPreset) -> some View {
        let selected = isSelected(preset)
        return Button {
            serverString = preset.url
        } label: {
            Text(preset.label)
                .font(.workSans(.subheadline, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.penpotAccent : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.penpotAccent : Color.secondary.opacity(0.35),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        guard let server = normalizedServerURL, !isSubmitting else { return }
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                try await appState.login(server: server, email: email, password: password)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func submitDemo() {
        guard let server = normalizedServerURL, !isSubmitting else { return }
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                try await appState.loginWithDemoAccount(server: server)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
