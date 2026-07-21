import Foundation

// MARK: - Geometry

struct Point: Decodable, Equatable {
    let x: Double
    let y: Double
}

struct Selrect: Decodable, Equatable {
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

/// A member of a team (from `get-team-members`). Used to recover the current user's
/// profile (incl. avatar) when `get-profile` is unavailable.
struct TeamMember: Decodable, Identifiable {
    let id: String
    let profileId: String?
    let email: String?
    let fullname: String?
    let photoId: String?
}

struct Team: Decodable, Identifiable {
    let id: String
    let name: String
    let isDefault: Bool?
    let photoId: String?

    /// The default team is stored as "Default" but presented as the localized
    /// "Your Penpot", matching the web UI.
    var displayName: String {
        isDefault == true ? .appLocalized("Your Penpot") : name
    }
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
}

struct FileListItem: Decodable, Identifiable {
    let id: String
    let name: String
    let projectId: String?
    let teamId: String?
    let modifiedAt: String?
}

extension FileListItem: Hashable {
    static func == (lhs: FileListItem, rhs: FileListItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - File data (for board geometry)

struct PenpotFile: Decodable {
    let id: String
    let name: String
    let revn: Int?
    let data: FileData?

    /// The file's pages in document order, each with its root-level boards.
    var pages: [PenpotPageSummary] {
        guard let index = data?.pagesIndex else { return [] }
        // `data.pages` carries the authored page order; fall back to the index keys.
        let order = data?.pages ?? Array(index.keys)
        return order.compactMap { pageID in
            guard let page = index[pageID] else { return nil }
            let content = Self.rootContent(in: page, pageID: pageID)
            return PenpotPageSummary(id: pageID,
                                     name: page.name ?? "Page",
                                     boards: content.boards,
                                     canvasObjectCount: content.canvasObjectCount)
        }
    }

    /// All root-level boards across every page, in page then top-to-bottom order.
    var boards: [Board] { pages.flatMap(\.boards) }

    /// Splits a page's direct root-frame children into boards and loose canvas objects.
    /// Every direct child is exactly one of the two, so a page with content can never
    /// look empty: shapes drawn straight on the canvas (and frames whose selrect failed
    /// to decode) surface via `canvasObjectCount`. In real payloads the root frame is
    /// self-parented, hence the explicit id check.
    private static func rootContent(in page: PenpotPage, pageID: String)
        -> (boards: [Board], canvasObjectCount: Int) {
        var boards: [Board] = []
        var canvasObjectCount = 0
        for (objectID, shape) in page.objects {
            guard objectID != Board.rootFrameID,
                  shape.parentId == Board.rootFrameID else { continue }
            if shape.type == "frame", let selrect = shape.selrect {
                boards.append(Board(id: objectID, pageID: pageID,
                                    name: shape.name ?? "Board", selrect: selrect))
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

/// A page within a file, with its root-level boards in display order.
struct PenpotPageSummary: Identifiable {
    let id: String
    let name: String
    let boards: [Board]
    /// Direct children of the root frame that are not surfaced as boards (shapes drawn
    /// straight on the canvas). Penpot renders no thumbnails for these; they are only
    /// viewable in the live canvas.
    let canvasObjectCount: Int

    var hasContent: Bool { !boards.isEmpty || canvasObjectCount > 0 }
}

struct FileData: Decodable {
    let pagesIndex: [String: PenpotPage]?
    let pages: [String]?
}

struct PenpotPage: Decodable {
    let id: String?
    let name: String?
    let objects: [String: Shape]
}

struct Shape: Decodable {
    let id: String?
    let name: String?
    let type: String?
    let frameId: String?
    let parentId: String?
    let selrect: Selrect?

    enum CodingKeys: String, CodingKey {
        case id, name, type, selrect, frameId, parentId
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
    }
}

/// A root-level board (frame) extracted from a file.
struct Board: Identifiable, Equatable {
    static let rootFrameID = "00000000-0000-0000-0000-000000000000"

    let id: String
    let pageID: String
    let name: String
    let selrect: Selrect
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

    var unreadCount: Int { countUnreadComments ?? 0 }
}

struct Comment: Decodable, Identifiable {
    let id: String
    let threadId: String?
    let ownerId: String?
    let content: String?
    let createdAt: String?
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
