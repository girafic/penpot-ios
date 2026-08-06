import XCTest
@testable import PenpotiOS

/// The exporter endpoint speaks transit+json (verbose): keywords as `"~:kw"`, uuids as
/// `"~u<lowercase>"`. These cover the hand-built encoding and the resource-map parsing.
final class BoardExportTests: XCTestCase {

    // MARK: Request body

    func testExportTransitBodyRoundTrips() throws {
        let data = try PenpotClient.exportTransitBody(
            fileID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            pageID: "11111111-2222-3333-4444-555555555555",
            objectID: "99999999-8888-7777-6666-555555555555",
            profileID: "7d3a8f10-0000-0000-0000-000000000000",
            type: .png, scale: 2, suffix: "@2x", name: "Board 1")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(body["~:wait"] as? Bool, true)
        XCTAssertEqual(body["~:cmd"] as? String, "~:export-shapes")
        XCTAssertEqual(body["~:profile-id"] as? String, "~u7d3a8f10-0000-0000-0000-000000000000")

        let exports = try XCTUnwrap(body["~:exports"] as? [[String: Any]])
        XCTAssertEqual(exports.count, 1)
        let entry = exports[0]
        // uuids are lowercased under the ~u tag regardless of input casing.
        XCTAssertEqual(entry["~:file-id"] as? String, "~uaaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertEqual(entry["~:page-id"] as? String, "~u11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(entry["~:object-id"] as? String, "~u99999999-8888-7777-6666-555555555555")
        XCTAssertEqual(entry["~:type"] as? String, "~:png")
        XCTAssertEqual(entry["~:scale"] as? Double, 2)
        XCTAssertEqual(entry["~:suffix"] as? String, "@2x")
        XCTAssertEqual(entry["~:name"] as? String, "Board 1")
    }

    // Leading `~`/`^` in user-controlled strings must be escaped per transit rules.
    func testTransitStringEscaping() {
        XCTAssertEqual(PenpotClient.transitString("~tilde"), "~~tilde")
        XCTAssertEqual(PenpotClient.transitString("^caret"), "~^caret")
        XCTAssertEqual(PenpotClient.transitString("plain ~ inside"), "plain ~ inside")
        XCTAssertEqual(PenpotClient.transitString(""), "")
    }

    // MARK: Response parsing

    private let base = URL(string: "https://design.penpot.app")!

    // Verbatim response shape from the verified contract (wait=true single export).
    func testExportResourceParsesContractResponse() throws {
        let json = """
        {
          "~:id": "~u0198f2a0-0000-0000-0000-000000000000",
          "~:name": "Board 1",
          "~:filename": "Board 1@2x.png",
          "~:mtype": "image/png",
          "~:uri": "https://design.penpot.app/assets/by-id/0198f2a0-1111-0000-0000-000000000000"
        }
        """
        let resource = try XCTUnwrap(
            PenpotClient.exportResource(fromTransit: Data(json.utf8), baseURL: base))
        XCTAssertEqual(resource.filename, "Board 1@2x.png")
        XCTAssertEqual(resource.mtype, "image/png")
        XCTAssertEqual(resource.uri?.absoluteString,
                       "https://design.penpot.app/assets/by-id/0198f2a0-1111-0000-0000-000000000000")
    }

    // Pre-2.12 servers answer wait=true without a uri — parse succeeds, uri stays nil
    // (the client then reports the exporter as unavailable).
    func testExportResourceWithoutURI() throws {
        let json = #"{"~:id": "~uabc", "~:filename": "x.png", "~:mtype": "image/png"}"#
        let resource = try XCTUnwrap(
            PenpotClient.exportResource(fromTransit: Data(json.utf8), baseURL: base))
        XCTAssertNil(resource.uri)
    }

    func testExportResourceResolvesRelativeURI() throws {
        let json = #"{"~:filename": "x.svg", "~:uri": "/assets/by-id/123"}"#
        let resource = try XCTUnwrap(
            PenpotClient.exportResource(fromTransit: Data(json.utf8), baseURL: base))
        XCTAssertEqual(resource.uri?.absoluteString, "https://design.penpot.app/assets/by-id/123")
    }

    // Transit's compact JSON encoding wraps maps as ["^ ", k1, v1, …] and tags typed
    // values (~r = URI) — the live SaaS exporter answers in this form.
    func testExportResourceParsesCompactTransitForm() throws {
        let json = """
        ["^ ", "~:id", "~u0198f2a0-0000-0000-0000-000000000000",
               "~:name", "Board 1",
               "~:filename", "Board 1.png",
               "~:mtype", "image/png",
               "~:uri", "~rhttps://design.penpot.app/assets/by-id/123"]
        """
        let resource = try XCTUnwrap(
            PenpotClient.exportResource(fromTransit: Data(json.utf8), baseURL: base))
        XCTAssertEqual(resource.filename, "Board 1.png")
        XCTAssertEqual(resource.uri?.absoluteString, "https://design.penpot.app/assets/by-id/123")
    }

    // A ~r-tagged uri in the verbose object form must be untagged too; a resource with a
    // uri but no filename is still usable (the client falls back to its own name).
    func testExportResourceUntagsURIAndToleratesMissingFilename() throws {
        let json = #"{"~:uri": "~rhttps://design.penpot.app/assets/by-id/9", "~:mtype": "image/png"}"#
        let resource = try XCTUnwrap(
            PenpotClient.exportResource(fromTransit: Data(json.utf8), baseURL: base))
        XCTAssertNil(resource.filename)
        XCTAssertEqual(resource.uri?.absoluteString, "https://design.penpot.app/assets/by-id/9")
    }

    // Penpot registers a CUSTOM transit tag "uri" (multi-char), so the live server sends
    // the uri as a tagged map {"~#uri": …} (verbose) or ["~#uri", …] (compact) — exactly
    // the case that once surfaced as a bogus "no export service". Verified live 2026-08-06.
    func testExportResourceUnwrapsCustomTaggedURI() throws {
        let verbose = """
        {"~:id": "~uabc", "~:filename": "metaball_cover_penpot.png", "~:mtype": "image/png",
         "~:uri": {"~#uri": "https://design.penpot.app/assets/by-id/42"}}
        """
        let fromVerbose = try XCTUnwrap(
            PenpotClient.exportResource(fromTransit: Data(verbose.utf8), baseURL: base))
        XCTAssertEqual(fromVerbose.filename, "metaball_cover_penpot.png")
        XCTAssertEqual(fromVerbose.uri?.absoluteString, "https://design.penpot.app/assets/by-id/42")

        let compact = """
        ["^ ", "~:filename", "x.png", "~:uri", ["~#uri", "https://design.penpot.app/assets/by-id/7"]]
        """
        let fromCompact = try XCTUnwrap(
            PenpotClient.exportResource(fromTransit: Data(compact.utf8), baseURL: base))
        XCTAssertEqual(fromCompact.uri?.absoluteString, "https://design.penpot.app/assets/by-id/7")
    }

    // Non-transit bodies (HTML error pages, arrays) must yield nil, not a bogus resource.
    func testExportResourceRejectsGarbage() {
        XCTAssertNil(PenpotClient.exportResource(fromTransit: Data("<html></html>".utf8), baseURL: base))
        XCTAssertNil(PenpotClient.exportResource(fromTransit: Data("[1,2]".utf8), baseURL: base))
        XCTAssertNil(PenpotClient.exportResource(fromTransit: Data(#"{"~:id": "~ux"}"#.utf8), baseURL: base))
        XCTAssertNil(PenpotClient.exportResource(fromTransit: Data(#"["^ ", "~:id", "~ux"]"#.utf8), baseURL: base))
    }

    // MARK: Errors & files

    // Exporter error bodies are transit-encoded — the summary must surface the short
    // hint/code, stripped of the "~:" tag, not the raw body.
    func testTransitErrorSummary() {
        let error = PenpotError.server(
            status: 400,
            body: #"{"~:type": "~:validation", "~:code": "~:spec-validation"}"#)
        XCTAssertEqual(error.errorDescription,
                       String(format: .appLocalized("Request failed (%lld): %@"), 400, "spec-validation"))
    }

    func testExportedDocumentFileSanitizesName() throws {
        let doc = try ExportedDocument.file(data: Data("x".utf8), filename: "a/b\\c:d.png")
        XCTAssertEqual(doc.url.lastPathComponent, "a-b-c-d.png")
        let fallback = try ExportedDocument.file(data: Data("x".utf8), filename: "  ",
                                                 fallbackName: "board.png")
        XCTAssertEqual(fallback.url.lastPathComponent, "board.png")
    }

    // The .penpot path delegates to file(...) and must keep its exact old behavior.
    func testExportedDocumentPenpotKeepsBehavior() throws {
        XCTAssertEqual(try ExportedDocument.penpot(data: Data("x".utf8), name: "My File").url.lastPathComponent,
                       "My File.penpot")
        XCTAssertEqual(try ExportedDocument.penpot(data: Data("x".utf8), name: "a/b").url.lastPathComponent,
                       "a-b.penpot")
        XCTAssertEqual(try ExportedDocument.penpot(data: Data("x".utf8), name: " ").url.lastPathComponent,
                       "file.penpot")
        XCTAssertEqual(try ExportedDocument.penpot(data: Data("x".utf8), name: "done.PENPOT").url.lastPathComponent,
                       "done.PENPOT")
    }
}
