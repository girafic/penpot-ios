import UIKit

/// Board renders by the exporter (`/api/export`, the service behind board export): PNG
/// previews for boards Penpot has no thumbnail of, and vector PDFs for the board detail.
///
/// Board thumbnails (`get-file-object-thumbnails`) are drawn by Penpot's *web editor*, and
/// only by its classic renderer: files that were imported, or only ever opened with the
/// WebGL renderer, have none. And a thumbnail is a bitmap that blurs when zoomed, while
/// the PDF keeps text and shapes as vectors.
///
/// The exporter is shared and scarce: each instance has a pool of 5 headless browsers and
/// gives up after waiting 10 s for one ("ResourceRequest timed out"). So:
/// - renders start only for boards on screen, one at a time, PNGs and PDFs in one queue;
/// - a board that scrolls away gives up its place in the queue, but a render that already
///   started runs to the end and is cached. Cancelling the request would not stop the job
///   on the server, and the next one would occupy another browser.
/// - results are cached on disk per file revision;
/// - a busy exporter gets a pause (``busyPause``), and an error that would repeat for every
///   board (no exporter, Cloudflare, rate limit) leaves the server alone for the session.
actor BoardPreviewRenderer {
    static let shared = BoardPreviewRenderer()

    enum Kind: Hashable, Sendable {
        /// A PNG at ``targetPixels`` for cards.
        case preview
        /// A vector PDF of the board, for the board detail.
        case vector

        var fileExtension: String { self == .preview ? "png" : "pdf" }

        /// Whether `data` is what the exporter was asked for, and not, say, an error page.
        func isValid(_ data: Data) -> Bool {
            switch self {
            case .preview:
                return UIImage(data: data) != nil
            case .vector:
                guard let provider = CGDataProvider(data: data as CFData),
                      let document = CGPDFDocument(provider) else { return false }
                return document.numberOfPages > 0
            }
        }
    }

    struct Key: Hashable, Sendable {
        let server: String
        let fileID: String
        let boardID: String
        /// The file's `revn`: a new revision renders again.
        let revision: Int
        var kind: Kind = .preview

        /// Raised when the on-device renderer (``PenpotSVG``) draws differently, so renders
        /// cached by an older version are made again.
        static let renderVersion = 5
        var fileName: String { "\(fileID)_\(boardID)_\(revision)_v\(Self.renderVersion).\(kind.fileExtension)" }
        /// Files of this board's older revisions start with this (and share the extension).
        var boardPrefix: String { "\(fileID)_\(boardID)_" }
    }

    /// Long side of a preview in pixels: sharp on a card and in the board detail at
    /// fit-to-screen on a 3× phone.
    static let targetPixels: Double = 1200

    /// The exporter scale that renders a `width` × `height` board at ``targetPixels`` on
    /// its long side. Never enlarges: small boards render at 1.
    static func scale(width: Double, height: Double) -> Double {
        let longSide = max(width, height)
        guard longSide > 0 else { return 1 }
        return min(1, max(0.05, targetPixels / longSide))
    }

    /// What a failed render means for the next ones.
    enum Outcome: Equatable {
        /// Only this board: not retried this session.
        case boardFailed
        /// The exporter is overloaded: pause the server for ``busyPause``.
        case serverBusy
        /// Every board would fail the same way: leave the server alone for the session.
        case serverUnusable
    }

    static func outcome(of error: Error) -> Outcome {
        switch error {
        case PenpotError.exporterUnavailable, PenpotError.forbidden, PenpotError.unauthorized,
             PenpotError.server(status: 429, body: _):
            return .serverUnusable
        case PenpotError.server(status: 502...503, body: _):
            return .serverBusy
        case PenpotError.server(status: 500, body: let body?) where body.contains("timeout"):
            // The exporter's browser pool had no free browser within 10 s.
            return .serverBusy
        default:
            // Including a gateway timeout (504, Cloudflare gives up on a long render) and our
            // own request timeout: that board is too heavy to render in time, and retrying
            // it would hold one of the exporter's few browsers for minutes again.
            return .boardFailed
        }
    }

    private let directory: URL?
    private let maxConcurrent: Int
    private let busyPause: TimeInterval
    private let images = NSCache<NSString, UIImage>()
    private let documents = NSCache<NSString, NSData>()
    private var running = 0
    private var queue: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    private var inFlight: [Key: (task: Task<Data?, Never>, waiters: Int)] = [:]
    /// Renders past the queue: they finish even when every caller has left.
    private var rendering: Set<Key> = []
    private var failed: Set<Key> = []
    private var unusableServers: Set<String> = []
    private var pausedUntil: [String: Date] = [:]

    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("BoardPreviews", isDirectory: true),
         maxConcurrent: Int = 1,
         busyPause: TimeInterval = 60) {
        self.directory = directory
        self.maxConcurrent = maxConcurrent
        self.busyPause = busyPause
    }

    /// The server can't be asked right now: unusable this session, or pausing.
    private func isResting(_ server: String) -> Bool {
        unusableServers.contains(server) || (pausedUntil[server].map { $0 > Date() } ?? false)
    }

    /// The preview for `key`: from memory, from disk, or rendered by `render` (PNG bytes).
    /// `nil` when it can't be had; a cancelled caller gives up its place in the queue.
    func image(for key: Key, render: @escaping @Sendable () async throws -> Data) async -> UIImage? {
        if let image = images.object(forKey: key.fileName as NSString) { return image }
        guard let data = await data(for: key, render: render),
              let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: key.fileName as NSString)
        return image
    }

    /// The preview for `key` if it is already cached; never renders.
    func cachedImage(for key: Key) -> UIImage? {
        if let image = images.object(forKey: key.fileName as NSString) { return image }
        guard let data = loadFromDisk(key), let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: key.fileName as NSString)
        return image
    }

    /// The board's vector PDF (`key.kind == .vector`), cached like previews.
    func pdf(for key: Key, render: @escaping @Sendable () async throws -> Data) async -> Data? {
        if let data = documents.object(forKey: key.fileName as NSString) { return data as Data }
        guard let data = await data(for: key, render: render) else { return nil }
        documents.setObject(data as NSData, forKey: key.fileName as NSString)
        return data
    }

    /// Drops everything cached, on disk too, and forgets failures (Settings → Clear image cache).
    func clearCache() {
        images.removeAllObjects()
        documents.removeAllObjects()
        failed = []
        unusableServers = []
        pausedUntil = [:]
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - Rendering

    /// From disk, or rendered (one at a time, shared by every caller of the same key).
    private func data(for key: Key, render: @escaping @Sendable () async throws -> Data) async -> Data? {
        if let data = loadFromDisk(key) { return data }
        guard !failed.contains(key), !isResting(key.server) else { return nil }

        let task: Task<Data?, Never>
        if let entry = inFlight[key] {
            task = entry.task
            inFlight[key]?.waiters += 1
        } else {
            task = Task { await self.run(key, render) }
            inFlight[key] = (task, 1)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.leave(key) }
        }
    }

    private func run(_ key: Key, _ render: @Sendable () async throws -> Data) async -> Data? {
        defer { inFlight[key] = nil }
        guard await acquire() else { return nil }
        defer { release() }
        // Queued while the server went to rest, or every caller left in the meantime.
        guard !Task.isCancelled, !isResting(key.server) else { return nil }
        rendering.insert(key)
        defer { rendering.remove(key) }
        do {
            let data = try await render()
            guard key.kind.isValid(data) else {
                failed.insert(key)
                return nil
            }
            store(data, for: key)
            return data
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                return nil
            }
            switch Self.outcome(of: error) {
            case .boardFailed: failed.insert(key)
            case .serverBusy: pausedUntil[key.server] = Date().addingTimeInterval(busyPause)
            case .serverUnusable: unusableServers.insert(key.server)
            }
            NSLog("BoardPreviewRenderer — %@ (%@) failed: %@", key.boardID,
                  key.kind.fileExtension, String(describing: error))
            return nil
        }
    }

    /// A caller was cancelled. When the last one leaves a render that is still queued, it
    /// leaves the queue; one that started runs on (see the type's note).
    private func leave(_ key: Key) {
        guard let entry = inFlight[key] else { return }
        inFlight[key]?.waiters -= 1
        if entry.waiters <= 1, !rendering.contains(key) {
            entry.task.cancel()
        }
    }

    // MARK: - Concurrency limit

    /// Waits for one of the ``maxConcurrent`` slots. `false` when cancelled while queued.
    private func acquire() async -> Bool {
        if running < maxConcurrent {
            running += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.append((id, continuation))
            }
        } onCancel: {
            Task { await self.dropFromQueue(id) }
        }
    }

    /// Hands the slot straight to the next in the queue, or frees it.
    private func release() {
        if queue.isEmpty {
            running -= 1
        } else {
            queue.removeFirst().continuation.resume(returning: true)
        }
    }

    private func dropFromQueue(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue.remove(at: index).continuation.resume(returning: false)
    }

    // MARK: - Disk cache

    private func loadFromDisk(_ key: Key) -> Data? {
        guard let url = directory?.appendingPathComponent(key.fileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The cached bytes for `key`, from memory or disk; never renders.
    func cachedData(for key: Key) -> Data? {
        if key.kind == .vector, let data = documents.object(forKey: key.fileName as NSString) {
            return data as Data
        }
        return loadFromDisk(key)
    }

    /// Writes a render (also one made on the device, see ``LocalBoardRenderer``) and
    /// deletes the board's renders of the same kind from older revisions.
    func store(_ data: Data, for key: Key) {
        if key.kind == .vector { documents.setObject(data as NSData, forKey: key.fileName as NSString) }
        guard let directory else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        where name.hasPrefix(key.boardPrefix) && name.hasSuffix(".\(key.kind.fileExtension)") {
            try? manager.removeItem(at: directory.appendingPathComponent(name))
        }
        try? data.write(to: directory.appendingPathComponent(key.fileName), options: .atomic)
    }
}
