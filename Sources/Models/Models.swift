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

    var displayName: String { fullname ?? email ?? "Unknown" }
}

struct Team: Decodable, Identifiable {
    let id: String
    let name: String
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name
        case isDefault = "is-default"
    }
}

struct Project: Decodable, Identifiable {
    let id: String
    let name: String
    let teamId: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case teamId = "team-id"
    }
}

struct FileListItem: Decodable, Identifiable {
    let id: String
    let name: String
    let projectId: String?
    let modifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case projectId = "project-id"
        case modifiedAt = "modified-at"
    }
}

// MARK: - File data (for board geometry)

struct PenpotFile: Decodable {
    let id: String
    let name: String
    let revn: Int?
    let data: FileData?

    /// All root-level boards across the file's pages, with their page id and geometry.
    var boards: [Board] {
        guard let pagesIndex = data?.pagesIndex else { return [] }
        var result: [Board] = []
        for (pageID, page) in pagesIndex {
            for (objectID, shape) in page.objects {
                guard shape.type == "frame",
                      objectID != Board.rootFrameID,
                      shape.parentId == Board.rootFrameID,
                      let selrect = shape.selrect else { continue }
                result.append(Board(id: objectID,
                                    pageID: pageID,
                                    name: shape.name ?? "Board",
                                    selrect: selrect))
            }
        }
        // Stable-ish ordering: top-to-bottom, then left-to-right.
        return result.sorted { lhs, rhs in
            if lhs.selrect.y != rhs.selrect.y { return lhs.selrect.y < rhs.selrect.y }
            return lhs.selrect.x < rhs.selrect.x
        }
    }
}

struct FileData: Decodable {
    let pagesIndex: [String: PenpotPage]?
    let pages: [String]?

    enum CodingKeys: String, CodingKey {
        case pagesIndex = "pages-index"
        case pages
    }
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
        case id, name, type, selrect
        case frameId = "frame-id"
        case parentId = "parent-id"
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

    enum CodingKeys: String, CodingKey {
        case id, position, content, seqn
        case fileId = "file-id"
        case pageId = "page-id"
        case frameId = "frame-id"
        case isResolved = "is-resolved"
        case countComments = "count-comments"
        case countUnreadComments = "count-unread-comments"
        case ownerId = "owner-id"
        case createdAt = "created-at"
    }
}

struct Comment: Decodable, Identifiable {
    let id: String
    let threadId: String?
    let ownerId: String?
    let content: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, content
        case threadId = "thread-id"
        case ownerId = "owner-id"
        case createdAt = "created-at"
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
    }

    init(from decoder: Decoder) throws {
        var result: [String: Profile] = [:]
        if let map = try? [String: ProfileDTO](from: decoder) {
            for (key, dto) in map {
                let id = dto.id ?? key
                result[id] = Profile(id: id, fullname: dto.fullname, email: dto.email)
            }
        } else if let array = try? [ProfileDTO](from: decoder) {
            for dto in array {
                guard let id = dto.id else { continue }
                result[id] = Profile(id: id, fullname: dto.fullname, email: dto.email)
            }
        }
        byID = result
    }
}
