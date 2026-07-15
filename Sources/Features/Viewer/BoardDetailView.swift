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
                    CommentPinView(thread: thread)
                        .position(x: norm.x * fitted.width, y: norm.y * fitted.height)
                        .onTapGesture { selectedThread = thread }
                }
            }
        }
        .frame(width: fitted.width, height: fitted.height)
        .contentShape(Rectangle())
        .gesture(placeCommentGesture(fitted: fitted), including: addMode ? .all : .subviews)
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
