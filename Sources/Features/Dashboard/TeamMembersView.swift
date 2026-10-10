import SwiftUI

/// A team's member roster and pending invitations, mirroring Penpot's web members page.
/// Every member may view the roster; inviting, role changes, removals and invitation
/// management are admin/owner-only. Leaving the team is available to any member — an
/// owner must first hand the team to a new owner (picked via a reused ``MoveSheet``).
struct TeamMembersView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let team: Team
    /// Called after the current user left the team, so the caller can pop and refresh.
    var onTeamLeft: (() -> Void)? = nil

    @State private var members: [TeamMember] = []
    /// nil while loading or when the server doesn't support invitations — the section is
    /// hidden then instead of blanking the roster.
    @State private var invitations: [TeamInvitation]?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var pendingConfirmation: PendingConfirmation?
    @State private var showingInvite = false
    @State private var showingOwnerPicker = false

    private enum PendingConfirmation {
        case removeMember(TeamMember)
        case deleteInvitation(TeamInvitation)
        case transferOwnership(TeamMember)
        case leaveTeam
    }

    // MARK: Permissions

    private func isSelf(_ member: TeamMember) -> Bool {
        if let myID = appState.profile?.id,
           member.id == myID || member.profileId == myID { return true }
        guard let email = SessionStore.email?.lowercased() else { return false }
        return member.email?.lowercased() == email
    }

    private var myMember: TeamMember? { members.first(where: isSelf) }

    /// `Team.permissions` comes from `get-teams`; the loaded roster is the fallback for
    /// `Team` values that predate the permissions field.
    private var isAdmin: Bool {
        if let permissions = team.permissions { return permissions.isAdminOrOwner }
        guard let role = myMember?.role else { return false }
        return role == .owner || role == .admin
    }

    private var isOwner: Bool {
        team.permissions?.isOwner == true || myMember?.role == .owner
    }

    private var sortedMembers: [TeamMember] {
        members.sorted {
            if $0.role.rank != $1.role.rank { return $0.role.rank < $1.role.rank }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // MARK: Body

    var body: some View {
        content
            .penpotPageBackground()
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isAdmin {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingInvite = true } label: { AppIcon.add.image }
                            .accessibilityLabel("Invite Members")
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert(confirmationTitle, isPresented: confirmationAlert, presenting: pendingConfirmation) { confirmation in
                confirmationButton(for: confirmation)
                Button("Cancel", role: .cancel) {}
            } message: { confirmation in
                confirmationMessage(for: confirmation)
            }
            .alert("Something went wrong", isPresented: actionErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
            .sheet(isPresented: $showingInvite) {
                InviteMembersSheet(team: team) { Task { await load() } }
            }
            .sheet(isPresented: $showingOwnerPicker) {
                MoveSheet(title: "Select New Owner",
                          failureTitle: "Couldn’t leave team",
                          load: { candidateOwners() },
                          onSelect: { target in try await leave(reassignTo: target.id) })
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && members.isEmpty {
            LoadingView(message: "Loading members…")
        } else if let errorMessage, members.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else {
            // Hand-built cards rather than a List (see PenpotCard).
            ScrollView {
                LazyVStack(spacing: 16) {
                    PenpotCard {
                        ForEach(Array(sortedMembers.enumerated()), id: \.element.id) { index, member in
                            memberRow(member)
                            if index < sortedMembers.count - 1 {
                                PenpotCardDivider()
                            }
                        }
                    }
                    if let invitations {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader(Text("Pending Invitations"))
                            PenpotCard {
                                if invitations.isEmpty {
                                    PenpotCardRow(showsChevron: false) {
                                        Text("No pending invitations")
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    ForEach(Array(invitations.enumerated()), id: \.element.id) { index, invitation in
                                        invitationRow(invitation)
                                        if index < invitations.count - 1 {
                                            PenpotCardDivider()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    /// A section title above a card, in Penpot's uppercase label style.
    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.workSans(.caption, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Color.penpotIconGray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Member rows

    private func memberRow(_ member: TeamMember) -> some View {
        PenpotCardRow(showsChevron: false) {
            HStack(spacing: 12) {
                PenpotAvatar(photoID: member.photoId, baseURL: appState.client?.baseURL,
                             initials: member.displayName, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(member.displayName)
                            .font(.workSans(.subheadline))
                        if isSelf(member) {
                            Text("(You)")
                                .font(.workSans(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let email = member.email {
                        Text(email)
                            .font(.workSans(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } trailing: {
            roleControl(member)
        }
        .contextMenu { memberMenu(member) }
        .penpotSwipeActions(id: member.id) {
            if isSelf(member) {
                if !(isOwner && members.count <= 1) {
                    PenpotSwipeAction("Leave Team", icon: .leave, isDestructive: true) { startLeave() }
                }
            } else if isAdmin && member.role != .owner {
                PenpotSwipeAction("Remove Member", icon: .delete, isDestructive: true) {
                    pendingConfirmation = .removeMember(member)
                }
            }
        }
    }

    /// Whether the current user may change `member`'s role: admins/owners can edit anyone
    /// except the owner and themselves (ownership transfer is a separate, owner-only act).
    private func canEditRole(of member: TeamMember) -> Bool {
        isAdmin && member.role != .owner && !isSelf(member)
    }

    @ViewBuilder
    private func roleControl(_ member: TeamMember) -> some View {
        if canEditRole(of: member) {
            Menu {
                PenpotMenuChoices(selection: roleBinding(for: member),
                                  options: TeamRole.assignable.map { (value: $0, label: Text($0.displayName)) })
                if isOwner {
                    Divider()
                    Button { pendingConfirmation = .transferOwnership(member) } label: {
                        Text("Transfer Ownership")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(member.role.displayName)
                    AppIcon.chevronDown.image(size: 10)
                }
                .font(.workSans(.subheadline))
                // The card row tints its trailing slot secondary; an editable role must
                // still read as tappable.
                .foregroundStyle(Color.penpotAccent)
            }
        } else {
            Text(member.role.displayName)
                .font(.workSans(.subheadline))
                .foregroundStyle(.secondary)
        }
    }

    private func roleBinding(for member: TeamMember) -> Binding<TeamRole> {
        Binding(get: { member.role },
                set: { newRole in
                    guard newRole != member.role else { return }
                    Task { await changeRole(member, to: newRole) }
                })
    }

    @ViewBuilder
    private func memberMenu(_ member: TeamMember) -> some View {
        if isSelf(member) {
            // A sole-member owner can't leave (the server rejects it) — delete the team instead.
            if !(isOwner && members.count <= 1) {
                Button(role: .destructive) { startLeave() } label: {
                    AppIcon.leave.destructiveLabel("Leave Team")
                }
            }
        } else if isAdmin && member.role != .owner {
            Button(role: .destructive) { pendingConfirmation = .removeMember(member) } label: {
                AppIcon.delete.destructiveLabel("Remove Member")
            }
        }
    }

    // MARK: Invitation rows

    private func invitationRow(_ invitation: TeamInvitation) -> some View {
        PenpotCardRow(showsChevron: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.email)
                    .font(.workSans(.subheadline))
                Text(invitation.teamRole.displayName)
                    .font(.workSans(.caption))
                    .foregroundStyle(.secondary)
            }
        } trailing: {
            if invitation.expired == true {
                Text("Expired")
                    .font(.workSans(.caption))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if isAdmin {
                Button { Task { await resend(invitation) } } label: {
                    AppIcon.send.label("Resend Invitation")
                }
                Menu {
                    PenpotMenuChoices(selection: invitationRoleBinding(invitation),
                                      options: TeamRole.assignable.map { (value: $0, label: Text($0.displayName)) })
                } label: {
                    AppIcon.edit.label("Change Role")
                }
                Button(role: .destructive) { pendingConfirmation = .deleteInvitation(invitation) } label: {
                    AppIcon.delete.destructiveLabel("Delete Invitation")
                }
            }
        }
        .penpotSwipeActions(id: invitation.id) {
            if isAdmin {
                PenpotSwipeAction("Resend Invitation", icon: .send) {
                    Task { await resend(invitation) }
                }
                PenpotSwipeAction("Delete Invitation", icon: .delete, isDestructive: true) {
                    pendingConfirmation = .deleteInvitation(invitation)
                }
            }
        }
    }

    private func invitationRoleBinding(_ invitation: TeamInvitation) -> Binding<TeamRole> {
        Binding(get: { invitation.teamRole },
                set: { newRole in
                    guard newRole != invitation.teamRole else { return }
                    Task { await changeInvitationRole(invitation, to: newRole) }
                })
    }

    // MARK: Confirmation alert (single enum-driven alert — two confirmationDialogs on one
    // view render as a broken popover on iPhone)

    private var confirmationAlert: Binding<Bool> {
        Binding(get: { pendingConfirmation != nil }, set: { if !$0 { pendingConfirmation = nil } })
    }

    private var confirmationTitle: Text {
        switch pendingConfirmation {
        case .removeMember: Text("Remove Member")
        case .deleteInvitation: Text("Delete Invitation")
        case .transferOwnership: Text("Transfer Ownership")
        case .leaveTeam: Text("Leave Team")
        case nil: Text(verbatim: "")
        }
    }

    @ViewBuilder
    private func confirmationButton(for confirmation: PendingConfirmation) -> some View {
        switch confirmation {
        case .removeMember(let member):
            Button("Remove", role: .destructive) { Task { await removeMember(member) } }
        case .deleteInvitation(let invitation):
            Button("Delete", role: .destructive) { Task { await deleteInvitation(invitation) } }
        case .transferOwnership(let member):
            Button("Transfer", role: .destructive) { Task { await changeRole(member, to: .owner) } }
        case .leaveTeam:
            Button("Leave", role: .destructive) { Task { await confirmLeave() } }
        }
    }

    private func confirmationMessage(for confirmation: PendingConfirmation) -> Text {
        switch confirmation {
        case .removeMember(let member):
            Text("“\(member.displayName)” will be removed from the team.")
        case .deleteInvitation(let invitation):
            Text("The invitation to “\(invitation.email)” will be deleted.")
        case .transferOwnership(let member):
            Text("“\(member.displayName)” will become the owner of this team. You will become an admin.")
        case .leaveTeam:
            Text("You will lose access to “\(team.displayName)”.")
        }
    }

    private var actionErrorAlert: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    // MARK: Actions

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let loadedMembers = client.teamMembers(teamID: team.id)
            // Invitations failing (e.g. an older server) must not blank the roster.
            async let loadedInvitations = try? client.teamInvitations(teamID: team.id)
            members = try await loadedMembers
            invitations = await loadedInvitations
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func changeRole(_ member: TeamMember, to role: TeamRole) async {
        guard let client = appState.client else { return }
        do {
            try await client.updateTeamMemberRole(teamID: team.id,
                                                  memberID: member.profileId ?? member.id,
                                                  role: role)
            await load()
        } catch { handleActionError(error) }
    }

    private func removeMember(_ member: TeamMember) async {
        guard let client = appState.client else { return }
        do {
            try await client.deleteTeamMember(teamID: team.id,
                                              memberID: member.profileId ?? member.id)
            await load()
        } catch { handleActionError(error) }
    }

    /// Re-sending is just re-creating: Penpot has no dedicated resend command, and this
    /// also un-expires an expired invitation.
    private func resend(_ invitation: TeamInvitation) async {
        guard let client = appState.client else { return }
        do {
            try await client.createTeamInvitations(teamID: team.id,
                                                   emails: [invitation.email],
                                                   role: invitation.teamRole)
            await load()
        } catch { handleActionError(error) }
    }

    private func changeInvitationRole(_ invitation: TeamInvitation, to role: TeamRole) async {
        guard let client = appState.client else { return }
        do {
            try await client.updateTeamInvitationRole(teamID: team.id,
                                                      email: invitation.email,
                                                      role: role)
            await load()
        } catch { handleActionError(error) }
    }

    private func deleteInvitation(_ invitation: TeamInvitation) async {
        guard let client = appState.client else { return }
        do {
            try await client.deleteTeamInvitation(teamID: team.id, email: invitation.email)
            await load()
        } catch { handleActionError(error) }
    }

    private func startLeave() {
        if isOwner && members.count > 1 {
            // The owner must hand the team over before leaving.
            showingOwnerPicker = true
        } else {
            pendingConfirmation = .leaveTeam
        }
    }

    private func candidateOwners() -> [MoveTarget] {
        sortedMembers
            .filter { !isSelf($0) }
            .map { MoveTarget(id: $0.profileId ?? $0.id, name: $0.displayName) }
    }

    private func confirmLeave() async {
        do {
            try await leave(reassignTo: nil)
        } catch { handleActionError(error) }
    }

    private func leave(reassignTo: String?) async throws {
        guard let client = appState.client else { return }
        try await client.leaveTeam(id: team.id, reassignTo: reassignTo)
        if let onTeamLeft {
            onTeamLeft()
        } else {
            dismiss()
        }
    }

    private func handleActionError(_ error: Error) {
        if case PenpotError.unauthorized = error {
            appState.logout()
        } else {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
