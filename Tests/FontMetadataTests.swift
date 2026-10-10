import XCTest
@testable import PenpotiOS

/// Font-upload plumbing: container sniffing, metadata heuristics (the backend never
/// opens the font — the client's parse IS the stored metadata), and chunk math.
final class FontMetadataTests: XCTestCase {

    // MARK: Container sniffing

    func testSniffMimeType() {
        XCTAssertEqual(FontFileMetadata.sniffMimeType(Data([0x00, 0x01, 0x00, 0x00, 0xFF])), "font/ttf")
        XCTAssertEqual(FontFileMetadata.sniffMimeType(Data("true".utf8)), "font/ttf")
        XCTAssertEqual(FontFileMetadata.sniffMimeType(Data("OTTO".utf8)), "font/otf")
        XCTAssertEqual(FontFileMetadata.sniffMimeType(Data("wOFF".utf8)), "font/woff")
        XCTAssertEqual(FontFileMetadata.sniffMimeType(Data("wOF2".utf8)), "font/woff2")
        XCTAssertNil(FontFileMetadata.sniffMimeType(Data([0x50, 0x4B, 0x03, 0x04])))   // zip
        XCTAssertNil(FontFileMetadata.sniffMimeType(Data("garbage".utf8)))
        XCTAssertNil(FontFileMetadata.sniffMimeType(Data([0x00, 0x01])))
    }

    // MARK: Name heuristics (the web's parse-font-weight word table)

    func testWeightFromName() {
        XCTAssertEqual(FontFileMetadata.weight(fromName: "Inter-ExtraLight"), 200)
        XCTAssertEqual(FontFileMetadata.weight(fromName: "Inter-Thin"), 100)
        XCTAssertEqual(FontFileMetadata.weight(fromName: "SemiBold"), 600)
        XCTAssertEqual(FontFileMetadata.weight(fromName: "DemiBold"), 600)
        XCTAssertEqual(FontFileMetadata.weight(fromName: "UltraBold"), 800)
        XCTAssertEqual(FontFileMetadata.weight(fromName: "Book"), 400)
        XCTAssertEqual(FontFileMetadata.weight(fromName: "Heavy"), 900)
        XCTAssertEqual(FontFileMetadata.weight(fromName: "BoldItalic"), 700)
        XCTAssertEqual(FontFileMetadata.weight(fromName: "Light"), 300)
        XCTAssertNil(FontFileMetadata.weight(fromName: "Display"))
    }

    func testItalicFromName() {
        XCTAssertTrue(FontFileMetadata.isItalic(name: "Inter-BoldItalic"))
        XCTAssertTrue(FontFileMetadata.isItalic(name: "Oblique"))
        XCTAssertFalse(FontFileMetadata.isItalic(name: "Inter-Bold"))
    }

    func testStrippedFamilyName() {
        XCTAssertEqual(FontFileMetadata.strippedFamilyName(from: "Inter-ExtraLight"), "Inter")
        XCTAssertEqual(FontFileMetadata.strippedFamilyName(from: "Work_Sans_Bold_Italic"), "Work Sans")
        XCTAssertEqual(FontFileMetadata.strippedFamilyName(from: "OpenSans"), "OpenSans")
    }

    // MARK: CoreText trait bucketing (midpoints of UIFont.Weight raw values)

    func testWeightBucketFromTrait() {
        XCTAssertEqual(FontFileMetadata.weightBucket(fromTrait: -0.80), 100)
        XCTAssertEqual(FontFileMetadata.weightBucket(fromTrait: -0.50), 200)
        XCTAssertEqual(FontFileMetadata.weightBucket(fromTrait: -0.30), 300)
        XCTAssertEqual(FontFileMetadata.weightBucket(fromTrait: 0.0), 400)
        XCTAssertEqual(FontFileMetadata.weightBucket(fromTrait: 0.23), 500)
        XCTAssertEqual(FontFileMetadata.weightBucket(fromTrait: 0.30), 600)
        XCTAssertEqual(FontFileMetadata.weightBucket(fromTrait: 0.40), 700)
        XCTAssertEqual(FontFileMetadata.weightBucket(fromTrait: 0.56), 800)
        XCTAssertEqual(FontFileMetadata.weightBucket(fromTrait: 0.62), 900)
    }

    // MARK: Family sanitizing (backend constraint: letters/digits/space/_.-, ≤ 250)

    func testSanitizedFamily() {
        XCTAssertEqual(FontFileMetadata.sanitizedFamily("Inter"), "Inter")
        XCTAssertEqual(FontFileMetadata.sanitizedFamily("Ærøskøbing 2.0"), "Ærøskøbing 2.0")
        XCTAssertEqual(FontFileMetadata.sanitizedFamily("Bad@Name#!"), "BadName")
        XCTAssertEqual(FontFileMetadata.sanitizedFamily("  spaced  "), "spaced")
        XCTAssertEqual(FontFileMetadata.sanitizedFamily(String(repeating: "a", count: 300)).count, 250)
    }

    // MARK: Filename fallback parse (woff/woff2 — CoreText can't open those)

    func testParseWoff2FallsBackToFilename() throws {
        var data = Data("wOF2".utf8)
        data.append(Data(repeating: 0, count: 64))
        let metadata = try XCTUnwrap(FontFileMetadata.parse(data: data, filename: "Inter-SemiBoldItalic.woff2"))
        XCTAssertEqual(metadata.family, "Inter")
        XCTAssertEqual(metadata.weight, 600)
        XCTAssertEqual(metadata.style, "italic")
        XCTAssertEqual(metadata.mimeType, "font/woff2")
    }

    func testParseRejectsNonFont() {
        XCTAssertNil(FontFileMetadata.parse(data: Data("not a font".utf8), filename: "x.ttf"))
    }

    // MARK: Chunk math + upload plumbing

    func testFontChunkCount() {
        XCTAssertEqual(PenpotClient.fontChunkCount(forSize: 1), 1)
        XCTAssertEqual(PenpotClient.fontChunkCount(forSize: 5 * 1024 * 1024), 1)
        XCTAssertEqual(PenpotClient.fontChunkCount(forSize: 10 * 1024 * 1024), 1)
        XCTAssertEqual(PenpotClient.fontChunkCount(forSize: 10 * 1024 * 1024 + 1), 2)
        XCTAssertEqual(PenpotClient.fontChunkCount(forSize: 25 * 1024 * 1024), 3)
    }

    // A transient-failure resend of a chunk that already landed: Penpot ≥ 2.18 rejects
    // it, and that rejection means the chunk is stored.
    func testDuplicateChunkCountsAsStored() {
        XCTAssertTrue(PenpotClient.isDuplicateChunk(
            #"{"type": "validation", "code": "duplicate-chunk-index", "hint": "chunk already uploaded"}"#))
        // `develop`'s name for it (seen live on a devenv backend).
        XCTAssertTrue(PenpotClient.isDuplicateChunk(
            #"{"type": "validation", "code": "chunk-already-exists", "sessionId": "s", "index": 0}"#))
        XCTAssertFalse(PenpotClient.isDuplicateChunk(
            #"{"type": "validation", "code": "chunk-too-large"}"#))
        XCTAssertFalse(PenpotClient.isDuplicateChunk("<html>bad gateway</html>"))
        XCTAssertFalse(PenpotClient.isDuplicateChunk(nil))
    }

    func testChunkMultipartBodyLayout() throws {
        let body = PenpotClient.multipartFormBody(
            boundary: "B",
            fields: [("session-id", "s-1"), ("index", "0")],
            file: (field: "content", filename: "chunk-0",
                   mimeType: "application/octet-stream", data: Data([0x01])))
        let text = try XCTUnwrap(String(data: body, encoding: .isoLatin1))
        XCTAssertTrue(text.contains("name=\"session-id\"\r\n\r\ns-1\r\n"))
        XCTAssertTrue(text.contains("name=\"index\"\r\n\r\n0\r\n"))
        XCTAssertTrue(text.contains("name=\"content\"; filename=\"chunk-0\"\r\nContent-Type: application/octet-stream"))
        XCTAssertTrue(text.hasSuffix("\r\n--B--\r\n"))
    }

    // MARK: Response decoding

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.penpot.decode(T.self, from: Data(json.utf8))
    }

    func testFontDownloadDecodes() throws {
        let download = try decode(PenpotClient.FontDownload.self,
                                  #"{"id": "d1", "uri": "https://x/assets/by-id/1", "name": "Inter.zip"}"#)
        XCTAssertEqual(download.name, "Inter.zip")
        XCTAssertEqual(download.uri, "https://x/assets/by-id/1")
    }

    // create-font-variant answers with the variant row; storage-file ids may be null.
    func testCreateFontVariantResponseDecodes() throws {
        let json = """
        {
          "id": "variant-1", "teamId": "team-1", "fontId": "font-1",
          "fontFamily": "Inter", "fontWeight": 600, "fontStyle": "normal",
          "otfFileId": null, "ttfFileId": "media-1", "woff1FileId": null, "woff2FileId": null,
          "createdAt": "2026-08-06T10:00:00.000Z", "modifiedAt": "2026-08-06T10:00:00.000Z"
        }
        """
        let variant = try decode(FontVariant.self, json)
        XCTAssertEqual(variant.fontFamily, "Inter")
        XCTAssertEqual(variant.fontWeight, 600)
    }
}
