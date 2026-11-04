import SwiftUI
import UIKit

/// Full-screen board with zoom/pan and comment pins overlaid at their canvas positions.
/// Toggle "add" mode to drop a new comment by tapping the board.
///
/// The board shows its thumbnail at once and is replaced by its vector PDF from the
/// exporter as soon as that arrives, so text stays sharp when zoomed in.
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
    /// Summaries of the file's prototype-capable pages — drives the Play entry (button
    /// shown only when this board's page has something to play, starting at this board).
    var prototypePages: [PenpotPageSummary] = []
    /// The root boards of this board's page, to tell threads on boards nested in this one
    /// from threads on its neighbours (see ``PinMath/thread(_:isOn:pageBoardIDs:)``).
    var pageBoardIDs: Set<String> = []

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

    private var openThreads: [CommentThread] {
        settings.commentFilters.apply(threads.filter(isOnBoard), profileID: appState.profile?.id)
    }

    private func isOnBoard(_ thread: CommentThread) -> Bool {
        PinMath.thread(thread, isOn: board, pageBoardIDs: pageBoardIDs)
    }

    /// This board's page summary, when it has something the view mode can play.
    private var boardPage: PenpotPageSummary? {
        prototypePages.first { $0.id == board.pageID }
    }

    var body: some View {
        GeometryReader { geo in
            let fitted = PinMath.fittedSize(selrect: board.selrect, in: geo.size)
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                boardLayer(fitted: fitted)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoomAndPan, including: addMode ? .subviews : .all)
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
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if boardPage != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showViewMode = true } label: {
                        AppIcon.play.image
                    }
                    .accessibilityLabel("Play prototype")
                }
            }
            // The comment filter menu lives inside this sheet (not the toolbar) — with the
            // conditional Play button, five nav-bar icons would crowd out the title.
            ToolbarItem(placement: .topBarTrailing) {
                Button { showThreadList = true } label: {
                    AppIcon.comments.image
                }
                .accessibilityLabel("Comments in this file")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCanvas = true } label: {
                    AppIcon.expand.image
                }
                .accessibilityLabel("Open live canvas")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { addMode.toggle() }
                } label: {
                    (addMode ? AppIcon.closeFilled : AppIcon.addComment).image
                }
            }
        }
        .fullScreenCover(isPresented: $showCanvas) {
            PenpotCanvasView(baseURL: baseURL, fileID: fileID, teamID: teamID,
                             pages: pages.isEmpty ? [CanvasPage(id: board.pageID, name: board.name)] : pages,
                             initialPageID: board.pageID, title: board.name)
        }
        .fullScreenCover(isPresented: $showViewMode) {
            PenpotViewModeView(baseURL: baseURL, fileID: fileID,
                               pages: prototypePages.map { CanvasPage(id: $0.id, name: $0.name) },
                               initialPageID: board.pageID,
                               initialIndex: boardPage?.viewerFrameIDs.firstIndex(of: board.id) ?? 0,
                               title: board.name)
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
        .task(id: board.id) { await loadVector() }
        .refreshable { await load() }
        .sheet(item: $selectedThread) { thread in
            CommentThreadSheet(fileID: fileID, thread: thread, profiles: profiles,
                               teamID: teamID) {
                reload()
            }
        }
        .sheet(isPresented: $showThreadList) {
            CommentThreadListSheet(threads: threads, profiles: profiles, boardID: board.id,
                                   belongsToBoard: isOnBoard) { thread in
                focusThread(thread)
            }
        }
        .sheet(isPresented: Binding(get: { newCommentPosition != nil },
                                    set: { if !$0 { newCommentPosition = nil } })) {
            if let position = newCommentPosition {
                NewCommentSheet(fileID: fileID,
                                pageID: board.pageID,
                                frameID: board.id,
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

    private var moveErrorAlert: Binding<Bool> {
        Binding(get: { moveError != nil }, set: { if !$0 { moveError = nil } })
    }

    @ViewBuilder
    private func boardLayer(fitted: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            BoardImage(fileID: fileID, revision: revision, board: board,
                       mediaID: mediaID, baseURL: baseURL, rendersMissingPreview: false,
                       teamID: teamID)
                .frame(width: fitted.width, height: fitted.height)
                .opacity(vectorDocument == nil ? 1 : 0)
            if let vectorDocument {
                BoardVectorView(document: vectorDocument)
                    .frame(width: fitted.width, height: fitted.height)
                    .transition(.opacity)
            }

            ForEach(openThreads) { thread in
                if let position = thread.position {
                    let norm = PinMath.normalized(position: position, in: board.selrect)
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
                let position = PinMath.canvasPosition(normalized: norm, in: board.selrect)
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
            try await client.updateThreadPosition(id: thread.id, frameID: board.id, position: position)
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
            newCommentPosition = PinMath.canvasPosition(normalized: norm, in: board.selrect)
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
        let fitted = PinMath.fittedSize(selrect: board.selrect, in: viewportSize)
        let norm = PinMath.normalized(position: position, in: board.selrect)
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
        guard let client = appState.client, vectorDocument == nil else { return }
        let renders = BoardRenders(client: client, fileID: fileID, revision: revision,
                                   profileID: appState.profile?.id ?? UUID().uuidString.lowercased(),
                                   teamID: teamID)
        isLoadingVector = true
        defer { isLoadingVector = false }
        guard let document = await renders.vector(of: board) else { return }
        withAnimation(.easeOut(duration: 0.2)) { vectorDocument = document }
    }

    /// Reloads threads, superseding any fetch still in flight.
    private func reload() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }
}
