import Foundation
import Observation

/// A file open in the app, kept current while it is on screen: Penpot's notification
/// websocket (``PenpotNotifications``) says when someone saves a change and who else has
/// the file open, as the avatars in Penpot's workspace header do.
///
/// A change names its pages and shapes. Each touched page is fetched again (`get-page`),
/// and the boards that changed are drawn again under the revision they changed at
/// (``revision(of:)``); every other board keeps its cached render. Without the page's
/// earlier data (the first change on it), the boards holding the named shapes are the
/// changed ones; a deleted shape names no board, so then all of the page's boards are.
///
/// The screens of a file share one instance through the environment.
@MainActor @Observable
final class LiveFile {
    let fileID: String

    struct Peer: Identifiable, Equatable {
        /// The session: one person can have a file open twice.
        let id: String
        let profileID: String
    }

    /// The other sessions that have the file open, in the order they came.
    private(set) var peers: [Peer] = []
    private(set) var profiles: [String: Profile] = [:]
    /// Bumped when the file must be loaded again as a whole: its pages changed, a version
    /// was restored, or the connection was lost for a while.
    private(set) var reloadCount = 0
    private(set) var isDeleted = false

    /// Boards drawn again since the outline was loaded, with the revision they changed at.
    private var boardRevisions: [String: Int] = [:]
    /// The latest name and geometry of the boards of the pages fetched again.
    private var boards: [String: Board] = [:]
    private var pages: [String: (revision: Int, summary: PenpotPageSummary)] = [:]
    /// Each fetched page's boards' content, to tell which of them a change touched.
    private var fingerprints: [String: [String: Int]] = [:]
    /// The outline's revision: what everything not changed live is drawn at.
    private var baseRevision: Int?

    private var pending = Pending()
    private var flushTask: Task<Void, Never>?

    private struct Pending {
        var pages = Set<String>()
        var objects = Set<String>()
        var revision: Int?
        var pagesChanged = false
        var since: Date?
    }

    init(fileID: String) {
        self.fileID = fileID
    }

    /// The board's render revision, if it changed live after the outline was loaded.
    func revision(of boardID: String) -> Int? { boardRevisions[boardID] }

    /// The board as it is now, if its page was fetched again.
    func board(_ id: String) -> Board? { boards[id] }

    /// The page as it is now, if it changed live.
    func page(_ id: String) -> PenpotPageSummary? { pages[id]?.summary }

    /// The revision the page last changed at live: what its loose shapes are drawn at.
    func pageRevision(_ id: String) -> Int? { pages[id]?.revision }

    /// The outline was loaded (again) at `revision`: what changed up to it is in there now.
    func rebase(_ revision: Int?) {
        baseRevision = revision
        guard let revision else { return }
        boardRevisions = boardRevisions.filter { $0.value > revision }
        pages = pages.filter { $0.value.revision > revision }
        boards = boards.filter { entry in pages.values.contains { $0.summary.boards.contains { $0.id == entry.key } } }
    }

    // MARK: - Connection

    /// The connection, for as long as the file is open. Not a view's `.task`: SwiftUI
    /// cancels that as soon as a board detail is pushed over the file, which closed the
    /// socket exactly while someone looked at a board.
    nonisolated(unsafe) private var connection: Task<Void, Never>?

    deinit { connection?.cancel() }

    /// Keeps the file live until it is released, reconnecting with a growing pause. Changes
    /// made while it was away are unknown, so a reconnect loads the file again. The task
    /// holds the file weakly: closing the file ends it.
    func start(client: PenpotClient) {
        guard connection == nil else { return }
        let fileID = fileID
        connection = Task { [weak self] in
            var pause: Duration = .seconds(1)
            var connections = 0
            while !Task.isCancelled, self != nil {
                connections += 1
                if connections > 1 { self?.reloadCount += 1 }
                do {
                    for try await event in PenpotNotifications.events(server: client.baseURL, fileID: fileID) {
                        guard let self else { return }
                        pause = .seconds(1)
                        self.handle(event, client: client)
                    }
                } catch {
                    NSLog("LiveFile — connection closed: %@", String(describing: error))
                }
                self?.peers = []
                guard !Task.isCancelled, self?.isDeleted == false else { return }
                try? await Task.sleep(for: pause)
                pause = min(pause * 2, .seconds(60))
            }
        }
    }

    private func handle(_ event: PenpotNotifications.Event, client: PenpotClient) {
        switch event {
        case .present(let session, let profile):
            if !peers.contains(where: { $0.id == session }) {
                peers.append(Peer(id: session, profileID: profile))
            }
            if profiles[profile] == nil { Task { await loadProfiles(client: client) } }
        case .left(let session):
            peers.removeAll { $0.id == session }
        case .restored:
            boardRevisions = [:]
            boards = [:]
            pages = [:]
            fingerprints = [:]
            reloadCount += 1
        case .deleted:
            isDeleted = true
        case .fileChange(let revision, let pageIDs, let objectIDs, let pagesChanged):
            pending.pages.formUnion(pageIDs)
            pending.objects.formUnion(objectIDs)
            pending.revision = max(pending.revision ?? 0, revision ?? 0)
            pending.pagesChanged = pending.pagesChanged || pagesChanged
            if pending.since == nil { pending.since = Date() }
            scheduleFlush(client: client)
        }
    }

    /// Changes come in bursts while someone works: fetch once they pause, at least every
    /// two seconds.
    private func scheduleFlush(client: PenpotClient) {
        let waited = pending.since.map { Date().timeIntervalSince($0) } ?? 0
        let delay = max(0, min(0.6, 2 - waited))
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            let batch = pending
            pending = Pending()
            if batch.pagesChanged { reloadCount += 1 }
            for pageID in batch.pages {
                await refresh(pageID, objects: batch.objects, revision: batch.revision, client: client)
            }
        }
    }

    private func loadProfiles(client: PenpotClient) async {
        guard let fetched = try? await client.commentProfiles(fileID: fileID) else { return }
        profiles.merge(fetched) { _, new in new }
    }

    // MARK: - Pages

    struct PageState: Sendable {
        let summary: PenpotPageSummary
        let fingerprints: [String: Int]
        /// The boards holding the shapes a change named.
        let touched: Set<String>
        /// A named shape is gone (deleted): its board is unknown.
        let lostShapes: Bool
    }

    private func refresh(_ pageID: String, objects: Set<String>, revision: Int?, client: PenpotClient) async {
        guard let data = try? await client.pageJSON(fileID: fileID, pageID: pageID) else {
            NSLog("LiveFile — page %@ could not be fetched", pageID)
            return
        }
        var earlier = fingerprints[pageID]
        if earlier == nil { earlier = await cachedFingerprints(pageID, client: client) }
        guard let state = try? await Task.detached(priority: .userInitiated, operation: {
            try Self.read(data, pageID: pageID, objects: objects)
        }).value else { return }

        let revision = revision.flatMap { $0 > 0 ? $0 : nil }
            ?? (max(baseRevision ?? 0, boardRevisions.values.max() ?? 0) + 1)
        var changed = state.touched
        if let earlier {
            for (board, print) in state.fingerprints where earlier[board] != print { changed.insert(board) }
        } else if state.lostShapes {
            changed.formUnion(state.summary.boards.map(\.id))
        }
        NSLog("LiveFile — page %@ at revision %d: %d of %d boards changed", pageID, revision,
              changed.count, state.summary.boards.count)
        for board in changed { boardRevisions[board] = revision }
        for board in state.summary.boards { boards[board.id] = board }
        pages[pageID] = (revision, state.summary)
        fingerprints[pageID] = state.fingerprints
    }

    /// The fingerprints of the page the renderer still holds at the outline's revision: the
    /// page as it was before the first change on it.
    private func cachedFingerprints(_ pageID: String, client: PenpotClient) async -> [String: Int]? {
        guard let page = await LocalBoardRenderer.shared.cachedPage(pageID, fileID: fileID, server: client.baseURL,
                                                                     revision: baseRevision ?? 0) else { return nil }
        let rootIDs = page.objects[PenpotSVG.rootID]?["shapes"] as? [String] ?? []
        let boards = rootIDs.filter { page.objects[$0]?["type"] as? String == "frame" }
        return Self.fingerprints(of: boards, objects: page.objects)
    }

    nonisolated static func read(_ data: Data, pageID: String, objects named: Set<String>) throws -> PageState {
        let page = try JSONDecoder.penpot.decode(PenpotPage.self, from: data)
        let summary = PenpotPageSummary(id: pageID, page: page)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let objects = (json?["objects"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String: Any] }
        let boardIDs = Set(summary.boards.map(\.id))
        var touched = Set<String>()
        var lost = false
        for id in named {
            guard objects[id] != nil else {
                // A page id, or a shape that is gone.
                if id != pageID { lost = true }
                continue
            }
            var current = id
            var steps = 0
            while let parent = objects[current]?["parentId"] as? String, parent != current, steps < 200 {
                if boardIDs.contains(current) { touched.insert(current); break }
                current = parent
                steps += 1
            }
            if boardIDs.contains(current) { touched.insert(current) }
        }
        return PageState(summary: summary,
                         fingerprints: fingerprints(of: Array(boardIDs), objects: objects),
                         touched: touched, lostShapes: lost)
    }

    /// A hash of each board's shapes, as their JSON.
    nonisolated static func fingerprints(of boards: [String], objects: [String: [String: Any]]) -> [String: Int] {
        var result: [String: Int] = [:]
        for board in boards {
            var hasher = Hasher()
            var stack = [board]
            var seen = Set<String>()
            while let id = stack.popLast(), seen.insert(id).inserted {
                guard let shape = objects[id] else { continue }
                if let data = try? JSONSerialization.data(withJSONObject: shape, options: [.sortedKeys]) {
                    hasher.combine(data)
                }
                stack.append(contentsOf: (shape["shapes"] as? [Any])?.compactMap { $0 as? String } ?? [])
            }
            result[board] = hasher.finalize()
        }
        return result
    }
}
