import SwiftUI

/// Which comment threads to show — the iOS mirror of the web viewer's filter menu
/// ("All / Only yours / Mentions" plus the "Show resolved comments" toggle).
enum CommentFilterMode: String, CaseIterable, Identifiable {
    case all
    case yours
    case mentions

    var id: String { rawValue }
}

/// Client-side thread filtering with the web client's exact semantics: resolved threads
/// are hidden unless opted in; "yours" means the current profile participated (owner as
/// fallback for payloads without `participants`); "mentions" means the current profile is
/// mentioned. With no known profile id, yours/mentions match nothing.
struct CommentFilters {
    var mode: CommentFilterMode
    var showResolved: Bool

    /// True when the mode narrows beyond the default — drives the filled filter icon.
    var isNarrowing: Bool { mode != .all }

    func apply(_ threads: [CommentThread], profileID: String?) -> [CommentThread] {
        threads.filter { thread in
            if !showResolved && thread.isResolved == true { return false }
            switch mode {
            case .all:
                return true
            case .yours:
                guard let profileID else { return false }
                if let participants = thread.participants { return participants.contains(profileID) }
                return thread.ownerId == profileID
            case .mentions:
                guard let profileID else { return false }
                return thread.mentions?.contains(profileID) == true
            }
        }
    }
}

/// The comment filter menu (mode picker + resolved toggle), bound to ``AppSettings`` so
/// the choice sticks across boards and launches. Used in the board toolbar and the
/// per-file thread list.
struct CommentFilterMenu: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Menu {
            PenpotMenuChoices(selection: $settings.commentFilterMode, options: [
                (value: CommentFilterMode.all, label: Text("All comments")),
                (value: CommentFilterMode.yours, label: Text("Only yours")),
                (value: CommentFilterMode.mentions, label: Text("Mentions")),
            ])
            Divider()
            Button { settings.showResolvedComments.toggle() } label: {
                PenpotMenuCheckLabel(label: Text("Show resolved comments"),
                                     isOn: settings.showResolvedComments)
            }
        } label: {
            (settings.commentFilters.isNarrowing ? AppIcon.filterActive : AppIcon.filter).image
        }
        .accessibilityLabel("Filter comments")
    }
}
