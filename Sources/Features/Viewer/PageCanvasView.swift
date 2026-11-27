import SwiftUI
import UIKit

/// A page at its canvas positions, natively: pinch, pan and double-tap zoom in a
/// `UIScrollView`, read-only by construction.
///
/// Boards are vector PDFs rendered on the device (``LocalBoardRenderer``), drawn by
/// ``BoardVectorView``, so text stays readable at any zoom. Penpot's own thumbnail, where a
/// board has one, stands in for the moment that takes. Shapes straight on the canvas,
/// outside any board, come as islands (``PenpotSVG/Island``) once the page data is loaded,
/// layered with the boards in Penpot's paint order.
///
/// The page's comment threads show as pins at their canvas positions (filtered like on a
/// board); "add" mode drops a new one where the canvas is tapped, on the board under the
/// tap or, outside every board, on the page itself as Penpot does. A pin moves by touch
/// and hold, then drag; it then belongs to the board it was dropped on.
struct PageCanvasView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    /// The page opened; the title switches to the file's other pages.
    private let initialPage: PenpotPageSummary
    let fileID: String
    let revision: Int?
    /// Board id → Penpot thumbnail media id.
    let thumbnails: [String: String]
    let teamID: String?
    /// The file's pages, for the title's page switcher, the player and the live canvas.
    let pages: [PenpotPageSummary]
    let fileName: String

    @State private var pageID: String

    init(page: PenpotPageSummary, fileID: String, revision: Int?, thumbnails: [String: String],
         teamID: String?, pages: [PenpotPageSummary], fileName: String) {
        initialPage = page
        self.fileID = fileID
        self.revision = revision
        self.thumbnails = thumbnails
        self.teamID = teamID
        self.pages = pages
        self.fileName = fileName
        _pageID = State(initialValue: page.id)
    }

    @Environment(LiveFile.self) private var live: LiveFile?

    /// The page on screen, as it is now when it changed live.
    private var page: PenpotPageSummary {
        live?.page(pageID) ?? pages.first { $0.id == pageID } ?? initialPage
    }

    private var canvasPages: [CanvasPage] {
        let all = pages.isEmpty ? [initialPage] : pages
        return all.map { CanvasPage(id: $0.id, name: $0.name) }
    }

    @State private var showsLiveCanvas = false
    @State private var barWidth: CGFloat?
    @State private var showsPlayer = false
    /// How many islands the page has; `nil` until its data is loaded.
    @State private var islandCount: Int?

    @State private var threads: [CommentThread] = []
    @State private var profiles: [String: Profile] = [:]
    @State private var selectedThread: CommentThread?
    @State private var newComment: PendingComment?
    @State private var addMode = false
    @State private var showsThreadList = false
    @State private var focus: CanvasFocus?
    @State private var showsMoveHint = false
    @State private var moveError: String?
    /// In-flight thread reload; cancelled when a pin move lands so its older snapshot
    /// can't put the pin back.
    @State private var loadTask: Task<Void, Never>?

    /// A tap in "add" mode, waiting for its text.
    private struct PendingComment: Identifiable {
        let id = UUID()
        let position: Point
        let frameID: String
    }

    private var pins: [CommentThread] {
        settings.commentFilters.apply(threads.filter { $0.pageId == page.id },
                                      profileID: appState.profile?.id)
    }

    /// The page's name doesn't fit beside "Done" and three icons: "Done" becomes an X and
    /// the icons go into the ⋮ menu (``NavigationBarFit``).
    private var compactBar: Bool {
        guard let barWidth else { return false }
        return !NavigationBarFit.titleFits(page.name, chevron: canvasPages.count > 1,
                                          leading: .text(.appLocalized("Done")),
                                          trailingIcons: 3, width: barWidth)
    }

    /// The page's boards that changed live, at the revision they changed at.
    private var liveBoardRevisions: [String: Int] {
        guard let live else { return [:] }
        var revisions: [String: Int] = [:]
        for board in page.boards { revisions[board.id] = live.revision(of: board.id) }
        return revisions
    }

    /// The page's canvas color, as Penpot's workspace paints it behind the boards.
    private var canvasColor: UIColor {
        UIColor(penpotHex: page.background) ?? UIColor(penpotHex: PenpotPage.defaultBackground)!
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                if let client = appState.client {
                    PageCanvasRepresentable(
                        pageID: page.id,
                        boards: page.boards,
                        thumbnails: thumbnails,
                        renders: BoardRenders(client: client, fileID: fileID, revision: revision,
                                              profileID: appState.profile?.id
                                                ?? UUID().uuidString.lowercased(),
                                              teamID: teamID,
                                              boardRevisions: liveBoardRevisions,
                                              pageRevision: live?.pageRevision(page.id)),
                        liveRevision: live?.pageRevision(page.id),
                        pins: pins,
                        isPlacingComment: addMode,
                        focus: focus,
                        onIslands: { islandCount = $0 },
                        onSelectThread: { selectedThread = $0 },
                        onMoveThread: { thread, position, frameID in
                            Task { await moveThread(thread, to: position, frameID: frameID) }
                        },
                        onPlaceComment: { position, frameID in
                            addMode = false
                            newComment = PendingComment(position: position, frameID: frameID)
                        })
                        // Another page is another canvas.
                        .id(page.id)
                        .background(Color(uiColor: canvasColor))
                        .ignoresSafeArea(edges: .bottom)
                }
                if page.boards.isEmpty {
                    switch islandCount {
                    case nil:
                        PencilLoaderView()
                            .frame(width: 64)
                    case 0:
                        // On the page's color, not the app's: light or dark text to suit.
                        Text("No boards on this page")
                            .font(.workSans(.footnote))
                            .foregroundStyle(.secondary)
                            .environment(\.colorScheme, canvasColor.isDark ? .dark : .light)
                    default:
                        EmptyView()
                    }
                }
            }
            .trackingWidth($barWidth)
            .navigationTitle(page.name)
            .navigationBarTitleDisplayMode(.inline)
            // The canvas color runs under the bar: its title and the status bar follow how
            // light that color is, not the app's appearance.
            .toolbarColorScheme(canvasColor.isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DoneButton(compact: compactBar) { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    PageSwitcher(pages: canvasPages, selection: $pageID, fallbackTitle: page.name)
                }
                // Three buttons leave the page's name room; the rest is in the menu. Where
                // even that is too long, all of it is, except the way out of placing a
                // comment.
                if !compactBar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsPlayer = true } label: { AppIcon.play.image }
                            .accessibilityLabel("Play prototype")
                    }
                }
                if !compactBar || addMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { addMode.toggle() }
                        } label: {
                            (addMode ? AppIcon.closeFilled : AppIcon.addComment).image
                        }
                        .accessibilityLabel(addMode ? "Cancel" : "New Comment")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if compactBar {
                            Button { showsPlayer = true } label: {
                                AppIcon.play.label("Play prototype")
                            }
                            if !addMode {
                                Button { withAnimation { addMode = true } } label: {
                                    AppIcon.addComment.label("New Comment")
                                }
                            }
                        }
                        Button { showsThreadList = true } label: {
                            AppIcon.comments.label("Comments in this file")
                        }
                        Button { showsLiveCanvas = true } label: {
                            AppIcon.externalLink.label("Open live canvas")
                        }
                    } label: {
                        AppIcon.more.image
                    }
                    .accessibilityLabel("Options")
                }
            }
            .safeAreaInset(edge: .top) {
                if addMode {
                    hint("Tap the canvas to place a comment")
                } else if showsMoveHint {
                    hint("Touch and hold a pin to move it")
                }
            }
            .task { await loadComments() }
            // Penpot sends no comment events: the threads again every 20 seconds.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled, selectedThread == nil, newComment == nil,
                          UIApplication.shared.applicationState == .active else { continue }
                    await loadComments()
                }
            }
            .onChange(of: pageID) {
                islandCount = nil
                focus = nil
                withAnimation { addMode = false }
            }
            .alert("Something went wrong", isPresented: Binding(get: { moveError != nil },
                                                                set: { if !$0 { moveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(moveError ?? "")
            }
            .sheet(item: $selectedThread) { thread in
                CommentThreadSheet(fileID: fileID, thread: thread, profiles: profiles, teamID: teamID) {
                    reloadComments()
                }
            }
            .sheet(isPresented: $showsThreadList) {
                CommentThreadListSheet(threads: threads, profiles: profiles, boardID: "", pageID: page.id,
                                       onSelect: { thread in
                    if thread.pageId == page.id, let position = thread.position {
                        focus = CanvasFocus(position: position)
                    }
                    selectedThread = thread
                })
            }
            .sheet(item: $newComment) { pending in
                NewCommentSheet(fileID: fileID, pageID: page.id, frameID: pending.frameID,
                                position: pending.position, teamID: teamID) {
                    newComment = nil
                    reloadComments()
                    withAnimation { showsMoveHint = true }
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { showsMoveHint = false }
                    }
                }
            }
            .fullScreenCover(isPresented: $showsPlayer) {
                PrototypePlayerView(fileID: fileID, teamID: teamID, revision: revision,
                                    pages: canvasPages, initialPageID: page.id, title: fileName,
                                    thumbnails: thumbnails)
            }
            .fullScreenCover(isPresented: $showsLiveCanvas) {
                if let baseURL = appState.client?.baseURL {
                    PenpotCanvasView(baseURL: baseURL, fileID: fileID, teamID: teamID,
                                     pages: canvasPages, initialPageID: page.id, title: fileName)
                }
            }
        }
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.workSans(.footnote))
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
    }

    private func reloadComments() {
        loadTask?.cancel()
        loadTask = Task { await loadComments() }
    }

    /// Puts the pin where it was dropped at once, then saves it with the board under it;
    /// on failure only this pin goes back.
    private func moveThread(_ thread: CommentThread, to position: Point, frameID: String) async {
        guard let client = appState.client,
              let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        loadTask?.cancel()
        let previous = threads[index].position
        threads[index].position = position
        do {
            try await client.updateThreadPosition(id: thread.id, frameID: frameID, position: position)
            reloadComments()
        } catch {
            if let index = threads.firstIndex(where: { $0.id == thread.id }) {
                threads[index].position = previous
            }
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                moveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func loadComments() async {
        guard let client = appState.client else { return }
        // "Only yours"/"Mentions" need the profile id (see BoardDetailView.load).
        if let teamID { await appState.resolveProfileIfNeeded(teamID: teamID) }
        do {
            async let threadsTask = client.commentThreads(fileID: fileID)
            async let profilesTask = client.commentProfiles(fileID: fileID)
            let fetched = try await threadsTask
            let fetchedProfiles = (try? await profilesTask) ?? [:]
            guard !Task.isCancelled else { return }
            threads = fetched
            profiles = fetchedProfiles
        } catch {
            guard !Task.isCancelled else { return }
            if case PenpotError.unauthorized = error { appState.logout() }
        }
    }
}

/// A request to bring a canvas position to the middle of the screen; a new one each time.
struct CanvasFocus {
    let id = UUID()
    let position: Point
}

private struct PageCanvasRepresentable: UIViewRepresentable {
    let pageID: String
    let boards: [Board]
    let thumbnails: [String: String]
    let renders: BoardRenders
    /// ``LiveFile/pageRevision(_:)``: a new one redraws what changed, in place.
    let liveRevision: Int?
    let pins: [CommentThread]
    let isPlacingComment: Bool
    let focus: CanvasFocus?
    let onIslands: (Int) -> Void
    let onSelectThread: (CommentThread) -> Void
    let onMoveThread: (CommentThread, Point, String) -> Void
    let onPlaceComment: (Point, String) -> Void

    final class Coordinator {
        var handledFocus: UUID?
        var liveRevision: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PageCanvasUIView {
        context.coordinator.liveRevision = liveRevision
        return PageCanvasUIView(pageID: pageID, boards: boards, thumbnails: thumbnails, renders: renders,
                                onIslands: onIslands)
    }

    func updateUIView(_ view: PageCanvasUIView, context: Context) {
        if context.coordinator.liveRevision != liveRevision {
            context.coordinator.liveRevision = liveRevision
            view.apply(boards: boards, renders: renders)
        }
        view.onSelectThread = onSelectThread
        view.onMoveThread = onMoveThread
        view.onPlaceComment = onPlaceComment
        view.isPlacingComment = isPlacingComment
        view.setPins(pins)
        if let focus, focus.id != context.coordinator.handledFocus {
            context.coordinator.handledFocus = focus.id
            view.focus(on: focus.position)
        }
    }
}

/// The zooming canvas: boards and islands as subviews of one content view, sized in canvas
/// units times ``baseScale``; board names and comment pins in screen-space overlays so they
/// keep their size.
final class PageCanvasUIView: UIView, UIScrollViewDelegate {
    var onSelectThread: (CommentThread) -> Void = { _ in }
    /// A pin dropped somewhere else: its new canvas position and the board under it.
    var onMoveThread: (CommentThread, Point, String) -> Void = { _, _, _ in }
    /// A tap in "add" mode: its canvas position and the board under it (or the page's root).
    var onPlaceComment: (Point, String) -> Void = { _, _ in }
    var isPlacingComment = false {
        didSet { placeTap.isEnabled = isPlacingComment }
    }

    private let pageID: String
    private var boards: [Board]
    private let thumbnails: [String: String]
    private var renders: BoardRenders
    private let onIslands: (Int) -> Void
    /// Union of the boards and islands, in canvas units.
    private var pageBounds: CGRect
    private var islands: [PenpotSVG.Island] = []
    /// Root shape id → paint order, once the page data is loaded.
    private var layers: [String: Int] = [:]

    private let scrollView = UIScrollView()
    private let content = UIView()
    private let nameLayer = UIView()
    private let pinLayer = PinLayerView()
    private var pinViews: [String: CommentPinTile] = [:]
    /// The pin being dragged, which follows the finger instead of its thread's position.
    private var draggedPinID: String?
    private let placeTap = UITapGestureRecognizer()
    /// A focus asked for before the content was built.
    private var pendingFocus: Point?
    private var tiles: [BoardTileView] = []
    private var names: [(tile: BoardTileView, label: UILabel)] = []
    /// Points per canvas unit at zoom scale 1, which fits the page on first layout.
    private var baseScale: CGFloat = 0
    /// Set once the person zoomed or scrolled; islands arriving later then keep the view.
    private var hasMoved = false
    private var islandsTask: Task<Void, Never>?

    init(pageID: String, boards: [Board], thumbnails: [String: String], renders: BoardRenders,
         onIslands: @escaping (Int) -> Void) {
        self.pageID = pageID
        self.boards = boards
        self.thumbnails = thumbnails
        self.renders = renders
        self.onIslands = onIslands
        pageBounds = boards.reduce(CGRect.null) { $0.union(Self.rect(of: $1)) }
        super.init(frame: .zero)

        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        addSubview(scrollView)
        scrollView.addSubview(content)
        nameLayer.isUserInteractionEnabled = false
        addSubview(nameLayer)
        addSubview(pinLayer)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        placeTap.addTarget(self, action: #selector(handlePlaceTap(_:)))
        placeTap.require(toFail: doubleTap)
        placeTap.isEnabled = false
        scrollView.addGestureRecognizer(placeTap)

        islandsTask = Task { [weak self, pageID, renders] in
            let result = await LocalBoardRenderer.shared.islands(onPage: pageID, using: renders)
            guard !Task.isCancelled else { return }
            self?.add(islands: result?.islands ?? [], layers: result?.layers ?? [:])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { islandsTask?.cancel() }

    private static func rect(of board: Board) -> CGRect {
        CGRect(x: board.selrect.x, y: board.selrect.y,
               width: board.selrect.width, height: board.selrect.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        nameLayer.frame = bounds
        pinLayer.frame = bounds
        guard bounds.width > 0, bounds.height > 0, !pageBounds.isNull,
              pageBounds.width > 0, pageBounds.height > 0 else { return }
        if baseScale == 0 { buildContent() }
        updateZoomLimits()
        centerContent()
        updateNames()
        updatePins()
        loadVisibleBoards()
        if let position = pendingFocus {
            pendingFocus = nil
            focus(on: position)
        }
    }

    // MARK: - Content

    private func buildContent() {
        fitPage()
        for board in boards { addTile(for: board, islandLayer: nil) }
        for island in islands { addTile(for: island) }
        orderTiles()
        placeTiles()
    }

    /// The scale that fits the whole page, with room for the names above the boards.
    private func fitPage() {
        let nameSpace = UIFont.preferredFont(forTextStyle: .caption1).lineHeight + 8
        baseScale = min(bounds.width / pageBounds.width,
                        (bounds.height - nameSpace) / pageBounds.height) * 0.92
    }

    private func addTile(for board: Board, islandLayer: Int?) {
        let tile = BoardTileView(board: board, islandLayer: islandLayer)
        content.addSubview(tile)
        tiles.append(tile)
        addName(for: tile)
    }

    private func addName(for tile: BoardTileView) {
        let board = tile.board
        guard tile.islandLayer == nil, board.showsCanvasTitle else { return }
        let label = UILabel()
        label.font = WorkSans.uiFont(for: .regular, size: 12)
        label.attributedText = Self.title(of: board, font: label.font)
        label.lineBreakMode = .byTruncatingTail
        nameLayer.addSubview(label)
        names.append((tile, label))
    }

    private func addTile(for island: PenpotSVG.Island) {
        let box = island.bounds
        let board = Board(id: island.id, pageID: pageID, name: "",
                          selrect: Selrect(x: box.minX, y: box.minY, width: box.width, height: box.height))
        addTile(for: board, islandLayer: island.layer)
    }

    /// Penpot's paint order once it is known; before that, the boards' own order.
    private func orderTiles() {
        let order = tiles.enumerated().sorted { lhs, rhs in
            let left = lhs.element.islandLayer ?? layers[lhs.element.board.id] ?? -1
            let right = rhs.element.islandLayer ?? layers[rhs.element.board.id] ?? -1
            return left != right ? left < right : lhs.offset < rhs.offset
        }
        for (_, tile) in order { content.addSubview(tile) }
    }

    /// Sizes the content and the tiles for ``pageBounds`` at ``baseScale``; the zoom
    /// scale must be 1.
    private func placeTiles() {
        content.frame = CGRect(x: 0, y: 0, width: pageBounds.width * baseScale,
                               height: pageBounds.height * baseScale)
        scrollView.contentSize = content.frame.size
        // Enough levels of detail for the deepest zoom (see `updateZoomLimits`).
        let detailBias = max(3, Int(ceil(log2(maximumZoom))) + 1)
        for tile in tiles {
            let rect = Self.rect(of: tile.board).offsetBy(dx: -pageBounds.minX, dy: -pageBounds.minY)
            tile.frame = CGRect(x: rect.minX * baseScale, y: rect.minY * baseScale,
                                width: rect.width * baseScale, height: rect.height * baseScale)
            tile.detailBias = detailBias
        }
    }

    /// The islands arrived. Before the person moved, the page is fitted again around them;
    /// after, the view stays where it is and the page grows around it.
    private func add(islands: [PenpotSVG.Island], layers: [String: Int]) {
        self.layers = layers
        onIslands(islands.count)
        guard !islands.isEmpty else {
            if baseScale > 0 { orderTiles() }
            return
        }
        self.islands = islands
        let oldOrigin = pageBounds.origin
        pageBounds = islands.reduce(pageBounds) { $0.union($1.bounds) }
        guard baseScale > 0 else {
            setNeedsLayout()
            return
        }
        for island in islands { addTile(for: island) }
        orderTiles()

        let zoom = scrollView.zoomScale
        let offset = scrollView.contentOffset
        scrollView.zoomScale = 1
        if hasMoved {
            placeTiles()
            scrollView.zoomScale = zoom
            let shift = CGPoint(x: (oldOrigin.x - pageBounds.minX) * baseScale * zoom,
                                y: (oldOrigin.y - pageBounds.minY) * baseScale * zoom)
            scrollView.contentOffset = CGPoint(x: offset.x + shift.x, y: offset.y + shift.y)
        } else {
            fitPage()
            placeTiles()
        }
        updateZoomLimits()
        centerContent()
        updateNames()
        updatePins()
        loadVisibleBoards()
    }

    /// Up to 2 screen points per canvas unit: past real size, where Penpot's own canvas
    /// stops being useful too.
    private var maximumZoom: CGFloat { max(4, 2 / max(baseScale, 0.0001)) }

    private func updateZoomLimits() {
        // Fit the page again after a size change (rotation, iPad split view).
        let fit = min(bounds.width / content.bounds.width, bounds.height / content.bounds.height)
        scrollView.minimumZoomScale = min(1, fit)
        scrollView.maximumZoomScale = maximumZoom
        if scrollView.zoomScale < scrollView.minimumZoomScale {
            scrollView.zoomScale = scrollView.minimumZoomScale
        }
    }

    /// Keeps a page smaller than the screen centered instead of pinned to the top left.
    private func centerContent() {
        let size = scrollView.bounds.size
        let contentSize = scrollView.contentSize
        let horizontal = max(0, (size.width - contentSize.width) / 2)
        let vertical = max(0, (size.height - contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal,
                                               bottom: vertical, right: horizontal)
    }

    // MARK: - Names

    /// Penpot's board title (`frame-title`, body-small): gray on any canvas color, in either
    /// theme, with a 12-point icon before the name of the file's thumbnail board, a main
    /// component or a variant container.
    private static func title(of board: Board, font: UIFont) -> NSAttributedString {
        let color = UIColor(penpotHex: "#8F9DA3")!
        let title = NSMutableAttributedString()
        if let icon = board.titleIcon, let image = UIImage(named: icon.assetName) {
            let attachment = NSTextAttachment()
            attachment.image = image.withTintColor(color, renderingMode: .alwaysOriginal)
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - 12) / 2, width: 12, height: 12)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: " ", attributes: [.font: font]))
        }
        title.append(NSAttributedString(string: board.name, attributes: [.font: font, .foregroundColor: color]))
        return title
    }

    /// Places each board's name above its top-left corner in screen space; hidden when the
    /// board is too small on screen to carry it.
    private func updateNames() {
        for (tile, label) in names {
            let frame = content.convert(tile.frame, to: nameLayer)
            label.isHidden = frame.width < 48 || !frame.insetBy(dx: 0, dy: -24).intersects(nameLayer.bounds)
            guard !label.isHidden else { continue }
            let height = label.font.lineHeight
            label.frame = CGRect(x: frame.minX, y: frame.minY - height - 4,
                                 width: frame.width, height: height)
        }
    }

    // MARK: - Comments

    /// Shows `threads` as pins; a pin keeps its view (and its place) across reloads.
    func setPins(_ threads: [CommentThread]) {
        let placed = threads.filter { $0.position != nil }
        let ids = Set(placed.map(\.id))
        for (id, view) in pinViews where !ids.contains(id) {
            view.removeFromSuperview()
            pinViews[id] = nil
        }
        for thread in placed {
            if let view = pinViews[thread.id] {
                view.thread = thread
            } else {
                let view = CommentPinTile(thread: thread) { [weak self] thread in self?.onSelectThread(thread) }
                view.onPickUp = { [weak self] thread in self?.draggedPinID = thread.id }
                view.onDrop = { [weak self] thread, point in self?.drop(thread, at: point) }
                pinLayer.addSubview(view)
                pinViews[thread.id] = view
            }
        }
        updatePins()
    }

    /// Canvas units to the content view's (unzoomed) coordinates.
    private func contentPoint(_ position: Point) -> CGPoint {
        CGPoint(x: (position.x - pageBounds.minX) * baseScale, y: (position.y - pageBounds.minY) * baseScale)
    }

    /// Centers each pin on its thread's position, in screen space.
    private func updatePins() {
        for view in pinViews.values where view.thread.id != draggedPinID {
            guard baseScale > 0, let position = view.thread.position else {
                view.isHidden = true
                continue
            }
            view.isHidden = false
            view.center = content.convert(contentPoint(position), to: pinLayer)
        }
    }

    /// A dragged pin let go at `point` (pin layer coordinates), or `nil` when the drag was
    /// cancelled: it then goes back to where its thread is.
    private func drop(_ thread: CommentThread, at point: CGPoint?) {
        draggedPinID = nil
        guard let point, baseScale > 0 else {
            updatePins()
            return
        }
        let location = pinLayer.convert(point, to: content)
        let canvas = CGPoint(x: location.x / baseScale + pageBounds.minX, y: location.y / baseScale + pageBounds.minY)
        onMoveThread(thread, Point(x: canvas.x, y: canvas.y), Self.frameID(at: canvas, boards: boards, layers: layers))
    }

    /// Zooms to real size (or keeps a closer zoom) with `position` in the middle.
    func focus(on position: Point) {
        guard baseScale > 0 else {
            pendingFocus = position
            return
        }
        hasMoved = true
        let point = contentPoint(position)
        let scale = min(scrollView.maximumZoomScale, max(scrollView.zoomScale, 1 / baseScale))
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                   width: size.width, height: size.height), animated: true)
    }

    /// The canvas position of the tap, on the topmost board under it; outside every board
    /// the thread belongs to the page's root frame, as in Penpot.
    @objc private func handlePlaceTap(_ gesture: UITapGestureRecognizer) {
        guard baseScale > 0 else { return }
        let location = gesture.location(in: content)
        let canvas = CGPoint(x: location.x / baseScale + pageBounds.minX, y: location.y / baseScale + pageBounds.minY)
        onPlaceComment(Point(x: canvas.x, y: canvas.y), Self.frameID(at: canvas, boards: boards, layers: layers))
    }

    /// The topmost board containing `point` (canvas units), else the page's root frame.
    static func frameID(at point: CGPoint, boards: [Board], layers: [String: Int]) -> String {
        boards.filter { rect(of: $0).contains(point) }
            .max { (layers[$0.id] ?? -1) < (layers[$1.id] ?? -1) }?.id ?? Board.rootFrameID
    }

    /// The page changed live (``LiveFile``): boards drawn at another revision now, or
    /// moved, get new tiles, the others keep theirs; the islands come again from the new
    /// page data. The view stays where it is, as when islands arrive.
    func apply(boards newBoards: [Board], renders newRenders: BoardRenders) {
        let oldRenders = renders
        var kept: [String: BoardTileView] = [:]
        for tile in tiles {
            if tile.islandLayer == nil, let board = newBoards.first(where: { $0.id == tile.board.id }),
               board == tile.board,
               oldRenders.key(for: board, kind: .vector) == newRenders.key(for: board, kind: .vector) {
                kept[board.id] = tile
            } else {
                tile.cancelPendingLoads()
                tile.removeFromSuperview()
            }
        }
        names.forEach { $0.label.removeFromSuperview() }
        names = []
        tiles = []
        islands = []
        boards = newBoards
        renders = newRenders
        let oldOrigin = pageBounds.origin
        pageBounds = newBoards.reduce(CGRect.null) { $0.union(Self.rect(of: $1)) }
        guard baseScale > 0, !pageBounds.isNull else {
            setNeedsLayout()
            return
        }
        for board in newBoards {
            if let tile = kept[board.id] {
                content.addSubview(tile)
                tiles.append(tile)
                addName(for: tile)
            } else {
                addTile(for: board, islandLayer: nil)
            }
        }
        orderTiles()
        let zoom = scrollView.zoomScale
        let offset = scrollView.contentOffset
        scrollView.zoomScale = 1
        placeTiles()
        scrollView.zoomScale = zoom
        scrollView.contentOffset = CGPoint(x: offset.x + (oldOrigin.x - pageBounds.minX) * baseScale * zoom,
                                           y: offset.y + (oldOrigin.y - pageBounds.minY) * baseScale * zoom)
        updateZoomLimits()
        centerContent()
        updateNames()
        updatePins()
        loadVisibleBoards()

        islandsTask?.cancel()
        islandsTask = Task { [weak self, pageID, newRenders] in
            let result = await LocalBoardRenderer.shared.islands(onPage: pageID, using: newRenders)
            guard !Task.isCancelled else { return }
            self?.add(islands: result?.islands ?? [], layers: result?.layers ?? [:])
        }
    }

    // MARK: - Loading

    /// Vector PDFs for the tiles on (or near) the screen, with Penpot's thumbnail as a
    /// stand-in where a board has one. Tiles that left the screen give up their queued loads.
    private func loadVisibleBoards() {
        let visible = content.convert(scrollView.bounds, from: scrollView)
            .insetBy(dx: -scrollView.bounds.width / 4 / scrollView.zoomScale,
                     dy: -scrollView.bounds.height / 4 / scrollView.zoomScale)
        for tile in tiles {
            guard tile.frame.intersects(visible) else {
                tile.cancelPendingLoads()
                continue
            }
            // A board that changed live is drawn here: Penpot's thumbnail shows the old one.
            if let mediaID = thumbnails[tile.board.id], renders.boardRevisions[tile.board.id] == nil {
                tile.loadPicture(using: renders, mediaID: mediaID)
            }
            tile.loadVector(using: renders)
        }
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { hasMoved = true }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { hasMoved = true }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        updateNames()
        updatePins()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNames()
        updatePins()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        loadVisibleBoards()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { loadVisibleBoards() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { loadVisibleBoards() }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { loadVisibleBoards() }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        hasMoved = true
        if scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: content)
            let scale = min(scrollView.zoomScale * 3, scrollView.maximumZoomScale)
            let size = CGSize(width: scrollView.bounds.width / scale,
                              height: scrollView.bounds.height / scale)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
        }
    }
}

/// One board or island on the canvas: a board's thumbnail first, its vector PDF once that
/// is needed. An island has no thumbnail and no exporter fallback (the exporter only
/// renders boards), and shows nothing until it is drawn.
private final class BoardTileView: UIView {
    let board: Board
    /// An island's place in the paint order; `nil` for a board.
    let islandLayer: Int?
    var detailBias = 3 {
        didSet { vectorView?.pageLayer.levelsOfDetailBias = detailBias }
    }
    private let imageView = UIImageView()
    private var vectorView: BoardVectorView.PageView?
    private var pictureTask: Task<Void, Never>?
    private var vectorTask: Task<Void, Never>?

    init(board: Board, islandLayer: Int?) {
        self.board = board
        self.islandLayer = islandLayer
        super.init(frame: .zero)
        backgroundColor = islandLayer == nil ? .tertiarySystemFill : .clear
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        vectorView?.frame = bounds
    }

    func loadPicture(using renders: BoardRenders, mediaID: String?) {
        guard imageView.image == nil, vectorView == nil, pictureTask == nil else { return }
        let board = board
        pictureTask = Task { [weak self] in
            let image = await renders.picture(of: board, mediaID: mediaID)
            guard let self, !Task.isCancelled else { return }
            self.imageView.image = image
            if image != nil { self.backgroundColor = .clear }
        }
    }

    func loadVector(using renders: BoardRenders) {
        guard vectorView == nil, vectorTask == nil else { return }
        let board = board
        let exporterFallback = islandLayer == nil
        vectorTask = Task { [weak self] in
            guard let document = await renders.vector(of: board, exporterFallback: exporterFallback),
                  let self, !Task.isCancelled else { return }
            let view = BoardVectorView.PageView(frame: self.bounds)
            view.pageLayer.levelsOfDetailBias = self.detailBias
            view.pageLayer.page = document.page(at: 1)
            view.alpha = 0
            self.addSubview(view)
            self.vectorView = view
            UIView.animate(withDuration: 0.2) {
                view.alpha = 1
            } completion: { _ in
                self.imageView.isHidden = true
                self.backgroundColor = .clear
            }
        }
    }

    /// Off screen: drop loads still waiting in the exporter queue (a started render still
    /// finishes and is cached, see ``BoardPreviewRenderer``).
    func cancelPendingLoads() {
        if imageView.image == nil { pictureTask?.cancel(); pictureTask = nil }
        if vectorView == nil { vectorTask?.cancel(); vectorTask = nil }
    }
}

/// Lets touches through to the canvas except on its pins (the prototype player's too).
final class PinLayerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// A comment thread's pin on the canvas: the board view's ``CommentPinView``. A tap opens
/// the thread; touch and hold picks the pin up to drag it, as on a board. The hold gate
/// keeps a pan that happens to start on a pin from moving it.
final class CommentPinTile: UIView {
    var thread: CommentThread {
        didSet { host.rootView = CommentPinView(thread: thread) }
    }
    var onPickUp: (CommentThread) -> Void = { _ in }
    /// Where the pin was let go, in its superview; `nil` when the drag was cancelled.
    var onDrop: (CommentThread, CGPoint?) -> Void = { _, _ in }
    private let host: UIHostingController<CommentPinView>
    private let onTap: (CommentThread) -> Void

    init(thread: CommentThread, onTap: @escaping (CommentThread) -> Void) {
        self.thread = thread
        self.onTap = onTap
        host = UIHostingController(rootView: CommentPinView(thread: thread))
        super.init(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.view.frame = bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(host.view)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.3
        addGestureRecognizer(hold)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.require(toFail: hold)
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func tapped() { onTap(thread) }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard let superview else { return }
        switch gesture.state {
        case .began:
            onPickUp(thread)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            UIView.animate(withDuration: 0.15) { self.transform = CGAffineTransform(scaleX: 1.3, y: 1.3) }
            center = gesture.location(in: superview)
        case .changed:
            center = gesture.location(in: superview)
        case .ended:
            settle()
            onDrop(thread, center)
        default:
            settle()
            onDrop(thread, nil)
        }
    }

    private func settle() {
        UIView.animate(withDuration: 0.15) { self.transform = .identity }
    }
}
