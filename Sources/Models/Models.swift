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

struct Profile: Decodable, Identifiable {
    let id: String
    let fullname: String?
    let email: String?
    let photoId: String?

    var displayName: String { fullname ?? email ?? "Unknown" }
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
}

struct Project: Decodable, Identifiable {
    let id: String
    let name: String
    let teamId: String?
}

struct FileListItem: Decodable, Identifiable {
    let id: String
    let name: String
    let projectId: String?
    let teamId: String?
    let modifiedAt: String?
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
            return PenpotPageSummary(id: pageID,
                                     name: page.name ?? "Page",
                                     boards: Self.boards(in: page, pageID: pageID))
        }
    }

    /// All root-level boards across every page, in page then top-to-bottom order.
    var boards: [Board] { pages.flatMap(\.boards) }

    private static func boards(in page: PenpotPage, pageID: String) -> [Board] {
        page.objects.compactMap { objectID, shape -> Board? in
            guard shape.type == "frame",
                  objectID != Board.rootFrameID,
                  shape.parentId == Board.rootFrameID,
                  let selrect = shape.selrect else { return nil }
            return Board(id: objectID, pageID: pageID, name: shape.name ?? "Board", selrect: selrect)
        }
        // Stable-ish ordering: top-to-bottom, then left-to-right.
        .sorted { lhs, rhs in
            if lhs.selrect.y != rhs.selrect.y { return lhs.selrect.y < rhs.selrect.y }
            return lhs.selrect.x < rhs.selrect.x
        }
    }
}

/// A page within a file, with its root-level boards in display order.
struct PenpotPageSummary: Identifiable {
    let id: String
    let name: String
    let boards: [Board]
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
    let position: Point?
    let content: String?
    let isResolved: Bool?
    let countComments: Int?
    let countUnreadComments: Int?
    let ownerId: String?
    let seqn: Int?
    let createdAt: String?
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
