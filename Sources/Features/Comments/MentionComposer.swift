import SwiftUI

/// A comment text field with Penpot-style @mention autocomplete. Typing `@` at the end of
/// the text opens an inline list of team members; picking one inserts `@Fullname ` and
/// records a ``CommentMention/Pick`` so the sheet can serialize the display text to wire
/// markup on send. Without a team id — or when the member fetch fails — it degrades to a
/// plain text field; hand-typed `@Name` then simply stays plain text, like on the web.
struct MentionComposer: View {
    @Environment(AppState.self) private var appState

    let placeholder: LocalizedStringKey
    @Binding var text: String
    @Binding var mentions: [CommentMention.Pick]
    var teamID: String? = nil
    /// Renders suggestions above the field (for bottom-anchored composers).
    var suggestionsAbove: Bool = false
    var lineLimit: ClosedRange<Int> = 1...4
    var usesRoundedBorder: Bool = false

    @State private var members: [TeamMember] = []
    @State private var didLoadMembers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if suggestionsAbove { suggestionList }
            field
            if !suggestionsAbove { suggestionList }
            counter
        }
        .task(id: teamID) { await loadMembersIfNeeded() }
    }

    @ViewBuilder
    private var field: some View {
        if usesRoundedBorder {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(lineLimit)
                .textFieldStyle(.roundedBorder)
        } else {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(lineLimit)
        }
    }

    // MARK: Suggestions

    /// The active mention query: the text ends in `@…` whose `@` starts a word.
    private var activeQuery: String? {
        guard !members.isEmpty, let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex {
            let preceding = text[text.index(before: at)]
            guard preceding.isWhitespace || preceding.isNewline else { return nil }
        }
        let query = String(text[text.index(after: at)...])
        guard query.count <= 40, !query.contains("\n"), !query.contains("[") else { return nil }
        // Right after a pick the text ends with "@Fullname " — don't reopen for it.
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if query.hasSuffix(" "), members.contains(where: { $0.fullname == trimmed }) { return nil }
        return query
    }

    private var suggestions: [TeamMember] {
        guard let query = activeQuery else { return [] }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = needle.isEmpty ? members : members.filter {
            ($0.fullname?.lowercased().contains(needle) ?? false)
                || ($0.email?.lowercased().contains(needle) ?? false)
        }
        return Array(pool.prefix(8))
    }

    @ViewBuilder
    private var suggestionList: some View {
        let items = suggestions
        if !items.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { member in
                        Button { select(member) } label: {
                            HStack(spacing: 8) {
                                PenpotAvatar(photoID: member.photoId,
                                             baseURL: appState.client?.baseURL,
                                             initials: member.displayName, size: 24)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(member.displayName)
                                        .font(.workSans(.subheadline))
                                    if let email = member.email {
                                        Text(email)
                                            .font(.workSans(.caption2))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mention a team member")
                    }
                }
            }
            .frame(maxHeight: 168)
        }
    }

    private func select(_ member: TeamMember) {
        guard let at = text.lastIndex(of: "@") else { return }
        let name = member.fullname ?? member.email ?? ""
        guard !name.isEmpty else { return }
        text = String(text[..<at]) + "@\(name) "
        let pick = CommentMention.Pick(name: name, id: member.profileId ?? member.id)
        if !mentions.contains(pick) { mentions.append(pick) }
    }

    // MARK: Length guard

    /// Shows the serialized length once it approaches the server's 750-char cap — the
    /// markup is longer than the visible text, so the user can't see it coming otherwise.
    @ViewBuilder
    private var counter: some View {
        let length = CommentMention.serialize(display: text, mentions: mentions).count
        if length > 600 {
            Text(verbatim: "\(length)/\(CommentMention.maxContentLength)")
                .font(.workSans(.caption2))
                .foregroundStyle(length > CommentMention.maxContentLength ? Color.red : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func loadMembersIfNeeded() async {
        guard !didLoadMembers, let teamID, let client = appState.client else { return }
        didLoadMembers = true
        // Failure just leaves the list empty: composing degrades to plain text.
        members = (try? await client.teamMembers(teamID: teamID)) ?? []
    }
}
