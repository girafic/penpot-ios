import SwiftUI

/// Permanently delete the account (`delete-profile`). Requires typing the account email to
/// confirm. On success the session is invalidated, so we log out locally. Like the web
/// dialog, it lists owned organizations first — those are deleted along with the account.
struct DeleteAccountView: View {
    @Environment(AppState.self) private var appState

    @State private var confirmText = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    /// Empty on servers without organizations, and when the lookup fails — the warning is
    /// informational, so it never blocks the deletion itself.
    @State private var organizations: [OwnedOrganization] = []

    private var email: String { appState.profile?.email ?? SessionStore.email ?? "" }
    private var canDelete: Bool {
        !email.isEmpty && confirmText.trimmingCharacters(in: .whitespaces).lowercased() == email.lowercased()
            && !isDeleting
    }

    var body: some View {
        // The warning keeps a card; the confirmation box and the CTA carry their own
        // surface and stand on the page directly (see PenpotCard).
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PenpotCard {
                    Label {
                        if organizations.isEmpty {
                            Text("This permanently deletes your Penpot account and all data in it. This can’t be undone.")
                        } else {
                            Text("This can’t be undone. Your account, subscription and organizations will be deleted immediately, and you’ll lose access to your projects and files.")
                        }
                    } icon: {
                        AppIcon.warning.image.foregroundStyle(.red)
                    }
                    .font(.workSans(.body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                if !organizations.isEmpty {
                    organizationList
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: $confirmText)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .penpotField(label: "Type your email to confirm")

                    Text("Enter \(email) to enable deletion.")
                        .font(.workSans(.caption))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.workSans(.callout))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(role: .destructive, action: deleteAccount) {
                    if isDeleting { ProgressView() } else { Text("Delete Account") }
                }
                .buttonStyle(.penpot(.destructive, fullWidth: true))
                .disabled(!canDelete)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .penpotPageBackground()
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadOrganizations() }
    }

    private var organizationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Organizations that will be deleted")
                .font(.workSans(.caption, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(Color.penpotIconGray)
                .frame(maxWidth: .infinity, alignment: .leading)
            PenpotCard {
                ForEach(Array(organizations.enumerated()), id: \.element.id) { index, organization in
                    PenpotCardRow(showsChevron: false) {
                        HStack(spacing: 12) {
                            PenpotAvatar(photoID: nil, baseURL: nil,
                                         initials: organization.name, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(organization.name)
                                    .font(.workSans(.body, weight: .medium))
                                // Explicit plural entries in the catalog ("%lld teams" /
                                // "%lld members") — the automatic inflect engine can't be
                                // trusted for German.
                                HStack(spacing: 4) {
                                    Text("\(organization.teamCount ?? 0) teams")
                                    Text(verbatim: "·")
                                    Text("\(organization.memberCount ?? 0) members")
                                }
                                .font(.workSans(.caption))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if index < organizations.count - 1 {
                        PenpotCardDivider()
                    }
                }
            }
        }
    }

    private func loadOrganizations() async {
        guard let client = appState.client else { return }
        organizations = (try? await client.ownedOrganizations()) ?? []
    }

    private func deleteAccount() {
        guard let client = appState.client, canDelete else { return }
        errorMessage = nil
        isDeleting = true
        Task {
            do {
                try await client.deleteProfile()
                appState.logout()
            } catch {
                errorMessage = friendlyMessage(for: error)
                isDeleting = false
            }
        }
    }

    /// Penpot rejects deletion with `owner-teams-with-people` when the user still owns a team
    /// that has other members.
    private func friendlyMessage(for error: Error) -> String {
        if case let PenpotError.server(_, body) = error,
           let body, body.contains("owner-teams-with-people") {
            return .appLocalized("You own one or more teams with other members. Transfer ownership or remove those members in Penpot, then try again.")
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
