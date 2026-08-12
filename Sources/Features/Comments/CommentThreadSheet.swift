import SwiftUI
import UIKit

/// Reads a comment thread, lets the user reply and resolve/reopen it.
struct CommentThreadSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let fileID: String
    let thread: CommentThread
    var onChange: () -> Void = {}

    /// Enables @mention autocomplete in the reply/edit composers. Falls back to the
    /// thread's own `teamId` (joined by the server on thread queries), which covers the
    /// inbox path where the caller doesn't know the team.
    private let teamID: String?

    /// Seeded by callers that already loaded them; fetched on demand otherwise.
    @State private var profiles: [String: Profile]
    @State private var comments: [Comment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reply: String = ""
    @State private var replyMentions: [CommentMention.Pick] = []
    @State private var isSending = false
    @State private var editingComment: Comment?
    @State private var deletingComment: Comment?
    @State private var showDeleteThread = false
    @State private var isResolved: Bool

    private var isThreadOwner: Bool {
        thread.ownerId != nil && thread.ownerId == appState.profile?.id
    }

    init(fileID: String, thread: CommentThread, profiles: [String: Profile] = [:],
         teamID: String? = nil, onChange: @escaping () -> Void = {}) {
        self.fileID = fileID
        self.thread = thread
        self.teamID = teamID ?? thread.teamId
        self.onChange = onChange
        _profiles = State(initialValue: profiles)
        _isResolved = State(initialValue: thread.isResolved == true)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                commentsList
                Divider()
                composer
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await toggleResolved() }
                        } label: {
                            (isResolved ? AppIcon.unresolve : AppIcon.tick).label(isResolved ? "Reopen" : "Resolve")
                        }
                        if isThreadOwner {
                            Button(role: .destructive) {
                                showDeleteThread = true
                            } label: {
                                AppIcon.delete.destructiveLabel("Delete Thread")
                            }
                        }
                    } label: {
                        AppIcon.more.image
                    }
                    .accessibilityLabel("Thread actions")
                }
            }
            .task { await load() }
            .sheet(item: $editingComment) { comment in
                EditCommentSheet(initialContent: comment.content ?? "", teamID: teamID) { newContent in
                    await edit(comment, content: newContent)
                }
            }
            .confirmationDialog("Delete this comment?",
                                isPresented: Binding(get: { deletingComment != nil },
                                                     set: { if !$0 { deletingComment = nil } }),
                                titleVisibility: .visible,
                                presenting: deletingComment) { comment in
                Button("Delete", role: .destructive) { Task { await delete(comment) } }
                Button("Cancel", role: .cancel) { deletingComment = nil }
            }
            .confirmationDialog("Delete this thread and all of its comments?",
                                isPresented: $showDeleteThread, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await deleteThread() } }
                Button("Cancel", role: .cancel) {}
            }
            // Surface mutation errors even when the list is non-empty (the inline
            // ErrorStateView only covers the initial-load-empty case).
            .alert("Something went wrong",
                   isPresented: Binding(get: { errorMessage != nil && !comments.isEmpty },
                                        set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var commentsList: some View {
        if isLoading && comments.isEmpty {
            LoadingView(message: "Loading comments…")
        } else if let errorMessage, comments.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment,
                                   authorName: authorName(of: comment),
                                   canModify: comment.ownerId != nil && comment.ownerId == appState.profile?.id,
                                   onEdit: { editingComment = comment },
                                   onDelete: { deletingComment = comment })
                    }
                }
                .padding()
            }
        }
    }

    /// The thread carries its owner's name, which covers the common case before (or without)
    /// the participant profiles being fetched.
    private func authorName(of comment: Comment) -> String {
        if let profile = profiles[comment.ownerId ?? ""] { return profile.displayName }
        if comment.ownerId != nil, comment.ownerId == thread.ownerId,
           let fullname = thread.ownerFullname { return fullname }
        return "Unknown"
    }

    /// The wire-format reply (`@[Name](id)` markup) actually sent to the server.
    private var serializedReply: String {
        CommentMention.serialize(display: reply.trimmingCharacters(in: .whitespacesAndNewlines),
                                 mentions: replyMentions)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MentionComposer(placeholder: "Reply…",
                            text: $reply,
                            mentions: $replyMentions,
                            teamID: teamID,
                            suggestionsAbove: true,
                            lineLimit: 1...4)
            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView()
                } else {
                    AppIcon.send.image
                }
            }
            .buttonStyle(.penpot(.ghost, size: .compact))
            .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
                      || serializedReply.count > CommentMention.maxContentLength)
        }
        .padding()
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            comments = try await client.comments(threadID: thread.id)
            if profiles.isEmpty {
                profiles = (try? await client.commentProfiles(fileID: fileID)) ?? [:]
            }
            try? await client.markThreadRead(id: thread.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func send() async {
        guard let client = appState.client else { return }
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        errorMessage = nil
        do {
            try await client.createComment(threadID: thread.id, content: serializedReply)
            reply = ""
            replyMentions = []
            await load()
            onChange()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }

    private func toggleResolved() async {
        guard let client = appState.client else { return }
        let newValue = !isResolved
        errorMessage = nil
        do {
            try await client.setThreadResolved(id: thread.id, isResolved: newValue)
            isResolved = newValue
            onChange()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Returns true on success so the edit sheet only dismisses when the edit was saved.
    private func edit(_ comment: Comment, content: String) async -> Bool {
        guard let client = appState.client else { return false }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        errorMessage = nil
        do {
            try await client.updateComment(id: comment.id, content: text)
            await load()
            onChange()
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func delete(_ comment: Comment) async {
        guard let client = appState.client else { return }
        deletingComment = nil
        errorMessage = nil
        do {
            try await client.deleteComment(id: comment.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        onChange()
        // Refresh. Deleting a thread's first comment removes the whole thread, so a
        // not-found here means the thread is gone — but a transient failure must NOT be
        // mistaken for an emptied thread.
        do {
            let remaining = try await client.comments(threadID: thread.id)
            comments = remaining
            if remaining.isEmpty { dismiss() }
        } catch PenpotError.server(404, _) {
            dismiss()
        } catch {
            comments.removeAll { $0.id == comment.id }
            if comments.isEmpty { dismiss() }
        }
    }

    private func deleteThread() async {
        guard let client = appState.client else { return }
        errorMessage = nil
        do {
            try await client.deleteCommentThread(id: thread.id)
            onChange()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct CommentRow: View {
    let comment: Comment
    let authorName: String
    var canModify: Bool = false
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(authorName).font(.workSans(.subheadline, weight: .bold))
                Spacer()
                Text(PenpotDate.relative(from: comment.createdAt, locale: locale))
                    .font(.workSans(.caption))
                    .foregroundStyle(.secondary)
                if canModify {
                    Menu {
                        Button { onEdit() } label: { AppIcon.edit.label("Edit") }
                        Button(role: .destructive) { onDelete() } label: { AppIcon.delete.destructiveLabel("Delete") }
                    } label: {
                        AppIcon.moreInline.image
                            .font(.workSans(.footnote))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Comment actions")
                }
            }
            Text(CommentMention.attributedString(from: comment.content ?? ""))
                .font(.workSans(.body))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Sheet for editing an existing comment's text. Existing mention markup is unpacked to
/// display text for editing and re-serialized on save, so mentions survive the roundtrip.
private struct EditCommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var mentions: [CommentMention.Pick]
    @State private var isSaving = false
    private let teamID: String?
    /// Receives the wire-format (`@[Name](id)`) content.
    private let onSave: (String) async -> Bool

    init(initialContent: String, teamID: String?, onSave: @escaping (String) async -> Bool) {
        let display = CommentMention.displayRepresentation(of: initialContent)
        _text = State(initialValue: display.text)
        _mentions = State(initialValue: display.mentions)
        self.teamID = teamID
        self.onSave = onSave
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var serialized: String {
        CommentMention.serialize(display: trimmed, mentions: mentions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comment")
                            .font(.workSans(.caption, weight: .semibold))
                            .textCase(.uppercase)
                            .kerning(0.5)
                            .foregroundStyle(Color.penpotIconGray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        MentionComposer(placeholder: "Edit comment…",
                                        text: $text,
                                        mentions: $mentions,
                                        teamID: teamID,
                                        lineLimit: 3...8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .penpotPageBackground()
            .navigationTitle("Edit Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            let ok = await onSave(serialized)
                            isSaving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(trimmed.isEmpty || isSaving
                              || serialized.count > CommentMention.maxContentLength)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }
}
