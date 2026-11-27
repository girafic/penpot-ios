import Foundation

// MARK: - Geometry

struct Point: Decodable, Equatable {
    let x: Double
    let y: Double
}

struct Selrect: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Profile / Team / Project / File

/// Credentials returned by `create-demo-profile` — a throwaway account the caller then
/// logs in with. Only works when the server has the `demo-users` flag enabled.
struct DemoProfile: Decodable {
    let email: String
    let password: String
}

struct Profile: Decodable, Identifiable {
    let id: String
    let fullname: String?
    let email: String?
    let photoId: String?
    // Present on some responses (login/update-profile), absent on others. All optional so
    // decoding never fails. Note: `lang` and `theme` are write-only in Penpot's API — they
    // are accepted as `update-profile` params but never returned, so they usually stay nil.
    let theme: String?
    let lang: String?
    let props: ProfileProps?

    var displayName: String { fullname ?? email ?? .appLocalized("Unknown") }

    /// Explicit init that preserves the 4-argument construction used by `ProfilesResponse`,
    /// `AppState.resolveProfileIfNeeded`, and `SessionStore.cachedProfile`. The new fields
    /// default to nil so those call sites keep compiling unchanged.
    init(id: String, fullname: String? = nil, email: String? = nil, photoId: String? = nil,
         theme: String? = nil, lang: String? = nil, props: ProfileProps? = nil) {
        self.id = id
        self.fullname = fullname
        self.email = email
        self.photoId = photoId
        self.theme = theme
        self.lang = lang
        self.props = props
    }
}

/// A member's role in a team. The API returns no role string — `get-team-members` rows
/// carry `isOwner`/`isAdmin`/`canEdit` booleans the role is derived from — but the
/// invitation/role-change commands accept exactly these raw values.
enum TeamRole: String, CaseIterable, Identifiable {
    case owner, admin, editor, viewer

    var id: String { rawValue }

    /// Roles that invitations and role changes may grant. `owner` is excluded — it is only
    /// reachable through an explicit ownership transfer.
    static let assignable: [TeamRole] = [.admin, .editor, .viewer]

    /// Sort rank, owner first.
    var rank: Int {
        switch self {
        case .owner: 0
        case .admin: 1
        case .editor: 2
        case .viewer: 3
        }
    }

    var displayName: String {
        switch self {
        case .owner: .appLocalized("Owner")
        case .admin: .appLocalized("Admin")
        case .editor: .appLocalized("Editor")
        case .viewer: .appLocalized("Viewer")
        }
    }
}

/// A member of a team (from `get-team-members`). Also used to recover the current user's
/// profile (incl. avatar) when `get-profile` is unavailable.
struct TeamMember: Decodable, Identifiable {
    let id: String
    let profileId: String?
    let email: String?
    let fullname: String?
    let photoId: String?
    // Permission booleans; owner implies admin implies canEdit on the server side.
    let isOwner: Bool?
    let isAdmin: Bool?
    let canEdit: Bool?
    let isActive: Bool?

    var role: TeamRole {
        if isOwner == true { return .owner }
        if isAdmin == true { return .admin }
        if canEdit == true { return .editor }
        return .viewer
    }

    var displayName: String { fullname ?? email ?? .appLocalized("Unknown") }
}

/// The current profile's permissions on a team, returned inline by `get-teams`.
struct TeamPermissions: Decodable {
    let isOwner: Bool?
    let isAdmin: Bool?
    let canEdit: Bool?

    /// The backend already folds owner into `isAdmin`; checking both is defensive.
    var isAdminOrOwner: Bool { isOwner == true || isAdmin == true }
}

struct Team: Decodable, Identifiable {
    let id: String
    let name: String
    let isDefault: Bool?
    let photoId: String?
    let permissions: TeamPermissions?

    /// The default team is stored as "Default" but presented as the localized
    /// "Personal Projects", matching the web UI (Penpot ≥ 2.18; formerly "Your Penpot").
    var displayName: String {
        isDefault == true ? .appLocalized("Personal Projects") : name
    }
}

/// A pending team invitation (`get-team-invitations`). Invitations carry no id — they are
/// keyed by (team, email) — and no dates beyond the derived `expired` flag.
struct TeamInvitation: Decodable, Identifiable {
    let email: String
    let role: String?
    let expired: Bool?

    var id: String { email }
    var teamRole: TeamRole { TeamRole(rawValue: role ?? "") ?? .editor }
}

/// Result of `create-team-invitations`. Only `total` — the number of invitations actually
/// created — is stable; addressees who are already members are silently skipped, and the
/// response's `invitations` key is deliberately not decoded.
struct InvitationResult: Decodable {
    let total: Int?
}

struct Project: Decodable, Identifiable {
    let id: String
    let name: String
    let teamId: String?
    /// Identifies the team's default "Drafts" project (its stored name is literally "Drafts").
    let isDefault: Bool?
    /// Per-profile pin state (from `get-projects`).
    let isPinned: Bool?
    /// Non-deleted file count. Present only on `get-projects`, not `get-project-files`.
    let count: Int?
    /// Soft-delete marker; `get-projects` may include recoverable projects — filter these out.
    let deletedAt: String?

    var isDefaultProject: Bool { isDefault == true }
    var isPinnedFlag: Bool { isPinned == true }
    var fileCount: Int { count ?? 0 }
}

/// A built-in starter template offered by the server (`get-builtin-templates`).
///
/// The command returns only an id and a display name — no thumbnail, description or preview
/// URL — so templates can only be listed by name. The id's sole use is `clone-template`.
struct BuiltinTemplate: Decodable, Identifiable {
    let id: String
    let name: String

    /// Preview image for the template. The API returns no image field, so the path is derived
    /// from the id exactly as Penpot's own dashboard does (`images/thumbnails/template-<id>.jpg`).
    /// Not every template ships one — `welcome` 404s on current servers — so callers must
    /// tolerate a missing image and fall back to a placeholder.
    func thumbnailURL(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("images/thumbnails/template-\(id).jpg")
    }
}

/// A soft-deleted file from `get-team-deleted-files`, recoverable until `willBeDeletedAt`.
struct DeletedFile: Decodable, Identifiable {
    let id: String
    let name: String
    let projectId: String?
    let modifiedAt: String?
    let willBeDeletedAt: String?
}

/// A single installed font variant (weight + style) from `get-font-variants`.
struct FontVariant: Decodable, Identifiable {
    let id: String
    let teamId: String?
    let fontId: String?
    let fontFamily: String
    let fontWeight: Int?     // 100–950
    let fontStyle: String?   // "normal" | "italic"
    let variantName: String?
    let createdAt: String?
    let modifiedAt: String?
    /// The uploaded font files (media ids, served at `/assets/by-id/<id>`); the on-device
    /// renderer loads text in team fonts from them.
    var woff1FileId: String? = nil
    var woff2FileId: String? = nil
    var ttfFileId: String? = nil
    var otfFileId: String? = nil
}

struct FileListItem: Decodable, Identifiable {
    let id: String
    let name: String
    let projectId: String?
    let teamId: String?
    let modifiedAt: String?
    /// Whether the file is published as a team shared library. Returned by `get-project-files`
    /// and `get-team-shared-files`; nil when an endpoint omits it.
    let isShared: Bool?
    /// Media id of the file-level cover — the same image the web dashboard shows.
    /// Absent on files that never generated one (the card then falls back to a board
    /// thumbnail).
    let thumbnailId: String?
}

extension FileListItem: Hashable {
    // Compare all display-relevant fields, not just `id`: SwiftUI uses this `==` to decide
    // whether a file card changed, so an id-only comparison makes it treat a reloaded file as
    // unchanged and skip the redraw — leaving e.g. a stale shared-library badge after unpublish.
    // (Hashing stays id-only, which is still valid: equal items share an id, hence a hash.)
    static func == (lhs: FileListItem, rhs: FileListItem) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.isShared == rhs.isShared
            && lhs.modifiedAt == rhs.modifiedAt && lhs.projectId == rhs.projectId
            && lhs.teamId == rhs.teamId && lhs.thumbnailId == rhs.thumbnailId
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - File data (for board geometry)

struct PenpotFile: Decodable {
    let id: String
    let name: String
    let revn: Int?
    let data: FileData?

    /// The file's pages in document order, each with its root-level boards. Pointer and
    /// unrecognized `pagesIndex` entries are skipped (callers resolve pointers first via
    /// ``PenpotClient/file(id:)``); the `data.pages` order is preserved for survivors.
    var pages: [PenpotPageSummary] {
        guard let index = data?.pagesIndex else { return [] }
        // `data.pages` carries the authored page order; fall back to the index keys.
        let order = data?.pages ?? Array(index.keys)
        return order.compactMap { pageID in
            guard case .page(let page) = index[pageID] else { return nil }
            return PenpotPageSummary(id: pageID, page: page)
        }
    }

    /// What the board grid needs of this file, small enough to cache (``FileOutline``).
    var outline: FileOutline { FileOutline(revision: revn, pages: pages) }

    /// page-id → fragment-id for every `pagesIndex` entry that arrived as a pointer.
    var unresolvedPointerPages: [String: String] {
        guard let index = data?.pagesIndex else { return [:] }
        var pointers: [String: String] = [:]
        for (pageID, entry) in index {
            if case .pointer(let fragmentID) = entry {
                pointers[pageID] = fragmentID
            }
        }
        return pointers
    }

    /// A copy with pointer entries replaced by their resolved pages. Pointers absent
    /// from `resolved` stay pointers (and are simply not rendered).
    func resolvingPointerPages(_ resolved: [String: PenpotPage]) -> PenpotFile {
        guard let index = data?.pagesIndex, !resolved.isEmpty else { return self }
        var newIndex = index
        for (pageID, page) in resolved {
            newIndex[pageID] = .page(page)
        }
        return PenpotFile(id: id, name: name, revn: revn,
                          data: FileData(pagesIndex: newIndex, pages: data?.pages))
    }

    /// All root-level boards across every page, in page then top-to-bottom order.
    var boards: [Board] { pages.flatMap(\.boards) }

    /// Splits a page's direct root-frame children into boards and loose canvas objects.
    /// Every direct child is exactly one of the two, so a page with content can never
    /// look empty: shapes drawn straight on the canvas (and frames whose selrect failed
    /// to decode) surface via `canvasObjectCount`. In real payloads the root frame is
    /// self-parented, hence the explicit id check.
    fileprivate static func rootContent(in page: PenpotPage, pageID: String)
        -> (boards: [Board], canvasObjectCount: Int) {
        var boards: [Board] = []
        var canvasObjectCount = 0
        for (objectID, shape) in page.objects {
            guard objectID != Board.rootFrameID,
                  shape.parentId == Board.rootFrameID else { continue }
            if shape.type == "frame", let selrect = shape.selrect {
                boards.append(Board(id: objectID, pageID: pageID,
                                    name: shape.name ?? "Board", selrect: selrect,
                                    titleIcon: Board.TitleIcon(shape),
                                    showsCanvasTitle: shape.hidden != true
                                        && (shape.componentId == nil || shape.mainInstance == true)))
            } else {
                canvasObjectCount += 1
            }
        }
        // Stable-ish ordering: top-to-bottom, then left-to-right.
        boards.sort { lhs, rhs in
            if lhs.selrect.y != rhs.selrect.y { return lhs.selrect.y < rhs.selrect.y }
            return lhs.selrect.x < rhs.selrect.x
        }
        return (boards, canvasObjectCount)
    }
}

/// A file's pages with their root boards: everything the board grid shows, a few KB even
/// for a design system whose `get-file` is tens of MB. Cached per file with the
/// `get-file` ETag, see ``FileOutlineCache``.
struct FileOutline: Codable {
    /// The file's `revn`, keying the exporter-rendered board previews.
    let revision: Int?
    let pages: [PenpotPageSummary]
}

/// A page within a file, with its root-level boards in display order.
struct PenpotPageSummary: Identifiable, Codable {
    let id: String
    let name: String
    let boards: [Board]
    /// Direct children of the root frame that are not surfaced as boards (shapes drawn
    /// straight on the canvas). Penpot renders no thumbnails for these; they are only
    /// viewable in the live canvas.
    let canvasObjectCount: Int
    /// The canvas color, a hex string: the page's `background`, or Penpot's default
    /// (`clr/canvas`) when it has none. Outlines cached before it was kept don't decode
    /// and are fetched again.
    let background: String
    /// Each root board's position in the view mode's frame list
    /// (``PenpotPage/viewerFrameIDs``): the view route's `index`. Boards hidden in the
    /// viewer have none. It replaced a list kept in paint order, which put the bottom
    /// layer first; outlines cached with that list no longer decode and are fetched again.
    let viewerIndex: [String: Int]

    var hasContent: Bool { !boards.isEmpty || canvasObjectCount > 0 }
}

extension PenpotPageSummary {
    init(id: String, page: PenpotPage) {
        let content = PenpotFile.rootContent(in: page, pageID: id)
        let rootBoardIDs = Set(content.boards.map(\.id))
        let viewerIndex = page.viewerFrameIDs.enumerated()
            .filter { rootBoardIDs.contains($0.element) }
            .map { ($0.element, $0.offset) }
        self.init(id: id,
                  name: page.name ?? "Page",
                  boards: content.boards,
                  canvasObjectCount: content.canvasObjectCount,
                  background: page.background ?? page.options?.background ?? PenpotPage.defaultBackground,
                  viewerIndex: Dictionary(viewerIndex) { first, _ in first })
    }
}

struct FileData: Decodable {
    let pagesIndex: [String: PageEntry]?
    let pages: [String]?
}

/// A `data.pagesIndex` value: an inlined page, or a pointer to a fragment that
/// `get-file-fragment` resolves. Servers 2.0→develop inline everything when the client
/// sends no `features` param, so pointers should never occur for this app — but ONE
/// pointer-shaped entry must not sink the whole `get-file` decode, hence this enum
/// never throws. Pointers arrive as a 2-element array `[fragmentId, {meta}]` (the HTTP
/// middleware's encoding) or, defensively, as `{"type": "pointer", "id": …}`.
enum PageEntry: Decodable {
    case page(PenpotPage)
    case pointer(fragmentID: String)
    case unrecognized

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer(),
           let fragmentID = try? unkeyed.decode(String.self) {
            self = .pointer(fragmentID: fragmentID)
            return
        }
        // An inline page requires `objects`, so a pointer object never matches here.
        if let page = try? PenpotPage(from: decoder) {
            self = .page(page)
            return
        }
        if let probe = try? PointerProbe(from: decoder),
           probe.type == "pointer", let id = probe.id {
            self = .pointer(fragmentID: id)
            return
        }
        self = .unrecognized
    }

    private struct PointerProbe: Decodable {
        let type: String?
        let id: String?
    }
}

/// `get-file-fragment` response envelope. Modern servers (file_data table) carry the
/// page under `data`; 2.0-era servers (file_data_fragment) used `content`. Decoded
/// defensively — a non-page fragment (e.g. a components map) must not throw.
struct FileFragment: Decodable {
    let data: PenpotPage?
    let content: PenpotPage?

    var page: PenpotPage? { data ?? content }

    private enum CodingKeys: String, CodingKey { case data, content }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        data = try? container?.decodeIfPresent(PenpotPage.self, forKey: .data)
        content = try? container?.decodeIfPresent(PenpotPage.self, forKey: .content)
    }
}

/// A prototype flow: a named entry point into the page's interactions
/// (`{id, name, starting-frame}`).
struct PrototypeFlow: Decodable {
    let id: String?
    let name: String?
    let startingFrame: String?
}

/// Tolerates both encodings of a page's flows — the modern map-of-uuid (page-level
/// `flows`) and the legacy array (`options.flows` on pre-2.x files) — and never throws,
/// so a malformed payload can't sink the whole `get-file` decode.
struct FlowCollection: Decodable {
    let flows: [PrototypeFlow]

    init(from decoder: Decoder) throws {
        if let map = try? [String: PrototypeFlow](from: decoder) {
            flows = Array(map.values)
        } else if let list = try? [PrototypeFlow](from: decoder) {
            flows = list
        } else {
            flows = []
        }
    }
}

struct PenpotPage: Decodable {
    let id: String?
    let name: String?
    let objects: [String: Shape]
    /// Prototype flows (modern page-level field, Penpot ≥ 2.x).
    let flows: FlowCollection?
    /// Legacy container: pre-2.x files stored flows under `options`.
    let options: PageOptions?
    /// The canvas color (`#RRGGBB`), when the page sets one.
    let background: String?

    struct PageOptions: Decodable {
        let flows: FlowCollection?
        /// The canvas color of files from before it moved to the page itself.
        let background: String?
    }

    /// The canvas color of a page that sets none (`app.common.types.color/canvas`).
    static let defaultBackground = "#E8E9EA"
}

extension PenpotPage {
    /// The frames Penpot's view mode pages through, in its order: `get-viewer-frames`
    /// (`common/types/shape_tree.cljc`, the same since 2.0). That is every frame of the
    /// page, nested ones included, sorted by `sort-z-index-objects` and without
    /// `hide-in-viewer`. A frame's position here is the view route's `index`, and the
    /// viewer's "1 / n". The sort puts the topmost layer first and a frame before the
    /// frames inside it, so the root board listed *last* in `shapes` comes first.
    var viewerFrameIDs: [String] {
        var frames: [String] = []
        var visited: Set<String> = [Board.rootFrameID]
        func visit(_ parent: Shape) {
            for id in viewerOrder(ofChildrenOf: parent) where visited.insert(id).inserted {
                guard let shape = objects[id] else { continue }
                if shape.type == "frame", shape.hideInViewer != true { frames.append(id) }
                visit(shape)
            }
        }
        if let root = objects[Board.rootFrameID] { visit(root) }
        return frames
    }

    /// Siblings in the order `is-shape-over-shape?` sorts them: the last of `shapes` first,
    /// except in a flex or grid board, where a higher `layout-item-z-index` comes first
    /// and equal ones keep `shapes` order. Unlike paint order, the viewer ignores a
    /// reversed flex direction.
    func viewerOrder(ofChildrenOf parent: Shape) -> [String] {
        let ids = parent.shapes ?? []
        guard parent.type == "frame", parent.layout == "flex" || parent.layout == "grid" else {
            return ids.reversed()
        }
        return ids.enumerated().sorted { lhs, rhs in
            let lz = objects[lhs.element]?.layoutItemZIndex ?? 0
            let rz = objects[rhs.element]?.layoutItemZIndex ?? 0
            return lz != rz ? lz > rz : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

/// A prototype interaction on a shape (`common/types/shape/interactions.cljc`), as the
/// native player (``PrototypeModel``) plays it. Every field is optional and unknown values
/// stay strings, so a newer Penpot can't break decoding.
struct ShapeInteraction: Decodable, Equatable {
    /// `click`, `mouse-press`, `mouse-over`, `mouse-enter`, `mouse-leave`, `after-delay`.
    let eventType: String?
    /// `navigate`, `open-overlay`, `toggle-overlay`, `close-overlay`, `prev-screen`,
    /// `open-url`.
    let actionType: String?
    /// The board to go to (navigate) or show (overlays).
    let destination: String?
    /// Milliseconds before an `after-delay` interaction runs.
    let delay: Double?
    let url: String?
    /// Navigate keeps the viewer's scroll position.
    let preserveScroll: Bool?
    let animation: PrototypeAnimation?
    /// Overlays: `manual`, `center` (Penpot's default), `top-left`, `top-right`,
    /// `top-center`, `bottom-left`, `bottom-right`, `bottom-center`.
    let overlayPosType: String?
    /// A manual overlay's position.
    let overlayPosition: Point?
    /// The shape an overlay is placed against; none means the board.
    let positionRelativeTo: String?
    /// A tap outside the overlay closes it.
    let closeClickOutside: Bool?
    /// The screen dims behind the overlay.
    let backgroundOverlay: Bool?

    init(eventType: String? = "click", actionType: String?, destination: String? = nil,
         delay: Double? = nil, url: String? = nil, preserveScroll: Bool? = nil,
         animation: PrototypeAnimation? = nil, overlayPosType: String? = nil,
         overlayPosition: Point? = nil, positionRelativeTo: String? = nil,
         closeClickOutside: Bool? = nil, backgroundOverlay: Bool? = nil) {
        self.eventType = eventType
        self.actionType = actionType
        self.destination = destination
        self.delay = delay
        self.url = url
        self.preserveScroll = preserveScroll
        self.animation = animation
        self.overlayPosType = overlayPosType
        self.overlayPosition = overlayPosition
        self.positionRelativeTo = positionRelativeTo
        self.closeClickOutside = closeClickOutside
        self.backgroundOverlay = backgroundOverlay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventType = try? container.decodeIfPresent(String.self, forKey: .eventType)
        actionType = try? container.decodeIfPresent(String.self, forKey: .actionType)
        destination = try? container.decodeIfPresent(String.self, forKey: .destination)
        delay = try? container.decodeIfPresent(Double.self, forKey: .delay)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        preserveScroll = try? container.decodeIfPresent(Bool.self, forKey: .preserveScroll)
        animation = try? container.decodeIfPresent(PrototypeAnimation.self, forKey: .animation)
        overlayPosType = try? container.decodeIfPresent(String.self, forKey: .overlayPosType)
        overlayPosition = try? container.decodeIfPresent(Point.self, forKey: .overlayPosition)
        positionRelativeTo = try? container.decodeIfPresent(String.self, forKey: .positionRelativeTo)
        closeClickOutside = try? container.decodeIfPresent(Bool.self, forKey: .closeClickOutside)
        backgroundOverlay = try? container.decodeIfPresent(Bool.self, forKey: .backgroundOverlay)
    }

    private enum CodingKeys: String, CodingKey {
        case eventType, actionType, destination, delay, url, preserveScroll, animation,
             overlayPosType, overlayPosition, positionRelativeTo, closeClickOutside,
             backgroundOverlay
    }
}

/// How an interaction animates: Penpot's `dissolve`, `slide` and `push`.
struct PrototypeAnimation: Decodable, Equatable {
    let animationType: String?
    /// Milliseconds.
    let duration: Double?
    /// A CSS easing name: `linear`, `ease`, `ease-in`, `ease-out`, `ease-in-out`.
    let easing: String?
    /// `right`, `left`, `up`, `down`: where the moving board heads.
    let direction: String?
    /// `in` or `out`, for slides: whether the new board slides in or the old one out.
    let way: String?
    /// For slides: the other board moves 20 % along and fades.
    let offsetEffect: Bool?
}

struct Shape: Decodable {
    let id: String?
    let name: String?
    let type: String?
    let frameId: String?
    let parentId: String?
    let selrect: Selrect?
    /// Child shape ids, bottom layer first. Read for the viewer's frame order.
    let shapes: [String]?
    /// Excluded from the viewer's frame list when true.
    let hideInViewer: Bool?
    let interactions: [ShapeInteraction]?
    /// `flex` or `grid` on a board with a layout, whose children the viewer orders by
    /// `layoutItemZIndex`.
    let layout: String?
    let layoutItemZIndex: Double?
    /// Hidden in the layers panel: not drawn, so no prototype hotspot either.
    let hidden: Bool?
    /// "Fix when scrolling": the prototype keeps it in place while its board scrolls.
    let fixedScroll: Bool?
    /// Whether the shape has any fill. A board without one lets taps through to what lies
    /// under it in Penpot's viewer (its background rect has `fill: none`).
    let hasFills: Bool
    /// The board the file's thumbnail is made from.
    let useForThumbnail: Bool?
    /// The main copy of a component.
    let mainInstance: Bool?
    /// Set on the head of every instance of a component, the main one and its copies.
    let componentId: String?
    /// A board holding a component's variants.
    let isVariantContainer: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, type, selrect, frameId, parentId, shapes, hideInViewer, interactions,
             layout, layoutItemZIndex, hidden, fills, fixedScroll, useForThumbnail, mainInstance,
             componentId, isVariantContainer
    }

    // Decode defensively: a single shape with an unexpected field shape (e.g. a malformed
    // selrect) should not fail decoding of the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        frameId = try? container.decodeIfPresent(String.self, forKey: .frameId)
        parentId = try? container.decodeIfPresent(String.self, forKey: .parentId)
        selrect = try? container.decodeIfPresent(Selrect.self, forKey: .selrect)
        shapes = try? container.decodeIfPresent([String].self, forKey: .shapes)
        hideInViewer = try? container.decodeIfPresent(Bool.self, forKey: .hideInViewer)
        interactions = try? container.decodeIfPresent([ShapeInteraction].self, forKey: .interactions)
        layout = try? container.decodeIfPresent(String.self, forKey: .layout)
        layoutItemZIndex = try? container.decodeIfPresent(Double.self, forKey: .layoutItemZIndex)
        hidden = try? container.decodeIfPresent(Bool.self, forKey: .hidden)
        fixedScroll = try? container.decodeIfPresent(Bool.self, forKey: .fixedScroll)
        let fills = try? container.decodeIfPresent([AnyDecodable].self, forKey: .fills)
        hasFills = !(fills ?? []).isEmpty
        useForThumbnail = try? container.decodeIfPresent(Bool.self, forKey: .useForThumbnail)
        mainInstance = try? container.decodeIfPresent(Bool.self, forKey: .mainInstance)
        componentId = try? container.decodeIfPresent(String.self, forKey: .componentId)
        isVariantContainer = try? container.decodeIfPresent(Bool.self, forKey: .isVariantContainer)
    }
}

/// Decodes and discards any JSON value: only to count the entries of an array whose
/// elements the app doesn't read.
private struct AnyDecodable: Decodable {
    init(from decoder: Decoder) throws {}
}

/// A root-level board (frame) extracted from a file.
struct Board: Identifiable, Equatable, Codable {
    static let rootFrameID = "00000000-0000-0000-0000-000000000000"

    let id: String
    let pageID: String
    let name: String
    let selrect: Selrect
    /// The icon Penpot's canvas puts before the board's name, if any.
    var titleIcon: TitleIcon? = nil
    /// Whether Penpot's canvas names the board (`frame-titles*`): every root board but a
    /// copy of a component (an instance head that isn't the main one) and a hidden one.
    /// Boards inside groups or other boards are no root boards, so never named either.
    var showsCanvasTitle = true

    /// Penpot's `frame-title`: only these boards get an icon before their name.
    enum TitleIcon: String, Codable {
        /// The file's thumbnail board (`boards-thumbnail`).
        case thumbnail
        /// A main component or a variant container (`component`).
        case component

        init?(_ shape: Shape) {
            if shape.useForThumbnail == true {
                self = .thumbnail
            } else if shape.mainInstance == true || shape.isVariantContainer == true {
                self = .component
            } else {
                return nil
            }
        }

        var assetName: String {
            switch self {
            case .thumbnail: "ic-boards-thumbnail"
            case .component: "ic-component"
            }
        }
    }
}

// MARK: - Comments

struct CommentThread: Decodable, Identifiable {
    let id: String
    let fileId: String?
    let pageId: String?
    let frameId: String?
    var position: Point?
    let content: String?
    let isResolved: Bool?
    let countComments: Int?
    let countUnreadComments: Int?
    let ownerId: String?
    let seqn: Int?
    let createdAt: String?
    let modifiedAt: String?

    // Joined by the server on thread queries, so a thread can be rendered outside its file.
    let teamId: String?
    let fileName: String?
    let ownerFullname: String?
    let ownerPhotoId: String?

    /// Profile ids of everyone who commented in the thread — drives the "Only yours" filter.
    let participants: [String]?
    /// Profile ids mentioned anywhere in the thread — drives the "Mentions" filter.
    let mentions: [String]?

    var unreadCount: Int { countUnreadComments ?? 0 }

    enum CodingKeys: String, CodingKey {
        case id, fileId, pageId, frameId, position, content, isResolved,
             countComments, countUnreadComments, ownerId, seqn, createdAt, modifiedAt,
             teamId, fileName, ownerFullname, ownerPhotoId, participants, mentions
    }

    // Custom init only so `participants`/`mentions` decode defensively: they are stored
    // as transit/pg arrays server-side and their JSON shape is less battle-tested than
    // the rest — a surprise there must not sink a whole thread list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fileId = try container.decodeIfPresent(String.self, forKey: .fileId)
        pageId = try container.decodeIfPresent(String.self, forKey: .pageId)
        frameId = try container.decodeIfPresent(String.self, forKey: .frameId)
        position = try container.decodeIfPresent(Point.self, forKey: .position)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        isResolved = try container.decodeIfPresent(Bool.self, forKey: .isResolved)
        countComments = try container.decodeIfPresent(Int.self, forKey: .countComments)
        countUnreadComments = try container.decodeIfPresent(Int.self, forKey: .countUnreadComments)
        ownerId = try container.decodeIfPresent(String.self, forKey: .ownerId)
        seqn = try container.decodeIfPresent(Int.self, forKey: .seqn)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        modifiedAt = try container.decodeIfPresent(String.self, forKey: .modifiedAt)
        teamId = try container.decodeIfPresent(String.self, forKey: .teamId)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        ownerFullname = try container.decodeIfPresent(String.self, forKey: .ownerFullname)
        ownerPhotoId = try container.decodeIfPresent(String.self, forKey: .ownerPhotoId)
        participants = try? container.decodeIfPresent([String].self, forKey: .participants)
        mentions = try? container.decodeIfPresent([String].self, forKey: .mentions)
    }
}

struct Comment: Decodable, Identifiable {
    let id: String
    let threadId: String?
    let ownerId: String?
    let content: String?
    let createdAt: String?
    /// Profile ids mentioned in this comment (Penpot ≥ 2.7).
    let mentions: [String]?
}

// MARK: - Version history

/// One row of `get-file-snapshots`. Newer servers return every field; 2.7.x returns only
/// id/label/revn/createdAt/createdBy/profileId — decode leniently. Dates stay ISO strings
/// and are formatted via ``PenpotDate``.
struct FileSnapshot: Decodable, Identifiable {
    let id: String
    let label: String?
    let revn: Int?
    let version: Int?
    let createdAt: String?
    let modifiedAt: String?
    /// `"user" | "system" | "admin"` — system rows are autosaves / pre-restore backups.
    let createdBy: String?
    let profileId: String?
    /// Profile id holding a lock (Penpot ≥ 2.16), nil otherwise.
    let lockedBy: String?
    /// Non-nil on system rows: scheduled expiry (they stay listed until it passes).
    let deletedAt: String?

    /// A named, permanent version (explicitly saved or pinned); admin/nil count as user.
    var isUserVersion: Bool { createdBy != "system" }
    var sortKey: Date { PenpotDate.sortKey(createdAt) }
}

/// The web History sidebar's grouping: user versions render individually, system
/// autosaves are bundled per calendar day, everything newest-first — a day group sits at
/// the position of its newest member.
enum SnapshotGroup: Identifiable {
    case version(FileSnapshot)
    case autosaves(day: Date, items: [FileSnapshot])

    var id: String {
        switch self {
        case .version(let snapshot): "version-\(snapshot.id)"
        case .autosaves(let day, _): "autosaves-\(day.timeIntervalSinceReferenceDate)"
        }
    }

    /// `snapshots` may arrive in any order — the server's SQL UNION doesn't guarantee one.
    static func build(from snapshots: [FileSnapshot],
                      calendar: Calendar = .current) -> [SnapshotGroup] {
        let sorted = snapshots.sorted { $0.sortKey > $1.sortKey }
        var groups: [SnapshotGroup] = []
        var groupIndexByDay: [Date: Int] = [:]
        for snapshot in sorted {
            if snapshot.isUserVersion {
                groups.append(.version(snapshot))
            } else {
                let day = calendar.startOfDay(for: snapshot.sortKey)
                if let index = groupIndexByDay[day],
                   case .autosaves(_, var items) = groups[index] {
                    items.append(snapshot)
                    groups[index] = .autosaves(day: day, items: items)
                } else {
                    groupIndexByDay[day] = groups.count
                    groups.append(.autosaves(day: day, items: [snapshot]))
                }
            }
        }
        return groups
    }
}

// MARK: - Share links

/// A public share link of a file (`create-share-link` / the viewer bundle's `shareLinks`).
/// Named to avoid colliding with SwiftUI's `ShareLink` view.
struct PenpotShareLink: Decodable, Identifiable {
    let id: String
    let fileId: String?
    /// Who may comment through the link: `"all"` or `"team"`.
    let whoComment: String?
    /// Who may open inspect mode through the link: `"all"` or `"team"`.
    let whoInspect: String?
    let pages: [String]?
    let ownerId: String?

    var allowsExternalComments: Bool { whoComment == "all" }
    var allowsExternalInspect: Bool { whoInspect == "all" }
}

/// Minimal slice of `get-view-only-bundle` — share links plus the ordered page ids.
/// Deliberately not reusing `FileData`: decoding the bundle's full file data would parse
/// every shape just to list links.
struct ViewOnlyBundle: Decodable {
    let shareLinks: [PenpotShareLink]?
    let file: BundleFile?

    struct BundleFile: Decodable {
        let id: String?
        let data: BundleFileData?
    }

    struct BundleFileData: Decodable {
        let pages: [String]?
    }

    var pageIDs: [String] { file?.data?.pages ?? [] }
}

// MARK: - File stats

/// Aggregate metrics of one file (`get-file-stats`, Penpot ≥ 2.17). Counts only, so —
/// unlike `get-file` — no page data is transferred.
struct FileStats: Decodable {
    let pageCount: Int?
    let shapeCounts: ShapeCounts?
    let componentCount: Int?
    let colorCount: Int?
    let typographyCount: Int?
    /// Libraries this file uses.
    let libraryCount: Int?
    /// Files that use this file as a library.
    let referencedByCount: Int?
    let revn: Int?
    let updatedAt: String?

    struct ShapeCounts: Decodable {
        let total: Int?
        /// Keyed by shape type: `frame`, `rect`, `circle`, `text`, `path`, `group`, `bool`,
        /// `image`, `svgRaw` (keyword keys are camelCased like every response key).
        let byType: [String: Int]?
    }

    /// Shape types with a nonzero count, most frequent first (ties by type, so the order is
    /// stable — `byType` is a dictionary).
    var layerTypes: [(type: String, count: Int)] {
        (shapeCounts?.byType ?? [:])
            .filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (type: $0.key, count: $0.value) }
    }
}

/// `get-profiles-for-file-comments` may return either a list of profiles or a map keyed
/// by profile id (where the value object may omit its own `id`). This normalizes both
/// shapes into `byID`.
struct ProfilesResponse: Decodable {
    let byID: [String: Profile]

    private struct ProfileDTO: Decodable {
        let id: String?
        let fullname: String?
        let email: String?
        let photoId: String?
    }

    init(from decoder: Decoder) throws {
        var result: [String: Profile] = [:]
        if let map = try? [String: ProfileDTO](from: decoder) {
            for (key, dto) in map {
                let id = dto.id ?? key
                result[id] = Profile(id: id, fullname: dto.fullname, email: dto.email, photoId: dto.photoId)
            }
        } else if let array = try? [ProfileDTO](from: decoder) {
            for dto in array {
                guard let id = dto.id else { continue }
                result[id] = Profile(id: id, fullname: dto.fullname, email: dto.email, photoId: dto.photoId)
            }
        }
        byID = result
    }
}
