import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState

    @State private var serverString: String = SessionStore.serverURL?.absoluteString
        ?? SessionStore.defaultServerURL.absoluteString
    @State private var email: String = SessionStore.email ?? ""
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && normalizedServerURL != nil && !isSubmitting
    }

    private var normalizedServerURL: URL? {
        var trimmed = serverString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http") {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Penpot server") {
                    TextField("https://design.penpot.app", text: $serverString)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                            .font(.callout)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Log In").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Penpot")
        }
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
}
