import XCTest
@testable import PenpotiOS

/// `.penpot` import: magic-byte version sniffing, multipart form building, and the SSE
/// terminal-event grammar (`end` = success with the new file ids, `error` = failure
/// under an already-committed 200).
final class ImportBinfileTests: XCTestCase {

    // MARK: Version sniffing and the `version` field

    /// 2.18+ rejected the text field "3" (`[:enum 1 3]`) and a zip could not be
    /// imported at all; Penpot's web app sends no version, and neither does the app now.
    func testZipArchiveSendsNoVersion() {
        let fields = PenpotClient.importFields(name: "Snow globe (demo)", projectID: "p-1",
                                               version: 3, sendVersion: true)
        XCTAssertEqual(fields.map(\.name), ["name", "project-id"])
    }

    /// Servers up to 2.17 don't detect the format and default to 3, so a legacy archive
    /// names its version, unless the retry drops it.
    func testLegacyArchiveSendsVersionUntilRejected() {
        let first = PenpotClient.importFields(name: "Old", projectID: "p-1", version: 1, sendVersion: true)
        XCTAssertEqual(first.map(\.name), ["name", "project-id", "version"])
        XCTAssertEqual(first.last?.value, "1")
        let retry = PenpotClient.importFields(name: "Old", projectID: "p-1", version: 1, sendVersion: false)
        XCTAssertEqual(retry.map(\.name), ["name", "project-id"])
    }

    /// The 400 a 2.19 devenv answered for `version=3`; other 400s are no reason to retry.
    func testRecognizesRejectedVersionField() {
        let rejected = #"{"~:type":"~:validation","~:code":"~:params-validation","~:explain":"Errors:\n[{:path [0 :version], :in [:version], :schema [:enum 1 3], :value \"3\"}]"}"#
        XCTAssertTrue(PenpotClient.rejectsVersionField(rejected))
        let otherField = #"{"~:type":"~:validation","~:code":"~:params-validation","~:explain":"Errors:\n[{:path [0 :project-id], :in [:project-id]}]"}"#
        XCTAssertFalse(PenpotClient.rejectsVersionField(otherField))
        XCTAssertFalse(PenpotClient.rejectsVersionField(#"{"~:type":"~:validation","~:code":"~:unsupported-version"}"#))
        XCTAssertFalse(PenpotClient.rejectsVersionField(nil))
    }

    func testBinfileVersionSniffing() {
        // Modern exports are zips ("PK\x03\x04").
        XCTAssertEqual(PenpotClient.binfileVersion(of: Data([0x50, 0x4B, 0x03, 0x04, 0xFF])), 3)
        // Legacy binfile-v1 header mark + magic.
        XCTAssertEqual(PenpotClient.binfileVersion(of: Data([0x01, 0x0B, 0x1A, 0x86, 0x00])), 1)
        XCTAssertNil(PenpotClient.binfileVersion(of: Data("not a penpot file".utf8)))
        XCTAssertNil(PenpotClient.binfileVersion(of: Data([0x50, 0x4B])))
        XCTAssertNil(PenpotClient.binfileVersion(of: Data()))
    }

    // MARK: Multipart form body

    func testMultipartFormBodyLayout() throws {
        let body = PenpotClient.multipartFormBody(
            boundary: "B",
            fields: [("name", "My File"), ("project-id", "p-1"), ("version", "3")],
            file: (field: "file", filename: "My File.penpot",
                   mimeType: "application/zip", data: Data([0x50, 0x4B, 0x03, 0x04])))
        let text = try XCTUnwrap(String(data: body, encoding: .isoLatin1))

        // Plain fields come first, each with a name-only disposition.
        XCTAssertTrue(text.contains("--B\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nMy File\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"project-id\"\r\n\r\np-1\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"version\"\r\n\r\n3\r\n"))
        // The file part carries filename + content type, and the body ends with the
        // closing boundary.
        XCTAssertTrue(text.contains(
            "Content-Disposition: form-data; name=\"file\"; filename=\"My File.penpot\"\r\nContent-Type: application/zip\r\n\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n--B--\r\n"))
        // The fields precede the file part.
        let nameRange = try XCTUnwrap(text.range(of: "name=\"name\""))
        let fileRange = try XCTUnwrap(text.range(of: "name=\"file\""))
        XCTAssertLessThan(nameRange.lowerBound, fileRange.lowerBound)
    }

    // MARK: SSE terminal events

    func testSSEOutcomeSuccess() {
        let body = """
        event: progress
        data: {"~:section": "~:manifest"}

        event: progress
        data: {"~:section": "~:file"}

        event: end
        data: ["~u3f1c1e70-0000-0000-0000-000000000000"]

        """
        let outcome = PenpotClient.sseOutcome(from: body)
        XCTAssertEqual(outcome.endPayload, #"["~u3f1c1e70-0000-0000-0000-000000000000"]"#)
        XCTAssertNil(outcome.errorPayload)
    }

    func testSSEOutcomeError() {
        let body = """
        event: progress
        data: {"~:section": "~:manifest"}

        event: error
        data: {"~:type": "~:validation", "~:code": "~:invalid-penpot-file", "~:hint": "invalid penpot file"}

        """
        let outcome = PenpotClient.sseOutcome(from: body)
        XCTAssertNil(outcome.endPayload)
        XCTAssertEqual(outcome.errorPayload,
                       #"{"~:type": "~:validation", "~:code": "~:invalid-penpot-file", "~:hint": "invalid penpot file"}"#)
        // The error payload feeds PenpotError.server — its transit keys must surface.
        let error = PenpotError.server(status: 400, body: outcome.errorPayload)
        XCTAssertTrue(error.errorDescription?.contains("invalid penpot file") == true)
    }

    // A stream that never terminated (connection cut mid-import) yields neither payload.
    func testSSEOutcomeUnterminated() {
        let body = "event: progress\ndata: {}\n\n"
        let outcome = PenpotClient.sseOutcome(from: body)
        XCTAssertNil(outcome.endPayload)
        XCTAssertNil(outcome.errorPayload)
    }
}
