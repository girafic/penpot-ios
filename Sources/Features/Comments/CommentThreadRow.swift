import SwiftUI

/// A comment-thread preview row: author avatar + name, snippet (with highlighted
/// mentions), thread number, comment count and unread badge. Shared by the inbox and
/// the per-file thread list.
struct CommentThreadRow: View {
    let thread: CommentThread
    let baseURL: URL?
    /// Fills author name/avatar when the row's thread carries no joined owner fields
    /// (per-file queries don't join them the way the unread query does).
    var fallbackProfile: Profile? = nil

    @Environment(\.locale) private var locale

    private var authorName: String {
        thread.ownerFullname ?? fallbackProfile?.displayName ?? .appLocalized("Unknown")
    }

    private var photoID: String? { thread.ownerPhotoId ?? fallbackProfile?.photoId }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(authorName)
                        .font(.workSans(.subheadline, weight: .bold))
                        .lineLimit(1)
                    if thread.isResolved == true {
                        AppIcon.tick.image(size: 12)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Resolved")
                    }
                    Spacer(minLength: 0)
                    Text(PenpotDate.relative(from: thread.modifiedAt ?? thread.createdAt, locale: locale))
                        .font(.workSans(.caption))
                        .foregroundStyle(.secondary)
                }
                Text(CommentMention.attributedString(from: thread.content ?? ""))
                    .font(.workSans(.subheadline))
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
                .font(.workSans(.caption))
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
                .font(.workSans(.caption2, weight: .bold))
                .foregroundStyle(Color.penpotOnAccent)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.penpotAccent, in: Capsule())
        }
    }

    @ViewBuilder
    private var avatar: some View {
        let placeholder = Circle().fill(.quaternary).overlay(
            AppIcon.user.image(size: 14).foregroundStyle(.secondary))

        if let photoID, let baseURL {
            RemoteImage(mediaID: photoID, baseURL: baseURL, contentMode: .fill) { placeholder }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            placeholder.frame(width: 32, height: 32)
        }
    }
}
