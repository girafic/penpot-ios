import Foundation

/// File share-link commands. Penpot has no dedicated "list share links" query — the web
/// app reads them from the viewer bundle (`get-view-only-bundle`), so this does too.
extension PenpotClient {

    /// The view-only bundle of a file: existing share links + the ordered page ids.
    func viewOnlyBundle(fileID: String) async throws -> ViewOnlyBundle {
        try await query("get-view-only-bundle", params: ["file-id": fileID], as: ViewOnlyBundle.self)
    }

    /// Creates a public share link (`create-share-link`). `whoComment`/`whoInspect` are
    /// exactly `"all"` or `"team"` (the web dialog's values). All four params are required
    /// by the backend schema — pass every page id for a whole-file link. POSTed because
    /// the GET helper can't encode the `pages` array.
    @discardableResult
    func createShareLink(fileID: String, whoComment: String, whoInspect: String,
                         pageIDs: [String]) async throws -> PenpotShareLink {
        try await mutation("create-share-link", params: [
            "file-id": fileID,
            "who-comment": whoComment,
            "who-inspect": whoInspect,
            "pages": pageIDs,
        ], as: PenpotShareLink.self)
    }

    /// Revokes a share link (`delete-share-link`); the URL stops working for everyone.
    func deleteShareLink(id: String) async throws {
        _ = try await mutation("delete-share-link", params: ["id": id], as: EmptyResponse.self)
    }

    /// The public viewer URL for a share link — the same URL the web app's share dialog
    /// copies. `pageID` may be nil; the viewer then falls back to the file's first page.
    func shareURL(fileID: String, pageID: String?, shareID: String) -> URL? {
        var query = "file-id=\(fileID)"
        if let pageID { query += "&page-id=\(pageID)" }
        query += "&section=interactions&index=0&share-id=\(shareID)"
        return URL(string: "\(baseURL.absoluteString)/#/view?\(query)")
    }
}
