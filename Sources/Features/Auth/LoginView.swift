import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @State private var serverString: String = SessionStore.serverURL?.absoluteString
        ?? SessionStore.defaultServerURL.absoluteString
    @State private var email: String = SessionStore.email ?? ""
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

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
            Form {
                Section("Penpot server") {
                    TextField("https://design.penpot.app", text: $serverString)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(serverPresets) { preset in
                                serverChip(preset)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
                }

                Section("Account") {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .onSubmit { submit() }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.workSans(.callout))
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Log In").font(.workSans(.body, weight: .bold))
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }

                Section {
                    Button(action: submitDemo) {
                        HStack {
                            Spacer()
                            Text("Log in as demo user").font(.workSans(.footnote))
                            Spacer()
                        }
                    }
                    .disabled(!canSubmitDemo)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(PenpotTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Language") {
                    Picker("App Language", selection: appLanguageBinding) {
                        Text("System").tag("")
                        ForEach(PenpotLanguage.appLocalizedLanguages) { language in
                            Text(language.nativeName).tag(language.iosCode)
                        }
                    }
                }
            }
            .navigationTitle("Penpot")
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
