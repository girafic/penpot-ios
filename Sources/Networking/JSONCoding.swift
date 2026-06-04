import Foundation

extension JSONDecoder {
    /// Shared decoder for Penpot responses.
    ///
    /// Note: we deliberately do *not* use a global kebab-case key strategy, because Penpot
    /// responses contain dictionaries keyed by UUIDs (object ids, thumbnail ids) whose keys
    /// must not be transformed. Kebab-case fields are mapped explicitly via `CodingKeys`.
    static let penpot = JSONDecoder()
}
