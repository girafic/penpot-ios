import SwiftUI

/// Personal access tokens (Penpot's "Integrations" / "Access tokens" tab).
/// `get-access-tokens` reaches the API over plain GET, so this works despite the
/// `get-profile` Cloudflare block.
struct IntegrationsView: View {
    @Environment(AppState.self) private var appState

    @State private var tokens: [AccessToken] = []
    @State private var phase: Phase = .loading
    @State private var showingCreate = false
    @State private var createdSecret: AccessToken?

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                LoadingView(message: "Loading tokens…")
            case let .failed(message):
                ErrorStateView(message: message) { Task { await load() } }
            case .ready:
                list
            }
        }
        .navigationTitle("Access Tokens")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: { AppIcon.add.image }
                    .accessibilityLabel("Create token")
            }
        }
        .task { if phase == .loading { await load() } }
        .sheet(isPresented: $showingCreate) {
            CreateTokenSheet { name, expiration in
                try await create(name: name, expiration: expiration)
            }
        }
        .sheet(item: $createdSecret) { token in
            TokenSecretSheet(token: token)
        }
    }

    @ViewBuilder
    private var list: some View {
        if tokens.isEmpty {
            ContentUnavailableView {
                AppIcon.key.label("No access tokens")
            } description: {
                Text("Create a personal access token to use the Penpot API.")
            } actions: {
                Button("Create Token") { showingCreate = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                Section {
                    ForEach(tokens) { token in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(token.name).font(.workSans(.body))
                            if let expiresAt = token.expiresAt {
                                Text("Expires \(shortDate(expiresAt))")
                                    .font(.workSans(.caption)).foregroundStyle(.secondary)
                            } else {
                                Text("Never expires")
                                    .font(.workSans(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Tokens grant full API access to your account. Delete any you no longer use.")
                }
            }
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        phase = .loading
        do {
            tokens = try await client.accessTokens()
            phase = .ready
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func create(name: String, expiration: TokenExpiration) async throws {
        guard let client = appState.client else { return }
        let token = try await client.createAccessToken(name: name, expiration: expiration)
        await load()
        // Only the create response carries the secret — surface it once.
        if token.token != nil { createdSecret = token }
    }

    private func delete(at offsets: IndexSet) {
        guard let client = appState.client else { return }
        let toDelete = offsets.map { tokens[$0] }
        tokens.remove(atOffsets: offsets)
        Task {
            for token in toDelete {
                try? await client.deleteAccessToken(id: token.id)
            }
            await load()
        }
    }

    private func shortDate(_ iso: String) -> String {
        // expiresAt is an ISO-8601 string; show just the date portion when possible.
        String(iso.prefix(10))
    }
}

/// Sheet to name a new token and pick its expiration.
private struct CreateTokenSheet: View {
    let onCreate: (String, TokenExpiration) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var expiration: TokenExpiration = .days30
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. CI pipeline", text: $name)
                        .autocorrectionDisabled()
                }
                Section("Expiration") {
                    Picker("Expiration", selection: $expiration) {
                        ForEach(TokenExpiration.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.workSans(.callout)) }
                }
            }
            .navigationTitle("New Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create") { submit() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isCreating)
    }

    private func submit() {
        errorMessage = nil
        isCreating = true
        Task {
            do {
                try await onCreate(name.trimmingCharacters(in: .whitespaces), expiration)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isCreating = false
        }
    }
}

/// One-time reveal of a freshly created token's secret.
private struct TokenSecretSheet: View {
    let token: AccessToken

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(token.token ?? "")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                Section {
                    Button {
                        UIPasteboard.general.string = token.token
                        copied = true
                    } label: {
                        (copied ? AppIcon.tick : AppIcon.copy).label(copied ? "Copied" : "Copy to Clipboard")
                    }
                } footer: {
                    Text("Copy this token now — for security, Penpot won’t show it again.")
                }
            }
            .navigationTitle("“\(token.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
