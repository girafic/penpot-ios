import SwiftUI

/// The per-file thread list opened from a board — web-sidebar parity: filtered thread
/// previews split into the current board and the rest of the file. Picking a thread
/// dismisses and hands it back so the board can jump to its pin.
struct CommentThreadListSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let threads: [CommentThread]
    /// Comment-author profiles of the file, for rows whose thread lacks joined owner fields.
    let profiles: [String: Profile]
    let boardID: String
    /// Called with the picked thread after the sheet dismisses.
    var onSelect: (CommentThread) -> Void = { _ in }

    private var filtered: [CommentThread] {
        settings.commentFilters.apply(threads, profileID: appState.profile?.id)
            .sorted { ($0.seqn ?? 0) < ($1.seqn ?? 0) }
    }

    private var currentBoard: [CommentThread] { filtered.filter { $0.frameId == boardID } }
    private var otherBoards: [CommentThread] { filtered.filter { $0.frameId != boardID } }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Comments in this file")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        CommentFilterMenu()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            EmptyStateView(title: "No comments match the filters", icon: .comments) {
                if settings.commentFilters.isNarrowing || !settings.showResolvedComments {
                    Button("Reset filters") {
                        settings.commentFilterMode = .all
                        settings.showResolvedComments = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            List {
                if !currentBoard.isEmpty {
                    Section("This board") { rows(currentBoard) }
                }
                if !otherBoards.isEmpty {
                    Section("Other boards") { rows(otherBoards) }
                }
            }
        }
    }

    private func rows(_ threads: [CommentThread]) -> some View {
        ForEach(threads) { thread in
            Button {
                dismiss()
                onSelect(thread)
            } label: {
                CommentThreadRow(thread: thread, baseURL: appState.client?.baseURL,
                                 fallbackProfile: profiles[thread.ownerId ?? ""])
            }
            .buttonStyle(.plain)
        }
    }
}
