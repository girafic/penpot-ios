import SwiftUI

/// Sheet for inviting people to a team by email (`create-team-invitations`). Multiple
/// comma/whitespace-separated addresses share a single role.
struct InviteMembersSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let team: Team
    /// Called after invitations were sent so the parent can refresh its list.
    var onInvited: () -> Void = {}

    @State private var emailsText = ""
    @State private var role: TeamRole = .editor
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showingAllMembersInfo = false

    /// The server rejects requests with more than 25 invitations.
    private static let maxInvitations = 25

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email addresses", text: $emailsText, axis: .vertical)
                        .lineLimit(2...5)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Separate multiple addresses with commas.")
                }
                Section {
                    Picker("Role", selection: $role) {
                        ForEach(TeamRole.assignable) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                }
            }
            .navigationTitle("Invite Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }
                            .disabled(parsedEmails.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSending)
            .alert("Something went wrong", isPresented: errorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Already Members", isPresented: $showingAllMembersInfo) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text("Everyone on this list is already a member.")
            }
        }
    }

    private var errorAlert: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// Splits on commas/semicolons/whitespace, trims, lowercases, and dedupes while
    /// preserving order. The server re-validates each address.
    private var parsedEmails: [String] {
        var seen = Set<String>()
        return emailsText
            .components(separatedBy: CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines))
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func looksLikeEmail(_ candidate: String) -> Bool {
        candidate.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    private func send() async {
        guard let client = appState.client else { return }
        let emails = parsedEmails
        guard !emails.isEmpty else { return }
        if let invalid = emails.first(where: { !Self.looksLikeEmail($0) }) {
            errorMessage = String(format: .appLocalized("Invalid email address: %@"), invalid)
            return
        }
        guard emails.count <= Self.maxInvitations else {
            errorMessage = .appLocalized("You can invite up to 25 people at once.")
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let result = try await client.createTeamInvitations(teamID: team.id, emails: emails, role: role)
            onInvited()
            if result.total == 0 {
                // Every addressee is already a member — the server silently created nothing.
                showingAllMembersInfo = true
            } else {
                dismiss()
            }
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
