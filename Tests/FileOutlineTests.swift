import XCTest
@testable import PenpotiOS

/// A big file's `get-file` takes tens of seconds; the board grid only needs its outline.
/// Reopening must cost a 304, and the cached outline must survive the round trip intact.
final class FileOutlineTests: XCTestCase {

    /// Answers every request with the next canned response and records the request.
    private final class StubProtocol: URLProtocol {
        static var response: (status: Int, headers: [String: String], body: Data) =
            (200, [:], Data())
        static var lastRequest: URLRequest?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.lastRequest = request
            let (status, headers, body) = Self.response
            let http = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private var directory: URL!
    private let server = URL(string: "https://penpot.test")!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileOutlineTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func stubbedClient() -> PenpotClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return PenpotClient(baseURL: server, session: URLSession(configuration: configuration))
    }

    /// One page holding a board, a loose rectangle and the root frame.
    private static let pageJSON = """
        {"id": "page-1", "name": "Cover", "objects": {
          "00000000-0000-0000-0000-000000000000": {"id": "00000000-0000-0000-0000-000000000000",
            "type": "frame", "parentId": "00000000-0000-0000-0000-000000000000",
            "shapes": ["board-1", "rect-1"]},
          "board-1": {"id": "board-1", "name": "Hero", "type": "frame",
            "parentId": "00000000-0000-0000-0000-000000000000",
            "selrect": {"x": 0, "y": 0, "width": 1440, "height": 900}},
          "rect-1": {"id": "rect-1", "type": "rect",
            "parentId": "00000000-0000-0000-0000-000000000000"}}}
        """

    func testFirstPageAloneBuildsTheSameSummaryAsTheWholeFile() throws {
        let page = try JSONDecoder().decode(PenpotPage.self, from: Data(Self.pageJSON.utf8))
        let summary = PenpotPageSummary(id: "page-1", page: page)
        XCTAssertEqual(summary.name, "Cover")
        XCTAssertEqual(summary.boards.map(\.name), ["Hero"])
        XCTAssertEqual(summary.canvasObjectCount, 1)
        XCTAssertEqual(summary.viewerIndex, ["board-1": 0])
    }

    func testCachedOutlineSurvivesTheRoundTripPerServer() throws {
        let page = try JSONDecoder().decode(PenpotPage.self, from: Data(Self.pageJSON.utf8))
        let outline = FileOutline(revision: 7, pages: [PenpotPageSummary(id: "page-1", page: page)])
        let cache = FileOutlineCache(directory: directory)
        cache.store(.init(etag: #"W/"abc""#, outline: outline), server: server, fileID: "file-1")

        let entry = try XCTUnwrap(cache.entry(server: server, fileID: "file-1"))
        XCTAssertEqual(entry.etag, #"W/"abc""#)
        XCTAssertEqual(entry.outline.revision, 7)
        XCTAssertEqual(entry.outline.pages.first?.boards, outline.pages.first?.boards)
        XCTAssertEqual(entry.outline.pages.first?.viewerIndex, ["board-1": 0])
        XCTAssertNil(cache.entry(server: URL(string: "http://localhost:3450")!, fileID: "file-1"))
    }

    func testUnchangedFileIsAnswered304AndNotRefetched() async throws {
        StubProtocol.response = (304, ["ETag": #"W/"abc""#], Data())
        let result = try await stubbedClient().fileOutline(id: "file-1", ifNoneMatch: #"W/"abc""#)
        guard case .notModified = result else { return XCTFail("expected notModified, got \(result)") }
        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), #"W/"abc""#)
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testChangedFileReturnsItsOutlineAndNewETag() async throws {
        let body = #"{"id": "file-1", "name": "Big", "revn": 12, "data": {"pages": ["page-1"], "pagesIndex": {"page-1": \#(Self.pageJSON)}}}"#
        StubProtocol.response = (200, ["ETag": #"W/"def""#, "Content-Type": "application/json"], Data(body.utf8))
        let result = try await stubbedClient().fileOutline(id: "file-1", ifNoneMatch: #"W/"abc""#)
        guard case .loaded(let outline, let etag) = result else { return XCTFail("expected loaded") }
        XCTAssertEqual(etag, #"W/"def""#)
        XCTAssertEqual(outline.revision, 12)
        XCTAssertEqual(outline.pages.map(\.name), ["Cover"])
        XCTAssertEqual(outline.pages.first?.boards.map(\.id), ["board-1"])
    }
}
