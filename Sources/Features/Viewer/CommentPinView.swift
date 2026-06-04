import SwiftUI

/// A map-style pin marking a comment thread on the board.
struct CommentPinView: View {
    let thread: CommentThread

    private var isResolved: Bool { thread.isResolved == true }
    private var hasUnread: Bool { (thread.countUnreadComments ?? 0) > 0 }

    var body: some View {
        ZStack {
            Circle()
                .fill(isResolved ? Color.gray : Color.accentColor)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(radius: 2)
            Image(systemName: isResolved ? "checkmark" : "bubble.left.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .topTrailing) {
            if hasUnread {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.white, lineWidth: 1))
                    .offset(x: 2, y: -2)
            }
        }
    }
}
