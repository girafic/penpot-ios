import UIKit
import XCTest
@testable import PenpotiOS

/// The exporter fallback for boards without a Penpot thumbnail: it must stay gentle with the
/// shared exporter (limit, dedupe, give up, cancel) and never render the same thing twice.
final class BoardPreviewRendererTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardPreviewRendererTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func key(_ board: String, server: String = "https://penpot.test", revision: Int = 1)
        -> BoardPreviewRenderer.Key {
        .init(server: server, fileID: "file", boardID: board, revision: revision)
    }

    private static let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        .pngData { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }

    private static let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 50))
        .pdfData { context in
            context.beginPage()
            ("Board" as NSString).draw(at: CGPoint(x: 10, y: 10), withAttributes: nil)
        }

    // The board detail's PDF shares the preview's queue and cache, but neither may evict
    // the other, and an error page posing as a PDF is not cached.
    func testVectorPDFIsCachedBesideThePreviewAndValidated() async {
        let renderer = BoardPreviewRenderer(directory: directory)
        var vector = key("a")
        vector.kind = .vector
        XCTAssertEqual(vector.fileName, "file_a_1_v6.pdf")

        _ = await renderer.image(for: key("a")) { Self.png }
        let pdf = await renderer.pdf(for: vector) { Self.pdf }
        XCTAssertEqual(pdf, Self.pdf)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.sorted()
        XCTAssertEqual(files, ["file_a_1_v6.pdf", "file_a_1_v6.png"])

        var broken = key("b")
        broken.kind = .vector
        let notPDF = await renderer.pdf(for: broken) { Data("<html>busy</html>".utf8) }
        XCTAssertNil(notPDF)
    }

    func testCachedImageNeverRenders() async {
        let renderer = BoardPreviewRenderer(directory: directory)
        let missing = await renderer.cachedImage(for: key("a"))
        XCTAssertNil(missing)
        _ = await renderer.image(for: key("a")) { Self.png }
        let cached = await renderer.cachedImage(for: key("a"))
        XCTAssertNotNil(cached)
    }

    /// Counts renders and the most that ran at once.
    private actor Probe {
        private(set) var renders: [String] = []
        private(set) var peak = 0
        private var current = 0
        func begin(_ board: String) { renders.append(board); current += 1; peak = max(peak, current) }
        func end() { current -= 1 }
    }

    func testScaleTargetsTheLongSideAndNeverEnlarges() {
        XCTAssertEqual(BoardPreviewRenderer.scale(width: 2400, height: 1000), 0.5, accuracy: 0.0001)
        XCTAssertEqual(BoardPreviewRenderer.scale(width: 800, height: 3000), 0.4, accuracy: 0.0001)
        XCTAssertEqual(BoardPreviewRenderer.scale(width: 600, height: 400), 1)
        XCTAssertEqual(BoardPreviewRenderer.scale(width: 0, height: 0), 1)
        XCTAssertEqual(BoardPreviewRenderer.scale(width: 1_000_000, height: 10), 0.05)
    }

    func testRendersAtMostTwoAtOnceAndOnlyOncePerBoard() async {
        let renderer = BoardPreviewRenderer(directory: directory, maxConcurrent: 2)
        let probe = Probe()
        let boards = ["a", "b", "c", "a"]   // "a" twice: one render, two callers
        let results = await withTaskGroup(of: Bool.self) { group in
            for board in boards {
                group.addTask {
                    await renderer.image(for: self.key(board)) {
                        await probe.begin(board)
                        try await Task.sleep(for: .milliseconds(150))
                        await probe.end()
                        return Self.png
                    } != nil
                }
            }
            return await group.reduce(into: [Bool]()) { $0.append($1) }
        }
        XCTAssertEqual(results, [true, true, true, true])
        let renders = await probe.renders
        XCTAssertEqual(renders.sorted(), ["a", "b", "c"])
        let peak = await probe.peak
        XCTAssertLessThanOrEqual(peak, 2)
    }

    func testRenderedPreviewIsReadFromDiskNextLaunch() async {
        let first = BoardPreviewRenderer(directory: directory)
        _ = await first.image(for: key("a")) { Self.png }
        let relaunched = BoardPreviewRenderer(directory: directory)
        let image = await relaunched.image(for: key("a")) {
            XCTFail("rendered again although it was on disk")
            return Self.png
        }
        XCTAssertNotNil(image)
        // A new file revision renders again and replaces the old file.
        let probe = Probe()
        _ = await relaunched.image(for: key("a", revision: 2)) { await probe.begin("a"); return Self.png }
        let renders = await probe.renders
        XCTAssertEqual(renders, ["a"])
        let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["file_a_2_v6.png"])
    }

    func testServerIsLeftAloneAfterTheExporterIsMissing() async {
        let renderer = BoardPreviewRenderer(directory: directory)
        let probe = Probe()
        _ = await renderer.image(for: key("a")) {
            await probe.begin("a")
            throw PenpotError.exporterUnavailable
        }
        let other = await renderer.image(for: key("b")) {
            await probe.begin("b")
            return Self.png
        }
        XCTAssertNil(other)
        let renders = await probe.renders
        XCTAssertEqual(renders, ["a"])
        // Another server is unaffected.
        let elsewhere = await renderer.image(for: key("b", server: "https://other.test")) { Self.png }
        XCTAssertNotNil(elsewhere)
    }

    // Cancelling the request would not stop the exporter's job, and the next render would
    // take another of its few browsers: a started render finishes and is cached.
    func testStartedRenderFinishesAndIsCachedWhenTheCallerLeaves() async throws {
        let renderer = BoardPreviewRenderer(directory: directory)
        let probe = Probe()
        let leaving = Task {
            await renderer.image(for: key("a")) {
                await probe.begin("a")
                try await Task.sleep(for: .milliseconds(300))
                return Self.png
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        leaving.cancel()                                 // scrolled away mid-render
        let back = await renderer.image(for: key("a")) {
            XCTFail("rendered twice")
            return Self.png
        }
        XCTAssertNotNil(back)
        let renders = await probe.renders
        XCTAssertEqual(renders, ["a"])
    }

    func testBusyExporterPausesTheServer() async throws {
        let renderer = BoardPreviewRenderer(directory: directory, busyPause: 0.3)
        let busy = #"{"~:type":"~:server-error","~:code":"~:timeout","~:hint":"ResourceRequest timed out"}"#
        _ = await renderer.image(for: key("a")) { throw PenpotError.server(status: 500, body: busy) }
        let probe = Probe()
        let duringPause = await renderer.image(for: key("b")) { await probe.begin("b"); return Self.png }
        XCTAssertNil(duringPause)
        try await Task.sleep(for: .milliseconds(400))
        // Busy is not the board's fault: both are tried again after the pause.
        let afterPause = await renderer.image(for: key("a")) { await probe.begin("a"); return Self.png }
        XCTAssertNotNil(afterPause)
        let renders = await probe.renders
        XCTAssertEqual(renders, ["a"])
    }

    func testErrorsAreSortedByWhatTheyMeanForTheNextBoards() {
        typealias R = BoardPreviewRenderer
        XCTAssertEqual(R.outcome(of: PenpotError.exporterUnavailable), .serverUnusable)
        XCTAssertEqual(R.outcome(of: PenpotError.forbidden), .serverUnusable)
        XCTAssertEqual(R.outcome(of: PenpotError.server(status: 429, body: nil)), .serverUnusable)
        XCTAssertEqual(R.outcome(of: PenpotError.server(status: 503, body: nil)), .serverBusy)
        XCTAssertEqual(R.outcome(of: PenpotError.server(status: 500, body: #"{"~:code":"~:timeout"}"#)),
                       .serverBusy)
        // A render that runs out of time is that board's problem: retrying it would hold one
        // of the exporter's browsers for minutes again.
        XCTAssertEqual(R.outcome(of: PenpotError.server(status: 504, body: #"{"type":"https://developers.cloudflare.com/…"}"#)),
                       .boardFailed)
        XCTAssertEqual(R.outcome(of: URLError(.timedOut)), .boardFailed)
        XCTAssertEqual(R.outcome(of: PenpotError.server(status: 500, body: #"{"~:code":"~:render"}"#)),
                       .boardFailed)
        XCTAssertEqual(R.outcome(of: PenpotError.invalidResponse), .boardFailed)
    }

    func testCancelledCallerGivesUpItsPlaceInTheQueue() async throws {
        let renderer = BoardPreviewRenderer(directory: directory, maxConcurrent: 1)
        let probe = Probe()
        let blocking = Task {
            await renderer.image(for: key("a")) {
                await probe.begin("a")
                try await Task.sleep(for: .milliseconds(400))
                return Self.png
            }
        }
        try await Task.sleep(for: .milliseconds(100))   // "a" holds the only slot
        let queued = Task {
            await renderer.image(for: key("b")) {
                await probe.begin("b")
                return Self.png
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        queued.cancel()                                  // "b" scrolled away while queued
        let queuedResult = await queued.value
        let blockingResult = await blocking.value
        XCTAssertNil(queuedResult)
        XCTAssertNotNil(blockingResult)
        let renders = await probe.renders
        XCTAssertEqual(renders, ["a"])
    }
}
