import SwiftUI
import UIKit

/// Full-screen board image with zoom/pan and comment pins overlaid at their canvas
/// positions. Toggle "add" mode to drop a new comment by tapping the board.
struct BoardDetailView: View {
    @Environment(AppState.self) private var appState
    let fileID: String
    let board: Board
    let mediaID: String?
    let baseURL: URL
    var teamID: String? = nil
    var pages: [CanvasPage] = []

    @State private var threads: [CommentThread] = []
    @State private var profiles: [String: Profile] = [:]
    @State private var selectedThread: CommentThread? = nil
    @State private var newCommentPosition: Point? = nil
    @State private var addMode = false
    @State private var showCanvas = false

    // Pin being moved via long-press + drag, and its live position in board space.
    @State private var draggedThreadID: String? = nil
    @State private var draggedPinLocation: CGPoint? = nil

    // Zoom / pan state.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var openThreads: [CommentThread] {
        threads.filter { $0.frameId == board.id }
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
        }
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .safeAreaInset(edge: .top) {
            if addMode {
                Text("Tap the board to place a comment")
                    .font(.workSans(.footnote))
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedThread) { thread in
            CommentThreadSheet(fileID: fileID, thread: thread, profiles: profiles) {
                Task { await load() }
            }
        }
        .sheet(isPresented: Binding(get: { newCommentPosition != nil },
                                    set: { if !$0 { newCommentPosition = nil } })) {
            if let position = newCommentPosition {
                NewCommentSheet(fileID: fileID,
                                pageID: board.pageID,
                                frameID: board.id,
                                position: position) {
                    newCommentPosition = nil
                    Task { await load() }
                }
            }
        }
    }

    @ViewBuilder
    private func boardLayer(fitted: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            RemoteImage(mediaID: mediaID, baseURL: baseURL, contentMode: .fit)
                .frame(width: fitted.width, height: fitted.height)

            ForEach(openThreads) { thread in
                if let position = thread.position {
                    let norm = PinMath.normalized(position: position, in: board.selrect)
                    let restingPoint = CGPoint(x: norm.x * fitted.width, y: norm.y * fitted.height)
                    let isDragged = draggedThreadID == thread.id
                    CommentPinView(thread: thread)
                        .scaleEffect(isDragged ? 1.3 : 1)
                        .shadow(radius: isDragged ? 6 : 0)
                        .position(isDragged ? (draggedPinLocation ?? restingPoint) : restingPoint)
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

    /// Long-press a pin to pick it up, drag it to a new spot, release to save.
    private func movePinGesture(thread: CommentThread, fitted: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                           coordinateSpace: .named(Self.boardSpace)))
            .onChanged { value in
                switch value {
                case .first(true):
                    if draggedThreadID != thread.id {
                        draggedThreadID = thread.id
                        draggedPinLocation = nil
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                case .second(true, let drag):
                    if let drag { draggedPinLocation = drag.location }
                default:
                    break
                }
            }
            .onEnded { value in
                defer {
                    draggedThreadID = nil
                    draggedPinLocation = nil
                }
                guard case .second(true, let drag?) = value,
                      fitted.width > 0, fitted.height > 0 else { return }
                let norm = CGPoint(x: min(max(drag.location.x / fitted.width, 0), 1),
                                   y: min(max(drag.location.y / fitted.height, 0), 1))
                let position = PinMath.canvasPosition(normalized: norm, in: board.selrect)
                Task { await moveThread(thread, to: position) }
            }
    }

    /// Optimistically repositions the pin, then persists it; reverts on failure.
    private func moveThread(_ thread: CommentThread, to position: Point) async {
        guard let client = appState.client else { return }
        let previous = threads
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index].position = position
        }
        do {
            try await client.updateThreadPosition(id: thread.id, frameID: board.id, position: position)
        } catch {
            threads = previous
            if case PenpotError.unauthorized = error { appState.logout() }
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

    private func load() async {
        guard let client = appState.client else { return }
        do {
            async let threadsTask = client.commentThreads(fileID: fileID)
            async let profilesTask = client.commentProfiles(fileID: fileID)
            threads = try await threadsTask
            profiles = (try? await profilesTask) ?? [:]
        } catch {
            if case PenpotError.unauthorized = error { appState.logout() }
        }
    }
}
