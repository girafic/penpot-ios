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
                .penpotPageBackground()
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
                    .buttonStyle(.penpot(.secondary, size: .compact))
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if !currentBoard.isEmpty {
                        section("This board", threads: currentBoard)
                    }
                    if !otherBoards.isEmpty {
                        section("Other boards", threads: otherBoards)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func section(_ title: LocalizedStringKey, threads: [CommentThread]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.workSans(.caption, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(Color.penpotIconGray)
                .frame(maxWidth: .infinity, alignment: .leading)
            PenpotCard { rows(threads) }
        }
    }

    @ViewBuilder
    private func rows(_ threads: [CommentThread]) -> some View {
        ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
            Button {
                dismiss()
                onSelect(thread)
            } label: {
                CommentThreadRow(thread: thread, baseURL: appState.client?.baseURL,
                                 fallbackProfile: profiles[thread.ownerId ?? ""])
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if index < threads.count - 1 {
                PenpotCardDivider()
            }
        }
    }
}
