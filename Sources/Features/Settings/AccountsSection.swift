import SwiftUI

/// The other accounts the app is signed in to, as rows under the active account's header
/// in Settings: a tap switches without a new login, and "Add Account" signs in to one
/// more, on the same server or another. Penpot's web app has no such list; on a phone,
/// where a browser tab per account isn't at hand, it saves logging out and in.
struct AccountRows: View {
    @Environment(AppState.self) private var appState
    @State private var addsAccount = false
    @State private var accountToRemove: StoredAccount?

    private var others: [StoredAccount] { appState.accounts.filter { $0.id != appState.accountID } }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(others) { account in
                PenpotCardDivider()
                row(account)
            }
            PenpotCardDivider()
            Button { addsAccount = true } label: {
                PenpotCardRow(showsChevron: false) { AppIcon.add.label("Add Account") }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $addsAccount) {
            LoginView(isAddingAccount: true)
        }
        .alert("Log out of this account?", isPresented: removeAlert, presenting: accountToRemove) { account in
            Button("Log Out", role: .destructive) { appState.removeAccount(account.id) }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text(verbatim: [account.email, account.serverLabel].compactMap { $0 }.joined(separator: "\n"))
        }
    }

    private var removeAlert: Binding<Bool> {
        Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } })
    }

    private func row(_ account: StoredAccount) -> some View {
        Button {
            Task { await appState.switchAccount(to: account.id) }
        } label: {
            PenpotCardRow { AccountLabel(account: account) }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Switch Account"))
        .contextMenu {
            Button(role: .destructive) { accountToRemove = account } label: {
                AppIcon.leave.destructiveLabel("Log Out")
            }
        }
        .penpotSwipeActions(id: account.id) {
            PenpotSwipeAction("Log Out", icon: .leave, isDestructive: true) { accountToRemove = account }
        }
    }
}

/// An account as a row shows it: avatar, name, and the email with the server; a session
/// the server ended says so.
struct AccountLabel: View {
    let account: StoredAccount
    var avatarSize: CGFloat = 36

    var body: some View {
        HStack(spacing: 12) {
            PenpotAvatar(photoID: account.photoID, baseURL: account.server, fallbackIcon: .user,
                         initials: account.fullname ?? account.email, size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.fullname ?? account.email ?? account.serverLabel)
                    .font(.workSans(.body, weight: .medium))
                    .lineLimit(1)
                if account.fullname != nil, let email = account.email {
                    Text(verbatim: email)
                        .font(.workSans(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(verbatim: account.serverLabel)
                    .font(.workSans(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !SessionStore.isSignedIn(account) {
                    Text("Signed out")
                        .font(.workSans(.footnote))
                        .foregroundStyle(Color.penpotDangerText)
                }
            }
        }
    }
}

/// A label above a card, as Settings' section headers look.
struct SettingsSectionHeader: View {
    let title: Text

    var body: some View {
        title
            .font(.workSans(.caption, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Color.penpotIconGray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
