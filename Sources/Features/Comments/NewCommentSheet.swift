import SwiftUI

/// Composes a brand-new comment thread at a tapped position on a board.
struct NewCommentSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let fileID: String
    let pageID: String
    let frameID: String
    let position: Point
    /// Enables the @mention autocomplete; nil degrades to a plain text field.
    var teamID: String? = nil
    var onCreated: () -> Void = {}

    @State private var content: String = ""
    @State private var mentions: [CommentMention.Pick] = []
    @State private var isSending = false
    @State private var errorMessage: String?

    private var trimmed: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The wire-format content (`@[Name](id)` markup) actually sent to the server.
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
                        // The composer brings its own box — no card behind it.
                        MentionComposer(placeholder: "Write a comment…",
                                        text: $content,
                                        mentions: $mentions,
                                        teamID: teamID,
                                        lineLimit: 3...8)
                    }
                    if let errorMessage {
                        PenpotCard {
                            PenpotCardRow(showsChevron: false) {
                                Text(errorMessage)
                                    .foregroundStyle(Color.penpotDangerText)
                                    .font(.workSans(.callout))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .penpotPageBackground()
            .navigationTitle("New Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") { Task { await post() } }
                        .disabled(trimmed.isEmpty || isSending
                                  || serialized.count > CommentMention.maxContentLength)
                }
            }
        }
        .interactiveDismissDisabled(isSending)
    }

    private func post() async {
        guard let client = appState.client, !trimmed.isEmpty else { return }
        isSending = true
        errorMessage = nil
        do {
            try await client.createCommentThread(fileID: fileID,
                                                 pageID: pageID,
                                                 frameID: frameID,
                                                 position: position,
                                                 content: serialized)
            onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }
}
