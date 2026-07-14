import SwiftUI

/// The comment inbox: every thread across the user's teams that still has unread comments,
/// grouped by file. Penpot only exposes unread threads team-wide, so — like the web
/// dashboard — read threads are reachable from inside their file, not from here.
struct CommentsInboxView: View {
    @Environment(AppState.self) private var appState

    let teams: [Team]
    /// Owned by ``TeamsView`` so its unread badge stays in step with what the inbox shows.
    @Binding var threads: [CommentThread]

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selected: CommentThread?
    @State private var isMarkingAllRead = false

    var body: some View {
        content
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !threads.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark All Read") { Task { await markAllRead() } }
                            .disabled(isMarkingAllRead)
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            // Reading a thread marks it read, so re-sync once the sheet is gone rather than
            // pulling it out from under the open sheet.
            .sheet(item: $selected, onDismiss: { Task { await load() } }) { thread in
                if let fileID = thread.fileId {
                    CommentThreadSheet(fileID: fileID, thread: thread)
                }
            }
            // The inline ErrorStateView only covers an empty list; surface failures
            // (e.g. "Mark All Read") that happen while threads are on screen.
            .alert("Something went wrong",
                   isPresented: Binding(get: { errorMessage != nil && !threads.isEmpty },
                                        set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && threads.isEmpty {
            LoadingView(message: "Loading comments…")
        } else if let errorMessage, threads.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if threads.isEmpty {
            EmptyStateView(title: "No unread comments",
                           systemImage: "checkmark.bubble",
                           description: "New comments on your team's files show up here.")
        } else {
            List {
                ForEach(fileGroups) { group in
                    Section(group.name) {
                        ForEach(group.threads) { thread in
                            Button { selected = thread } label: { row(thread) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func row(_ thread: CommentThread) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(for: thread)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(thread.ownerFullname ?? "Unknown")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(PenpotDate.relative(from: thread.modifiedAt ?? thread.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(thread.content ?? "")
                    .font(.subheadline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if let seqn = thread.seqn {
                        Text("#\(seqn)")
                    }
                    // Explicit plural entry in the catalog ("%lld comments") — the automatic
                    // inflect engine can't be trusted for German.
                    Text("\(thread.countComments ?? 0) comments")
                    Spacer(minLength: 0)
                    unreadBadge(count: thread.unreadCount)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func unreadBadge(count: Int) -> some View {
        if count > 0 {
            Text("\(count) new")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.accentColor, in: Capsule())
        }
    }

    @ViewBuilder
    private func avatar(for thread: CommentThread) -> some View {
        let placeholder = Circle().fill(.quaternary).overlay(
            Image(systemName: "person.fill").font(.caption).foregroundStyle(.secondary))

        if let photoId = thread.ownerPhotoId, let baseURL = appState.client?.baseURL {
            RemoteImage(mediaID: photoId, baseURL: baseURL, contentMode: .fill) { placeholder }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            placeholder.frame(width: 32, height: 32)
        }
    }

    /// Threads grouped by file, files ordered by their most recent thread.
    private var fileGroups: [FileGroup] {
        Dictionary(grouping: threads) { $0.fileId ?? "" }
            .map { fileID, threads in
                FileGroup(id: fileID, name: threads.first?.fileName ?? "Untitled file", threads: threads)
            }
            .sorted { lhs, rhs in lhs.latest > rhs.latest }
    }

    private struct FileGroup: Identifiable {
        let id: String
        let name: String
        let threads: [CommentThread]

        /// `threads` arrives newest-first from the client.
        var latest: Date { PenpotDate.sortKey(threads.first?.modifiedAt ?? threads.first?.createdAt) }
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            threads = try await client.unreadCommentThreads(teams: teams)
        } catch PenpotError.unauthorized {
            appState.logout()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func markAllRead() async {
        guard let client = appState.client else { return }
        isMarkingAllRead = true
        errorMessage = nil
        do {
            try await client.markThreadsRead(ids: threads.map(\.id))
            threads = []
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isMarkingAllRead = false
    }
}
