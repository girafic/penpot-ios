import SwiftUI

/// Semantic icon set for the app UI.
///
/// Every icon is a Penpot-style template vector asset under `Assets.xcassets/PenpotIcons/`
/// (built by `Scripts/fetch-penpot-icons.sh`), so the app matches Penpot's web UI and never
/// falls back to SF Symbols. Most come straight from Penpot's icon set; the few Penpot
/// doesn't ship are drawn in its style in `Scripts/penpot-icons-extra/`. Everything routes
/// through this one enum so any icon can be remapped in one place.
///
/// The assets are fixed-size vectors: unlike SF Symbols they don't auto-scale to the
/// surrounding font, so `image(size:)` gives every icon an explicit size.
enum AppIcon {
    case add, delete, folder, user, lock, info, document, copy, text, library,
         comments, tick, warning, expand, externalLink, help, image, pin, board,
         more, moreInline, gridLayout, listLayout, history, recent,
         edit, notifications, key, appearance, subscription, camera, teams, send,
         chevronDown, chevronRight, duplicate, restore, unresolve, unpin,
         addComment, closeFilled, template, download, unpublish,
         leave, play, share, filter, filterActive, mention, search

    /// Template-asset name. `penpot-icons-extra` marks the ones drawn for the app.
    var assetName: String {
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
        case .history:      "ic-history"
        case .recent:       "ic-clock"
        case .edit:         "ic-curve"            // Penpot's pencil
        case .chevronDown:  "ic-arrow-down"       // Penpot's select arrow
        case .chevronRight: "ic-arrow-right"
        case .duplicate:    "ic-files"
        case .restore, .unresolve: "ic-reload"
        case .closeFilled:  "ic-close"
        case .download:     "ic-download"
        case .leave:        "ic-exit"
        case .play:         "ic-play"
        case .share:        "ic-share"
        case .filter:       "ic-filter"
        case .mention:      "ic-at"
        case .search:       "ic-search"
        // penpot-icons-extra
        case .notifications: "ic-bell"
        case .key:          "ic-key"
        case .appearance:   "ic-contrast"
        case .subscription: "ic-credit-card"
        case .camera:       "ic-camera"
        case .teams:        "ic-users"
        case .send:         "ic-send"
        case .unpin:        "ic-pin-off"
        case .addComment:   "ic-comment-add"
        case .template:     "ic-layout-template"
        case .unpublish:    "ic-library-off"
        case .filterActive: "ic-filter-active"
        }
    }

    /// Default size for inline / toolbar / list-row icons.
    static let defaultSize: CGFloat = 18

    /// The icon as a tinted view at an explicit size.
    func image(size: CGFloat) -> some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    /// The icon at the default size — the common `Image(systemName:)` replacement.
    var image: some View { image(size: AppIcon.defaultSize) }

    /// A `Label` pairing the icon with a title — replaces `Label(_, systemImage:)`.
    func label(_ title: LocalizedStringKey, size: CGFloat = AppIcon.defaultSize) -> some View {
        Label { Text(title) } icon: { image(size: size) }
    }

    /// A destructive `Label` (menu / inline delete) whose glyph is forced red to match the
    /// destructive-role text. The app's neutral gray tint would otherwise gray the icon while
    /// only the text turns red. (Swipe actions already render white-on-red — use `label` there.)
    func destructiveLabel(_ title: LocalizedStringKey, size: CGFloat = AppIcon.defaultSize) -> some View {
        Label { Text(title) } icon: { image(size: size).foregroundStyle(.red) }
            .tint(.red)
    }
}
