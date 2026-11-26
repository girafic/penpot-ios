import UIKit
import WebKit

/// Renders boards on the device: the page's `get-page` data becomes an SVG document per
/// board (``PenpotSVG``), a hidden `WKWebView` lays it out, and `createPDF` turns it into a
/// vector PDF. Text is laid out from its content like Penpot's editor does, not from
/// stored positions.
///
/// WebKit only draws here; the app shows the PDFs natively (``BoardVectorView``), which
/// zooms without WebKit's 10× limit. PDFs land in ``BoardPreviewRenderer``'s cache.
///
/// Two boards render at a time, each in its own web view (and web content process), the
/// most recently requested first: that is what is on screen. A request whose view went away
/// leaves the queue. A page's data is fetched and parsed once for all its boards; the last
/// two parsed pages stay in memory.
@MainActor
final class LocalBoardRenderer {
    static let shared = LocalBoardRenderer()

    private struct Job {
        let board: Board
        let renders: BoardRenders
        var waiters: [UUID: CheckedContinuation<Data?, Never>]
    }

    private var jobs: [BoardPreviewRenderer.Key: Job] = [:]
    /// Pending job keys, oldest first; the newest runs next.
    private var order: [BoardPreviewRenderer.Key] = []
    private let workers = 2
    private var running = 0
    private var pages: [String: Task<PenpotSVG.Page, Error>] = [:]
    private var pageOrder: [String] = []
    private var idleWebViews: [WKWebView] = []

    /// The board's PDF, rendered on the device if it isn't cached yet.
    func pdf(of board: Board, using renders: BoardRenders) async throws -> Data {
        let key = renders.key(for: board, kind: .vector)
        if let data = await BoardPreviewRenderer.shared.cachedData(for: key) { return data }
        let waiter = UUID()
        let data = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                enqueue(key, board: board, renders: renders, waiter: waiter, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in self.leave(key, waiter: waiter) }
        }
        guard let data else { throw CancellationError() }
        return data
    }

    /// The page's shapes outside any board, and the paint order of its root shapes, for the
    /// page canvas; from the same page data the boards are drawn from. Islands draw through
    /// ``pdf(of:using:)`` as boards whose id is their ``PenpotSVG/Island/id``.
    func islands(onPage pageID: String, using renders: BoardRenders) async
        -> (islands: [PenpotSVG.Island], layers: [String: Int])? {
        guard let page = try? await page(pageID, using: renders, revision: renders.revision ?? 0) else { return nil }
        return (page.islands, page.layers)
    }

    // MARK: - Queue

    private func enqueue(_ key: BoardPreviewRenderer.Key, board: Board, renders: BoardRenders,
                         waiter: UUID, continuation: CheckedContinuation<Data?, Never>) {
        if jobs[key] != nil {
            jobs[key]?.waiters[waiter] = continuation
            order.removeAll { $0 == key }
        } else {
            jobs[key] = Job(board: board, renders: renders, waiters: [waiter: continuation])
        }
        order.append(key)
        runNext()
    }

    /// A caller went away: it stops waiting, and a job nobody waits for leaves the queue.
    private func leave(_ key: BoardPreviewRenderer.Key, waiter: UUID) {
        guard let continuation = jobs[key]?.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(returning: nil)
        if jobs[key]?.waiters.isEmpty == true, order.contains(key) {
            jobs[key] = nil
            order.removeAll { $0 == key }
        }
    }

    private func runNext() {
        while running < workers, let key = order.popLast(), let job = jobs[key] {
            running += 1
            let webView = idleWebViews.popLast() ?? makeWebView()
            Task {
                var data: Data?
                do {
                    data = try await render(job.board, using: job.renders, in: webView, key: key)
                } catch {
                    NSLog("LocalBoardRenderer — %@ failed: %@", job.board.name, String(describing: error))
                }
                if let data { await BoardPreviewRenderer.shared.store(data, for: key) }
                for continuation in jobs.removeValue(forKey: key)?.waiters.values.map({ $0 }) ?? [] {
                    continuation.resume(returning: data)
                }
                idleWebViews.append(webView)
                running -= 1
                runNext()
            }
        }
        if running == 0, order.isEmpty {
            // Idle: let the web content processes go.
            idleWebViews.forEach { $0.removeFromSuperview() }
            idleWebViews = []
        }
    }

    // MARK: - Rendering

    private func render(_ board: Board, using renders: BoardRenders, in webView: WKWebView,
                        key: BoardPreviewRenderer.Key) async throws -> Data {
        let started = Date()
        let page = try await page(board.pageID, using: renders, revision: key.revision)
        let baseURL = renders.client.baseURL
        if let cookie = SessionStore.authCookie(for: baseURL) {
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
        let loader = PageLoader()
        webView.navigationDelegate = loader
        // An opaque web view paints white under the page, into the PDF too. That never
        // shows under a board, which fills its own rect, but the prototype's fixed layer
        // lies over the board and must be clear around its shapes.
        let transparent = PenpotSVG.Page.layer(board.id)?.fixed == true
        webView.isOpaque = !transparent
        webView.backgroundColor = transparent ? .clear : .white

        // Texts Penpot's editor never laid out have stale sizes, and so have the flex
        // layouts around them: WebKit lays the board out first, as the editor would.
        var layout: [String: CGRect] = [:]
        if page.needsLayout(board: board.id), let probe = page.layoutProbe(board: board.id) {
            try await loader.load(probe, baseURL: baseURL, in: webView)
            await fontsLoaded(in: webView)
            if let json = try? await webView.evaluateJavaScript(PenpotSVG.layoutScript) as? String {
                layout = page.layout(measured: json, board: board.id)
            }
        }
        guard let drawing = page.drawing(board: board.id, layout: layout) else { throw PenpotError.invalidResponse }
        try await loader.load(drawing.html, baseURL: baseURL, in: webView)
        await fontsLoaded(in: webView)
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(origin: .zero, size: drawing.size)
        let data = try await webView.pdf(configuration: configuration)
        NSLog("LocalBoardRenderer — %@ in %.2f s (%.0f KB SVG%@)", board.name,
              Date().timeIntervalSince(started), Double(drawing.html.utf8.count) / 1000,
              layout.isEmpty ? "" : ", laid out")
        return data
    }

    /// Fonts come from Penpot (`@font-face`); text laid out before they arrive would be
    /// measured and cut into the PDF in a fallback face. Layout is forced first, which is
    /// what requests the fonts. A font that never loads mustn't hold the board.
    private func fontsLoaded(in webView: WKWebView) async {
        _ = try? await webView.callAsyncJavaScript(
            "document.body.getBoundingClientRect(); await Promise.race([document.fonts.ready, new Promise(r => setTimeout(r, 5000))]); return true",
            contentWorld: .page)
    }

    /// The parsed page, fetched once for all its boards.
    private func page(_ pageID: String, using renders: BoardRenders, revision: Int) async throws -> PenpotSVG.Page {
        let key = "\(renders.client.baseURL.absoluteString)|\(renders.fileID)|\(pageID)|\(revision)"
        if let task = pages[key] {
            pageOrder.removeAll { $0 == key }
            pageOrder.append(key)
            return try await task.value
        }
        let task = Task<PenpotSVG.Page, Error> {
            let json = try await renders.client.pageJSON(fileID: renders.fileID, pageID: pageID)
            let server = renders.client.baseURL
            let page = try await Task.detached(priority: .userInitiated) {
                try PenpotSVG.Page(pageJSON: json, server: server)
            }.value
            if let teamID = renders.teamID, !page.customFontIDs.isEmpty {
                page.customFonts = (try? await renders.client.fontVariants(teamID: teamID)) ?? []
            }
            return page
        }
        pages[key] = task
        pageOrder.append(key)
        while pageOrder.count > 2 { pages[pageOrder.removeFirst()] = nil }
        do {
            return try await task.value
        } catch {
            pages[key] = nil
            pageOrder.removeAll { $0 == key }
            throw error
        }
    }

    /// A worker's web view, kept for the next board and released when the queue runs dry.
    ///
    /// It sits in the window, at the bottom, covered by the app's own views: outside any
    /// window WebKit throttles it (timers and font loads stall the render), and a view taken
    /// out of the window after loading never finishes `createPDF`.
    private func makeWebView() -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        webView.isUserInteractionEnabled = false
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?
            .insertSubview(webView, at: 0)
        return webView
    }

    /// Bridges one `loadHTMLString` to async/await.
    private final class PageLoader: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?

        func load(_ html: String, baseURL: URL, in webView: WKWebView) async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        private func finish(_ error: Error?) {
            if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            finish(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            finish(PenpotError.invalidResponse)
        }
    }
}
