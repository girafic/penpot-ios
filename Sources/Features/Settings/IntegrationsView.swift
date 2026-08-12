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
        .penpotPageBackground()
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
                    .buttonStyle(.penpot(.primary, size: .compact))
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        PenpotCard {
                            ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
                                PenpotCardRow(showsChevron: false) {
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
                                // The context menu stays the discoverable route; the swipe
                                // below reaches the same deletion outside a List.
                                .contextMenu {
                                    Button(role: .destructive) {
                                        delete(at: IndexSet(integer: index))
                                    } label: {
                                        AppIcon.delete.destructiveLabel("Delete")
                                    }
                                }
                                .penpotSwipeActions(id: token.id) {
                                    PenpotSwipeAction("Delete", icon: .delete, isDestructive: true) {
                                        delete(at: IndexSet(integer: index))
                                    }
                                }
                                if index < tokens.count - 1 {
                                    PenpotCardDivider()
                                }
                            }
                        }
                        Text("Tokens grant full API access to your account. Delete any you no longer use.")
                            .font(.workSans(.caption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(Text("Name"))
                        PenpotCard {
                            TextField("e.g. CI pipeline", text: $name)
                                .autocorrectionDisabled()
                                .font(.workSans(.body))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(Text("Expiration"))
                        // The inline Picker's rows, hand-built: `.inline` is a List/Form
                        // style and has nothing to lay itself out in here.
                        PenpotCard {
                            ForEach(Array(TokenExpiration.allCases.enumerated()), id: \.element.id) { index, option in
                                Button {
                                    expiration = option
                                } label: {
                                    PenpotCardRow(showsChevron: false) {
                                        Text(option.label)
                                    } trailing: {
                                        if expiration == option {
                                            AppIcon.tick.image
                                                .foregroundStyle(Color.penpotAccent)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                if index < TokenExpiration.allCases.count - 1 {
                                    PenpotCardDivider()
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        PenpotCard {
                            PenpotCardRow(showsChevron: false) {
                                Text(errorMessage).foregroundStyle(.red).font(.workSans(.callout))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .penpotPageBackground()
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

    /// A former `Section` header, now a label sitting above its card.
    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.workSans(.caption, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Color.penpotIconGray)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            ScrollView {
                VStack(spacing: 16) {
                    PenpotCard {
                        Text(token.token ?? "")
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            UIPasteboard.general.string = token.token
                            copied = true
                        } label: {
                            (copied ? AppIcon.tick : AppIcon.copy).label(copied ? "Copied" : "Copy to Clipboard")
                        }
                        .buttonStyle(.penpot(.secondary, size: .compact, fullWidth: true))
                        Text("Copy this token now — for security, Penpot won’t show it again.")
                            .font(.workSans(.caption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .penpotPageBackground()
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
