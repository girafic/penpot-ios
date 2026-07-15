import SwiftUI

/// Composes a brand-new comment thread at a tapped position on a board.
struct NewCommentSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let fileID: String
    let pageID: String
    let frameID: String
    let position: Point
    var onCreated: () -> Void = {}

    @State private var content: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var trimmed: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Comment") {
                    TextField("Write a comment…", text: $content, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.workSans(.callout))
                    }
                }
            }
            .navigationTitle("New Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") { Task { await post() } }
                        .disabled(trimmed.isEmpty || isSending)
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
                                                 content: trimmed)
            onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }
}
