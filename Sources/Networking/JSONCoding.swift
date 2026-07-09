import Foundation

extension JSONDecoder {
    /// Shared decoder for Penpot responses.
    ///
    /// Penpot's JSON API returns **camelCase** keys (e.g. `pagesIndex`, `parentId`, `isResolved`),
    /// which match our Swift property names directly — so no `keyDecodingStrategy` is needed.
    /// We must *not* set one anyway: responses contain dictionaries keyed by UUIDs (object ids,
    /// thumbnail ids) whose keys must be preserved verbatim.
    ///
    /// Note the asymmetry: request *params* use kebab-case (e.g. `file-id`), but response
    /// *bodies* are camelCase. See `PenpotClient`.
    static let penpot = JSONDecoder()
}
