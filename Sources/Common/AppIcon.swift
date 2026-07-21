import SwiftUI

/// Semantic icon set for the app UI.
///
/// Prefers Penpot's own icons — bundled as tintable **template** vector assets under
/// `Assets.xcassets/PenpotIcons/` (see `Scripts/fetch-penpot-icons.sh`) — so the app matches
/// Penpot's web UI. A handful of icons have no Penpot equivalent and fall back to SF
/// Symbols. Everything routes through this one enum so any icon can be remapped in one place.
///
/// Penpot assets are fixed-size vectors: unlike SF Symbols they don't auto-scale to the
/// surrounding font, so `image(size:)` gives both branches an explicit, matching size.
enum AppIcon {
    // Penpot-backed
    case add, delete, folder, user, lock, info, document, copy, text, library,
         comments, tick, warning, expand, externalLink, help, image, pin, board,
         more, moreInline, gridLayout, listLayout
    // SF Symbol fallback (no Penpot equivalent)
    case edit, notifications, key, appearance, subscription, camera, teams, send,
         chevronDown, duplicate, restore, unresolve, unpin,
         addComment, closeFilled, template, download, unpublish

    /// Penpot template-asset name, or `nil` when we fall back to an SF Symbol.
    private var penpotAsset: String? {
        switch self {
        case .add:          "ic-add"
        case .delete:       "ic-delete"
        case .folder:       "ic-folder"
        case .user:         "ic-user"
        case .lock:         "ic-lock"
        case .info:         "ic-info"
        case .document:     "ic-document"
        case .copy:         "ic-clipboard"
        case .text:         "ic-text"
        case .library:      "ic-library"
        case .comments:     "ic-comments"
        case .tick:         "ic-tick"
        case .warning:      "ic-msg-warning"
        case .expand:       "ic-expand"
        case .externalLink: "ic-open-link"
        case .help:         "ic-help"
        case .image:        "ic-img"
        case .pin:          "ic-pin"
        case .board:        "ic-board"
        case .more, .moreInline: "ic-menu"
        case .gridLayout:   "ic-view-as-icons"
        case .listLayout:   "ic-view-as-list"
        default:            nil
        }
    }

    /// SF Symbol name used when there's no Penpot equivalent.
    private var systemName: String {
        switch self {
        case .edit:         "pencil"
        case .notifications: "bell"
        case .key:          "key"
        case .appearance:   "paintbrush"
        case .subscription: "creditcard"
        case .camera:       "camera.fill"
        case .teams:        "person.3"
        case .send:         "paperplane.fill"
        case .chevronDown:  "chevron.down"
        case .duplicate:    "plus.square.on.square"
        case .restore:      "arrow.uturn.backward"
        case .unresolve:    "arrow.uturn.backward.circle"
        case .unpin:        "pin.slash"
        case .addComment:   "plus.bubble"
        case .closeFilled:  "xmark.circle.fill"
        case .template:     "square.grid.2x2"
        case .download:     "square.and.arrow.down"
        case .unpublish:    "book.closed"
        default:            ""   // Penpot-backed cases never reach here
        }
    }

    /// Default size for inline / toolbar / list-row icons.
    static let defaultSize: CGFloat = 18

    /// The icon as a tinted view at an explicit size.
    @ViewBuilder
    func image(size: CGFloat) -> some View {
        if let asset = penpotAsset {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: systemName)
                .font(.system(size: size))
        }
    }

    /// The icon at the default size — the common `Image(systemName:)` replacement.
    var image: some View { image(size: AppIcon.defaultSize) }

    /// A `Label` pairing the icon with a title — replaces `Label(_, systemImage:)`.
    func label(_ title: LocalizedStringKey, size: CGFloat = AppIcon.defaultSize) -> some View {
        Label { Text(title) } icon: { image(size: size) }
    }
}
