import SwiftUI
import UIKit

/// Full-screen board with zoom/pan and comment pins overlaid at their canvas positions.
/// Toggle "add" mode to drop a new comment by tapping the board.
///
/// The board shows its thumbnail at once and is replaced by its vector PDF from the
/// exporter as soon as that arrives, so text stays sharp when zoomed in.
///
/// Its Inspect mode is Penpot's (``InspectPanel``): a tap picks the shape under the finger.
/// On a wide screen (the iPhone Duo's inner one, landscape) the page's other boards are a
/// column beside the board, and the inspect panel sits on the right instead of below.
struct BoardDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    let fileID: String
    let board: Board
    let mediaID: String?
    let baseURL: URL
    /// The file's `revn`, for the exporter-rendered preview when there's no `mediaID`.
    var revision: Int? = nil
    var teamID: String? = nil
    var pages: [CanvasPage] = []
    /// The root boards of this board's page, to tell threads on boards nested in this one
    /// from threads on its neighbours (see ``PinMath/thread(_:isOn:pageBoardIDs:)``).
    var pageBoardIDs: Set<String> = []
    /// The page's boards, for the column of boards on a wide screen, with their thumbnails.
    var pageBoards: [Board] = []
    var thumbnails: [String: String] = [:]

    @Environment(LiveFile.self) private var live: LiveFile?
    /// The board on screen: the one opened, until another is picked in the column.
    @State private var shownBoardID: String?
    @State private var pageWidth: CGFloat?
    @State private var pageHeight: CGFloat = 0

    @State private var inspecting = false
    @State private var inspectBoard: InspectBoard?
    @State private var inspectSelection = ""

    @State private var threads: [CommentThread] = []
    @State private var profiles: [String: Profile] = [:]
    @State private var selectedThread: CommentThread? = nil
    @State private var newCommentPosition: Point? = nil
    @State private var addMode = false
    @State private var showCanvas = false
    @State private var showViewMode = false
    @State private var showThreadList = false
    /// Last known viewport size, captured from the GeometryReader so a thread-list jump
    /// can compute the pin-centering transform outside the reader's scope.
    @State private var viewportSize: CGSize = .zero

    /// Transient state of the pin being moved. Lives in `@GestureState` so the
    /// system resets it even when the gesture is cancelled (backgrounding, an
    /// incoming cover) — a pin can never get stuck in the picked-up style.
    private struct PinDrag {
        let threadID: String
        var location: CGPoint?
    }
    @GestureState private var pinDrag: PinDrag? = nil

    // In-flight thread reload; cancelled when a pin move lands so a stale
    // snapshot can't overwrite the fresh position.
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var moveError: String? = nil
    @State private var showMoveHint = false

    /// The board as a vector PDF; `nil` until the exporter delivered it.
    @State private var vectorDocument: CGPDFDocument?
    @State private var isLoadingVector = false

    // Zoom / pan state.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// The board on screen, with its latest name and geometry when it changed live.
    private var current: Board {
        let id = shownBoardID ?? board.id
        let shown = pageBoards.first { $0.id == id } ?? board
        return live?.board(id) ?? shown
    }

    /// The render revision of the board on screen: the file's, or the one it changed at live.
    private var currentRevision: Int? {
        live?.revision(of: current.id) ?? revision
    }

    private var currentMediaID: String? {
        // A board that changed live is drawn here: Penpot's thumbnail shows the old one.
        if live?.revision(of: current.id) != nil { return nil }
        return current.id == board.id ? (mediaID ?? thumbnails[board.id]) : thumbnails[current.id]
    }

    private var openThreads: [CommentThread] {
        settings.commentFilters.apply(threads.filter(isOnBoard), profileID: appState.profile?.id)
    }

    private func isOnBoard(_ thread: CommentThread) -> Bool {
        PinMath.thread(thread, isOn: current, pageBoardIDs: pageBoardIDs)
    }

    /// Wide enough for a second column: the iPhone Duo's inner screen, landscape.
    private var isWide: Bool { (pageWidth ?? 0) >= 600 }
    private var showsBoardColumn: Bool {
        isWide && pageBoards.count > 1 && (!inspecting || (pageWidth ?? 0) >= 900)
    }

    /// The board's name doesn't fit beside the back button and three icons: the icons go
    /// into the ⋮ menu (``NavigationBarFit``).
    private var compactBar: Bool {
        guard let width = pageWidth, width > 0 else { return false }
        return !NavigationBarFit.titleFits(current.name, leading: .back, trailingIcons: 3, width: width)
    }

    /// The pages the player and the live canvas switch between: the file's, or at least
    /// this board's.
    private var playerPages: [CanvasPage] {
        pages.isEmpty ? [CanvasPage(id: current.pageID, name: current.name)] : pages
    }

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 0) {
                    if showsBoardColumn {
                        boardColumn
                            .frame(width: 200)
                        Divider()
                    }
                    boardArea
                    if inspecting {
                        Divider()
                        inspectPanel
                            .frame(width: min(340, (pageWidth ?? 0) * 0.45))
                    }
                }
            } else {
                VStack(spacing: 0) {
                    boardArea
                    if inspecting {
                        Divider()
                        // The board keeps the larger part, the panel scrolls.
                        inspectPanel
                            .frame(height: max(240, pageHeight * 0.45))
                    }
                }
            }
        }
        .trackingWidth($pageWidth)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // As in Penpot, every board plays, starting here; a page without
            // interactions pages through its boards. Three buttons leave the board's name
            // room; the thread list (with its filter), Inspect and the live canvas are in
            // the menu. Where even that is too long, all of it is, except the way out of
            // placing a comment.
            if !compactBar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showViewMode = true } label: {
                        AppIcon.play.image
                    }
                    .accessibilityLabel("Play prototype")
                }
            }
            if !compactBar || addMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { toggleAddMode() }
                    } label: {
                        (addMode ? AppIcon.closeFilled : AppIcon.addComment).image
                    }
                    .accessibilityLabel(addMode ? "Cancel" : "New Comment")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if compactBar {
                        Button { showViewMode = true } label: {
                            AppIcon.play.label("Play prototype")
                        }
                        if !addMode {
                            Button { withAnimation { toggleAddMode() } } label: {
                                AppIcon.addComment.label("New Comment")
                            }
                        }
                    }
                    Button { withAnimation { toggleInspecting() } } label: {
                        if inspecting {
                            PenpotMenuCheckLabel(label: Text("Inspect"), isOn: true)
                        } else {
                            AppIcon.code.label("Inspect")
                        }
                    }
                    Button { showThreadList = true } label: {
                        AppIcon.comments.label("Comments in this file")
                    }
                    Button { showCanvas = true } label: {
                        AppIcon.expand.label("Open live canvas")
                    }
                } label: {
                    AppIcon.more.image
                }
                .accessibilityLabel("Options")
            }
        }
        .fullScreenCover(isPresented: $showCanvas) {
            PenpotCanvasView(baseURL: baseURL, fileID: fileID, teamID: teamID,
                             pages: playerPages,
                             initialPageID: current.pageID, title: current.name)
        }
        .fullScreenCover(isPresented: $showViewMode) {
            PrototypePlayerView(fileID: fileID, teamID: teamID, revision: revision,
                                pages: playerPages,
                                initialPageID: current.pageID,
                                initialBoardID: current.id,
                                title: current.name, thumbnails: thumbnails)
        }
        .safeAreaInset(edge: .top) {
            if addMode {
                Text("Tap the board to place a comment")
                    .font(.workSans(.footnote))
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            } else if showMoveHint {
                Text("Touch and hold a pin to move it")
                    .font(.workSans(.footnote))
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
        }
        .task { await load() }
        .task(id: "\(current.id)|\(currentRevision ?? 0)") { await loadVector() }
        .task(id: "\(current.id)|\(currentRevision ?? 0)|\(inspecting)") { await loadInspectBoard() }
        // Penpot sends no comment events, so threads are fetched again while the board is open.
        .task { await pollComments() }
        .refreshable { await load() }
        .sheet(item: $selectedThread) { thread in
            CommentThreadSheet(fileID: fileID, thread: thread, profiles: profiles,
                               teamID: teamID) {
                reload()
            }
        }
        .sheet(isPresented: $showThreadList) {
            CommentThreadListSheet(threads: threads, profiles: profiles, boardID: current.id,
                                   belongsToBoard: isOnBoard) { thread in
                focusThread(thread)
            }
        }
        .sheet(isPresented: Binding(get: { newCommentPosition != nil },
                                    set: { if !$0 { newCommentPosition = nil } })) {
            if let position = newCommentPosition {
                NewCommentSheet(fileID: fileID,
                                pageID: current.pageID,
                                frameID: current.id,
                                position: position,
                                teamID: teamID) {
                    newCommentPosition = nil
                    reload()
                    withAnimation { showMoveHint = true }
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { showMoveHint = false }
                    }
                }
            }
        }
        .alert("Something went wrong", isPresented: moveErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moveError ?? "")
        }
    }

    /// The board, zoomable, with its pins, or the inspect selection over it.
    private var boardArea: some View {
        GeometryReader { geo in
            let fitted = PinMath.fittedSize(selrect: current.selrect, in: geo.size)
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                boardLayer(fitted: fitted)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoomAndPan, including: addMode || inspecting ? .subviews : .all)
                if inspecting, let inspectBoard {
                    InspectOverlay(board: inspectBoard, selectedID: inspectSelection,
                                   transform: canvasTransform(fitted: fitted, in: geo.size))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if isLoadingVector {
                    PencilLoaderView()
                        .frame(width: 36)
                        .padding(16)
                }
            }
            .onAppear { viewportSize = geo.size }
            .onChange(of: geo.size) { _, newSize in viewportSize = newSize }
        }
        // The board pans and zooms by gesture, so the page has no scroll view; the inspect
        // panel's comes after this one.
        .navigationChromeFollowsAppearance()
    }

    @ViewBuilder
    private var inspectPanel: some View {
        if let inspectBoard {
            InspectPanel(board: inspectBoard, selectedID: $inspectSelection) {
                withAnimation { inspecting = false }
            }
        } else {
            ZStack {
                Color.penpotPage
                PencilLoaderView().frame(width: 44)
            }
        }
    }

    /// The page's boards, a tap away (wide screens only).
    private var boardColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(pageBoards) { item in
                        let isCurrent = item.id == current.id
                        Button { show(item) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                BoardImage(fileID: fileID,
                                           revision: live?.revision(of: item.id) ?? revision,
                                           board: live?.board(item.id) ?? item,
                                           mediaID: live?.revision(of: item.id) == nil ? thumbnails[item.id] : nil,
                                           baseURL: baseURL, teamID: teamID,
                                           staleMediaID: thumbnails[item.id])
                                    .frame(height: 96)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(isCurrent ? Color.penpotAccent : Color(.separator),
                                                      lineWidth: isCurrent ? 2 : 1))
                                Text(verbatim: (live?.board(item.id) ?? item).name)
                                    .font(.workSans(.caption, weight: isCurrent ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                        .id(item.id)
                    }
                }
                .padding(12)
            }
            .background(Color.penpotPage)
            .onAppear { proxy.scrollTo(current.id, anchor: .center) }
        }
    }

    private func show(_ item: Board) {
        guard item.id != current.id else { return }
        vectorDocument = nil
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
        addMode = false
        shownBoardID = item.id
        inspectSelection = item.id
    }

    private func toggleAddMode() {
        addMode.toggle()
        if addMode { inspecting = false }
    }

    private func toggleInspecting() {
        inspecting.toggle()
        if inspecting {
            addMode = false
            inspectSelection = current.id
        }
    }

    /// Canvas coordinates to the board area's: fitted into it, then zoomed and panned
    /// around its centre like the board layer.
    private func canvasTransform(fitted: CGSize, in size: CGSize) -> CGAffineTransform {
        let rect = current.selrect
        guard rect.width > 0 else { return .identity }
        let k = fitted.width / rect.width * scale
        let tx = size.width / 2 + offset.width - rect.x * k - fitted.width / 2 * scale
        let ty = size.height / 2 + offset.height - rect.y * k - fitted.height / 2 * scale
        return CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: tx, ty: ty)
    }

    private var moveErrorAlert: Binding<Bool> {
        Binding(get: { moveError != nil }, set: { if !$0 { moveError = nil } })
    }

    @ViewBuilder
    private func boardLayer(fitted: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            BoardImage(fileID: fileID, revision: currentRevision, board: current,
                       mediaID: currentMediaID, baseURL: baseURL, rendersMissingPreview: false,
                       teamID: teamID)
                .frame(width: fitted.width, height: fitted.height)
                .opacity(vectorDocument == nil ? 1 : 0)
            if let vectorDocument {
                BoardVectorView(document: vectorDocument)
                    .frame(width: fitted.width, height: fitted.height)
                    .transition(.opacity)
            }

            // Penpot's inspect shows no comments.
            ForEach(inspecting ? [] : openThreads) { thread in
                if let position = thread.position {
                    let norm = PinMath.normalized(position: position, in: current.selrect)
                    let restingPoint = CGPoint(x: norm.x * fitted.width, y: norm.y * fitted.height)
                    let isDragged = pinDrag?.threadID == thread.id
                    CommentPinView(thread: thread)
                        .scaleEffect(isDragged ? 1.3 : 1)
                        .shadow(radius: isDragged ? 6 : 0)
                        .position(isDragged ? (pinDrag?.location ?? restingPoint) : restingPoint)
                        .onTapGesture { selectedThread = thread }
                        .gesture(movePinGesture(thread: thread, fitted: fitted))
                        .animation(.easeOut(duration: 0.15), value: isDragged)
                }
            }
        }
        .frame(width: fitted.width, height: fitted.height)
        .contentShape(Rectangle())
        .coordinateSpace(name: Self.boardSpace)
        .gesture(placeCommentGesture(fitted: fitted), including: addMode ? .all : .subviews)
        .gesture(inspectGesture(fitted: fitted), including: inspecting ? .all : .subviews)
    }

    /// Inspect: a tap picks the innermost shape under it (``InspectBoard/shape(at:)``).
    private func inspectGesture(fitted: CGSize) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local).onEnded { value in
            guard let inspectBoard, fitted.width > 0, fitted.height > 0 else { return }
            let rect = current.selrect
            let point = CGPoint(x: rect.x + value.location.x / fitted.width * rect.width,
                                y: rect.y + value.location.y / fitted.height * rect.height)
            inspectSelection = inspectBoard.shape(at: point) ?? current.id
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private static let boardSpace = "board"

    /// Touch and hold a pin to pick it up, drag it to a new spot, release to save.
    /// The hold gate is deliberate: a plain drag would claim any pan or pinch that
    /// happens to start on a pin (child gestures beat the ancestor's zoomAndPan)
    /// and silently persist an accidental move.
    private func movePinGesture(thread: CommentThread, fitted: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                           coordinateSpace: .named(Self.boardSpace)))
            .updating($pinDrag) { value, state, _ in
                switch value {
                case .first(true):
                    if state == nil {
                        state = PinDrag(threadID: thread.id, location: nil)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                case .second(true, let drag):
                    // Clamp the live position to the board so the preview always
                    // matches what release will persist.
                    let location = drag.map { Self.clamp($0.location, to: fitted) }
                    state = PinDrag(threadID: thread.id,
                                    location: location ?? state?.location)
                default:
                    break
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value,
                      fitted.width > 0, fitted.height > 0 else { return }
                let clamped = Self.clamp(drag.location, to: fitted)
                let norm = CGPoint(x: clamped.x / fitted.width,
                                   y: clamped.y / fitted.height)
                let position = PinMath.canvasPosition(normalized: norm, in: current.selrect)
                Task { await moveThread(thread, to: position) }
            }
    }

    private static func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), size.width),
                y: min(max(point.y, 0), size.height))
    }

    /// Optimistically repositions the pin, then persists it. On failure only this
    /// pin's position is reverted (a whole-array snapshot would clobber changes
    /// that landed while the request was in flight) and the error is surfaced.
    private func moveThread(_ thread: CommentThread, to position: Point) async {
        guard let client = appState.client else { return }
        // A fetch started before the move still carries the old position — cancel
        // it so its stale snapshot can't land after the optimistic write.
        loadTask?.cancel()
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        let previousPosition = threads[index].position
        threads[index].position = position
        do {
            try await client.updateThreadPosition(id: thread.id, frameID: current.id, position: position)
        } catch {
            if let index = threads.firstIndex(where: { $0.id == thread.id }) {
                threads[index].position = previousPosition
            }
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                moveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func placeCommentGesture(fitted: CGSize) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local).onEnded { value in
            let norm = CGPoint(x: value.location.x / fitted.width,
                               y: value.location.y / fitted.height)
            newCommentPosition = PinMath.canvasPosition(normalized: norm, in: current.selrect)
            addMode = false
        }
    }

    private var zoomAndPan: some Gesture {
        let magnify = MagnifyGesture()
            .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 6) }
            .onEnded { _ in lastScale = scale }
        let drag = DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
        return magnify.simultaneously(with: drag)
    }

    /// Zooms/pans the board so `thread`'s pin lands at screen center, then opens the
    /// thread — closing the sheet leaves the board centered on the pin. Threads on other
    /// boards (from the file-wide list) just open.
    private func focusThread(_ thread: CommentThread) {
        defer { selectedThread = thread }
        guard isOnBoard(thread), let position = thread.position,
              viewportSize.width > 0, viewportSize.height > 0 else { return }
        let fitted = PinMath.fittedSize(selrect: current.selrect, in: viewportSize)
        let norm = PinMath.normalized(position: position, in: current.selrect)
        let targetScale = max(scale, 2)
        // The layer scales around its center, so the pin's offset from that center —
        // scaled — is what the translation must cancel out.
        let pinOffset = CGSize(width: (norm.x - 0.5) * fitted.width * targetScale,
                               height: (norm.y - 0.5) * fitted.height * targetScale)
        withAnimation(.easeInOut(duration: 0.3)) {
            scale = targetScale
            lastScale = targetScale
            offset = CGSize(width: -pinOffset.width, height: -pinOffset.height)
            lastOffset = offset
        }
    }

    private func load() async {
        guard let client = appState.client else { return }
        // "Only yours"/"Mentions" need the profile id, which a cold session restore may
        // not have yet (get-profile is Cloudflare-blocked; recovered via team members).
        if let teamID {
            await appState.resolveProfileIfNeeded(teamID: teamID)
        }
        do {
            async let threadsTask = client.commentThreads(fileID: fileID)
            async let profilesTask = client.commentProfiles(fileID: fileID)
            let fetchedThreads = try await threadsTask
            let fetchedProfiles = (try? await profilesTask) ?? [:]
            guard !Task.isCancelled else { return }
            threads = fetchedThreads
            profiles = fetchedProfiles
        } catch {
            guard !Task.isCancelled else { return }
            if case PenpotError.unauthorized = error { appState.logout() }
        }
    }

    /// Fetches the board's vector PDF through the shared exporter queue (cached per file
    /// revision). Without it the thumbnail simply stays.
    private func loadVector() async {
        guard let client = appState.client else { return }
        let renders = BoardRenders(client: client, fileID: fileID, revision: currentRevision,
                                   profileID: appState.profile?.id ?? UUID().uuidString.lowercased(),
                                   teamID: teamID)
        isLoadingVector = true
        defer { isLoadingVector = false }
        guard let document = await renders.vector(of: current) else { return }
        withAnimation(.easeOut(duration: 0.2)) { vectorDocument = document }
    }

    /// The page data of the board on screen, for the Inspect mode: the same the board is
    /// drawn from.
    private func loadInspectBoard() async {
        guard inspecting, let client = appState.client else { return }
        let renders = BoardRenders(client: client, fileID: fileID, revision: currentRevision,
                                   profileID: appState.profile?.id ?? UUID().uuidString.lowercased(),
                                   teamID: teamID)
        guard let page = await LocalBoardRenderer.shared.page(of: current, using: renders),
              !Task.isCancelled, let model = InspectBoard(page: page, boardID: current.id) else { return }
        inspectBoard = model
        // A shape gone in the new data leaves the board selected.
        if model.shape(inspectSelection) == nil || inspectSelection.isEmpty { inspectSelection = current.id }
    }

    /// Fetches the threads again every 20 seconds while the board is on screen.
    private func pollComments() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, selectedThread == nil, newCommentPosition == nil,
                  UIApplication.shared.applicationState == .active else { continue }
            await load()
        }
    }

    /// Reloads threads, superseding any fetch still in flight.
    private func reload() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }
}
