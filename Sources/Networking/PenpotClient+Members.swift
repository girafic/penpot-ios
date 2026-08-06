import Foundation

/// Team membership and invitation commands. Request params are kebab-case; responses are
/// camelCase. Roles travel as raw ``TeamRole`` strings; `member-id` params take the
/// member's *profile* id.
extension PenpotClient {

    /// Pending invitations of a team (`get-team-invitations`). Any member may list them.
    func teamInvitations(teamID: String) async throws -> [TeamInvitation] {
        try await query("get-team-invitations", params: ["team-id": teamID], as: [TeamInvitation].self)
    }

    /// Invites email addresses with a single role (`create-team-invitations`). Admin-only;
    /// the server caps one request at 25 invitations. Addressees who are already members
    /// are silently skipped — the returned `total` is the count actually created. There is
    /// no separate resend command: re-inviting an existing (or expired) invitation
    /// re-issues and re-mails it.
    @discardableResult
    func createTeamInvitations(teamID: String, emails: [String], role: TeamRole) async throws -> InvitationResult {
        try await mutation("create-team-invitations", params: [
            "team-id": teamID,
            "emails": emails,
            "role": role.rawValue,
        ], as: InvitationResult.self)
    }

    /// Changes the role of a pending invitation (`update-team-invitation-role`). Admin-only.
    func updateTeamInvitationRole(teamID: String, email: String, role: TeamRole) async throws {
        _ = try await mutation("update-team-invitation-role", params: [
            "team-id": teamID,
            "email": email,
            "role": role.rawValue,
        ], as: EmptyResponse.self)
    }

    /// Revokes a pending invitation (`delete-team-invitation`). Admin-only.
    func deleteTeamInvitation(teamID: String, email: String) async throws {
        _ = try await mutation("delete-team-invitation",
                               params: ["team-id": teamID, "email": email],
                               as: EmptyResponse.self)
    }

    /// Changes a member's role (`update-team-member-role`). Granting `.owner` transfers
    /// ownership — the previous owner becomes an admin — and is allowed for the owner only;
    /// admins can neither touch the owner nor promote to owner.
    func updateTeamMemberRole(teamID: String, memberID: String, role: TeamRole) async throws {
        _ = try await mutation("update-team-member-role", params: [
            "team-id": teamID,
            "member-id": memberID,
            "role": role.rawValue,
        ], as: EmptyResponse.self)
    }

    /// Removes a member from a team (`delete-team-member`). Admin-only; removing oneself is
    /// rejected — use ``leaveTeam(id:reassignTo:)`` instead.
    func deleteTeamMember(teamID: String, memberID: String) async throws {
        _ = try await mutation("delete-team-member",
                               params: ["team-id": teamID, "member-id": memberID],
                               as: EmptyResponse.self)
    }

    /// Leaves a team (`leave-team`). When the leaver owns the team and other members
    /// remain, `reassignTo` (the new owner's profile id) is required by the server.
    func leaveTeam(id: String, reassignTo: String? = nil) async throws {
        var params: [String: Any] = ["id": id]
        if let reassignTo { params["reassign-to"] = reassignTo }
        _ = try await mutation("leave-team", params: params, as: EmptyResponse.self)
    }
}
