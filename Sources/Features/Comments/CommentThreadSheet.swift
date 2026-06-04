import SwiftUI
import UIKit

/// Reads a comment thread, lets the user reply and resolve/reopen it.
struct CommentThreadSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let fileID: String
    let thread: CommentThread
    let profiles: [String: Profile]
    var onChange: () -> Void = {}

    @State private var comments: [Comment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reply: String = ""
    @State private var isSending = false
    @State private var isResolved: Bool

    init(fileID: String, thread: CommentThread, profiles: [String: Profile],
         onChange: @escaping () -> Void = {}) {
        self.fileID = fileID
        self.thread = thread
        self.profiles = profiles
        self.onChange = onChange
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
                    Button {
                        Task { await toggleResolved() }
                    } label: {
                        Label(isResolved ? "Reopen" : "Resolve",
                              systemImage: isResolved ? "arrow.uturn.backward.circle" : "checkmark.circle")
                    }
                }
            }
            .task { await load() }
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
                                   authorName: profiles[comment.ownerId ?? ""]?.displayName ?? "Unknown")
                    }
                }
                .padding()
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply…", text: $reply, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding()
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            comments = try await client.comments(threadID: thread.id)
            try? await client.markThreadRead(id: thread.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func send() async {
        guard let client = appState.client else { return }
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        do {
            try await client.createComment(threadID: thread.id, content: text)
            reply = ""
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
        do {
            try await client.setThreadResolved(id: thread.id, isResolved: newValue)
            isResolved = newValue
            onChange()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct CommentRow: View {
    let comment: Comment
    let authorName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(authorName).font(.subheadline).bold()
                Spacer()
                Text(PenpotDate.relative(from: comment.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(comment.content ?? "")
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
