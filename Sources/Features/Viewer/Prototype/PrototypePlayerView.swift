import SwiftUI
import UIKit

/// Plays a page's prototype natively (``PrototypeStageView``): Penpot's clicks, delays,
/// navigation with its transitions, overlays, going back, links and shapes fixed while a
/// board scrolls, on the boards the app renders itself. Penpot's own view mode
/// (``PenpotViewModeView``) loads the whole file into a web view, which a design system's
/// size can crash on an iPhone; this needs one page. The menu still opens it.
struct PrototypePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    let fileID: String
    let teamID: String?
    let revision: Int?
    /// The file's pages: as in Penpot, every page plays, with or without interactions
    /// (the navigation buttons page through its boards).
    let pages: [CanvasPage]
    let title: String
    /// Board id → Penpot's thumbnail media id, for the board picker.
    let thumbnails: [String: String]

    @State private var selectedPageID: String
    @State private var barWidth: CGFloat?
    /// The board to start on, for the page it belongs to.
    @State private var startBoardID: String?
    @State private var model: PrototypeModel?
    @State private var loadFailed = false
    @State private var isRendering = false
    @State private var renderFailed = false
    @State private var currentBoardID: String?
    @State private var zoom: PrototypeZoom = .fit
    @State private var isFullScreen = false
    @State private var showsViewMode = false
    @State private var stage = PrototypeStageHandle()
    /// Penpot's thumbnails panel: the page's boards to pick from.
    @State private var showsBoards = false

    // Comments (Penpot's comments mode)
    @State private var isCommenting = false
    @State private var threads: [CommentThread] = []
    /// Bumped when the threads change, so the stage only rebuilds its pins then.
    @State private var threadsRevision = 0
    @State private var profiles: [String: Profile] = [:]
    @State private var selectedThread: CommentThread?
    @State private var newComment: PendingComment?
    @State private var showsThreadList = false
    @State private var commentError: String?
    @State private var commentsTask: Task<Void, Never>?

    /// A tap in comments mode, waiting for its text.
    private struct PendingComment: Identifiable {
        let id = UUID()
        let position: Point
        let frameID: String
    }

    init(fileID: String, teamID: String?, revision: Int?, pages: [CanvasPage],
         initialPageID: String, initialBoardID: String? = nil, title: String,
         thumbnails: [String: String] = [:]) {
        self.fileID = fileID
        self.teamID = teamID
        self.revision = revision
        self.pages = pages
        self.title = title
        self.thumbnails = thumbnails
        _selectedPageID = State(initialValue: initialPageID)
        _startBoardID = State(initialValue: initialBoardID)
    }

    @Environment(LiveFile.self) private var live: LiveFile?

    private var currentPageName: String {
        pages.first { $0.id == selectedPageID }?.name ?? title
    }

    /// "Done" becomes an X where the page's name doesn't fit beside it
    /// (``NavigationBarFit``).
    private var compactBar: Bool {
        guard let barWidth else { return false }
        return !NavigationBarFit.titleFits(currentPageName, chevron: pages.count > 1,
                                          leading: .text(.appLocalized("Done")),
                                          trailingIcons: 2, width: barWidth)
    }

    /// The page's threads, as the comment filters let them show.
    private var pins: [CommentThread] {
        settings.commentFilters.apply(threads.filter { $0.pageId == selectedPageID },
                                      profileID: appState.profile?.id)
    }

    var body: some View {
        NavigationStack {
            // The board picker sits below the stage, not over it: a SwiftUI view over the
            // hosted UIKit stage doesn't get its taps.
            VStack(spacing: 0) {
                stageArea
                if showsBoards, let model, !model.viewerBoards.isEmpty {
                    boardStrip(model)
                        .transition(.move(edge: .bottom))
                }
            }
            .background(Color.penpotPage.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                if isCommenting && !isFullScreen {
                    Text("Tap the board to place a comment")
                        .font(.workSans(.footnote))
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
            .trackingWidth($barWidth)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { DoneButton(compact: compactBar) { dismiss() } }
                ToolbarItem(placement: .principal) { pageSwitcher }
                // Where the page's name lacks room, comments are in the menu too, except
                // the way out of comments mode.
                if !compactBar || isCommenting {
                    ToolbarItem(placement: .topBarTrailing) { commentsButton }
                }
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            }
            .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        }
        .statusBarHidden(isFullScreen)
        .persistentSystemOverlays(isFullScreen ? .hidden : .automatic)
        .task(id: selectedPageID) { await loadPage() }
        // Someone changed the page: the model and what changed again, in place.
        .task(id: live?.pageRevision(selectedPageID)) { await reloadLivePage() }
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
        .onChange(of: selectedPageID) {
            // The starting board belonged to the first page; another page starts at its flow.
            startBoardID = nil
        }
        .fullScreenCover(isPresented: $showsViewMode) {
            if let baseURL = appState.client?.baseURL {
                PenpotViewModeView(baseURL: baseURL, fileID: fileID, pages: pages,
                                   initialPageID: selectedPageID,
                                   initialFrameID: currentBoardID,
                                   initialIndex: currentBoardID.flatMap {
                                       model?.page.viewerFrameIDs.firstIndex(of: $0)
                                   } ?? 0,
                                   title: title)
            }
        }
        .sheet(item: $selectedThread) { thread in
            CommentThreadSheet(fileID: fileID, thread: thread, profiles: profiles, teamID: teamID) {
                reloadComments()
            }
        }
        .sheet(item: $newComment) { pending in
            NewCommentSheet(fileID: fileID, pageID: selectedPageID, frameID: pending.frameID,
                            position: pending.position, teamID: teamID) {
                newComment = nil
                reloadComments()
            }
        }
        .sheet(isPresented: $showsThreadList) {
            CommentThreadListSheet(threads: threads, profiles: profiles, boardID: "",
                                   pageID: selectedPageID, onSelect: { thread in
                showThread(thread)
            })
        }
        .alert("Something went wrong", isPresented: Binding(get: { commentError != nil },
                                                            set: { if !$0 { commentError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(commentError ?? "")
        }
    }

    private var stageArea: some View {
            ZStack {
                Color.penpotPage.ignoresSafeArea()
                if let model, let renders {
                    PrototypeStage(handle: stage, zoom: zoom,
                                   onLoadingChange: { isRendering = $0 },
                                   onBoardChange: { currentBoardID = $0; renderFailed = false },
                                   onOpenURL: { openURL($0) },
                                   onRenderFailed: { renderFailed = true },
                                   isFullScreen: isFullScreen,
                                   showsNavigation: settings.prototypeNavigation,
                                   presentsOnExternalDisplay: settings.prototypeOnExternalDisplay,
                                   onExitFullScreen: { withAnimation { isFullScreen = false } },
                                   onShowBoards: { withAnimation { showsBoards.toggle() } },
                                   isCommenting: isCommenting,
                                   threads: pins,
                                   threadsKey: "\(threadsRevision) \(selectedPageID) \(String(describing: settings.commentFilters))",
                                   onSelectThread: { selectedThread = $0 },
                                   onPlaceComment: { position, frameID in
                                       newComment = PendingComment(position: position, frameID: frameID)
                                   },
                                   onMoveThread: { thread, position, frameID in
                                       Task { await moveThread(thread, to: position, frameID: frameID) }
                                   })
                        .ignoresSafeArea(edges: isFullScreen ? .all : .bottom)
                        .task(id: model.pageID) {
                            if let start = model.startBoard(preferred: startBoardID) {
                                stage.view?.play(model, renders: renders, from: start)
                            }
                        }
                }
                if loadFailed {
                    ErrorStateView(message: .appLocalized("Couldn't load the presentation.")) {
                        Task { await loadPage() }
                    }
                } else if let model, model.viewerBoards.isEmpty {
                    EmptyStateView(title: "No boards on this page", icon: .board)
                } else if model != nil, !isRendering, renderFailed, currentBoardID == nil {
                    ErrorStateView(message: .appLocalized("Couldn't load the presentation.")) {
                        renderFailed = false
                        if let model, let renders, let start = model.startBoard(preferred: startBoardID) {
                            stage.view?.play(model, renders: renders, from: start)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isLoading { loadingBadge }
            }
    }

    /// Penpot's thumbnails panel (`viewer/thumbnails.cljs`).
    private func boardStrip(_ model: PrototypeModel) -> some View {
        PrototypeBoardStrip(boards: model.viewerBoards.compactMap(model.board),
                            currentID: currentBoardID, fileID: fileID, revision: revision,
                            teamID: teamID, thumbnails: thumbnails,
                            onSelect: { stage.view?.go(to: $0) },
                            onClose: { withAnimation { showsBoards = false } })
    }

    /// Penpot's comments mode: pins on the board, a tap places a comment.
    private var commentsButton: some View {
        Button {
            withAnimation { isCommenting.toggle() }
        } label: {
            AppIcon.comments.image
                .foregroundStyle(isCommenting ? Color.penpotAccent : Color.primary)
        }
        .accessibilityLabel("Comments")
        .accessibilityAddTraits(isCommenting ? .isSelected : [])
    }

    /// The page or a board is still loading.
    private var isLoading: Bool {
        guard !loadFailed else { return false }
        guard let model else { return true }
        return isRendering && !model.viewerBoards.isEmpty
    }

    /// Never over the middle of the design: a small pencil in the corner the navigation
    /// leaves free, in line with the counter and styled like its buttons.
    private var loadingBadge: some View {
        PencilLoaderView()
            .frame(width: 36)
            .frame(width: 56, height: 38)
            .background(Color.penpotPage, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.penpotSurface))
            .padding(8)
    }

    private var renders: BoardRenders? {
        guard let client = appState.client else { return nil }
        // Root boards by what changed; a nested viewer frame, drawn on its own, with its page.
        var revisions: [String: Int] = [:]
        if let live, let model {
            let pageRevision = live.pageRevision(selectedPageID)
            for id in model.viewerBoards {
                revisions[id] = model.rootBoardIDs.contains(id) ? live.revision(of: id) : pageRevision
            }
        }
        return BoardRenders(client: client, fileID: fileID, revision: revision,
                            profileID: appState.profile?.id ?? UUID().uuidString.lowercased(),
                            teamID: teamID, boardRevisions: revisions,
                            pageRevision: live?.pageRevision(selectedPageID))
    }

    private func reloadLivePage() async {
        guard let client = appState.client, live?.pageRevision(selectedPageID) != nil,
              model?.pageID == selectedPageID,
              let page = try? await client.page(fileID: fileID, pageID: selectedPageID),
              !Task.isCancelled else { return }
        let updated = PrototypeModel(pageID: selectedPageID, page: page)
        model = updated
        if let renders { stage.view?.update(updated, renders: renders) }
    }

    private func loadPage() async {
        guard let client = appState.client else { return }
        loadFailed = false
        if model?.pageID != selectedPageID { model = nil }
        currentBoardID = nil
        do {
            let page = try await client.page(fileID: fileID, pageID: selectedPageID)
            guard !Task.isCancelled else { return }
            model = PrototypeModel(pageID: selectedPageID, page: page)
        } catch {
            guard !Task.isCancelled else { return }
            if case PenpotError.unauthorized = error { appState.logout() }
            loadFailed = true
        }
    }

    // MARK: Comments

    private func reloadComments() {
        commentsTask?.cancel()
        commentsTask = Task { await loadComments() }
    }

    private func loadComments() async {
        guard let client = appState.client else { return }
        // "Only yours" and "Mentions" need the profile id.
        if let teamID { await appState.resolveProfileIfNeeded(teamID: teamID) }
        do {
            async let threadsTask = client.commentThreads(fileID: fileID)
            async let profilesTask = client.commentProfiles(fileID: fileID)
            let fetched = try await threadsTask
            let fetchedProfiles = (try? await profilesTask) ?? [:]
            guard !Task.isCancelled else { return }
            threads = fetched
            profiles = fetchedProfiles
            threadsRevision += 1
        } catch {
            guard !Task.isCancelled else { return }
            if case PenpotError.unauthorized = error { appState.logout() }
        }
    }

    /// Puts the pin where it was dropped at once, then saves it with the board it is on;
    /// on failure only this pin goes back.
    private func moveThread(_ thread: CommentThread, to position: Point, frameID: String) async {
        guard let client = appState.client,
              let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        commentsTask?.cancel()
        let previous = threads[index].position
        threads[index].position = position
        threadsRevision += 1
        do {
            try await client.updateThreadPosition(id: thread.id, frameID: frameID, position: position)
            reloadComments()
        } catch {
            if let index = threads.firstIndex(where: { $0.id == thread.id }) {
                threads[index].position = previous
                threadsRevision += 1
            }
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                commentError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// A thread picked from the file's list: its board, when the viewer has it, with the
    /// pins showing, and the thread open.
    private func showThread(_ thread: CommentThread) {
        if thread.pageId == selectedPageID, let model,
           let boardID = model.viewerBoards.first(where: { id in
               model.board(id).map { PinMath.thread(thread, isOn: $0, pageBoardIDs: model.rootBoardIDs) } ?? false
           }) {
            stage.view?.go(to: boardID)
            withAnimation { isCommenting = true }
        }
        selectedThread = thread
    }

    // MARK: Chrome

    private var optionsMenu: some View {
        Menu {
            PenpotMenuChoices(selection: $zoom, options: [
                (value: .fit, label: Text("Fit - Scale down to fit")),
                (value: .fill, label: Text("Fill - Scale to fill")),
                (value: .actual, label: Text(1.0, format: .percent)),
            ])
            Divider()
            Button { withAnimation { isFullScreen = true } } label: { Text("Full screen") }
            Button { settings.prototypeNavigation.toggle() } label: {
                PenpotMenuCheckLabel(label: Text("Navigation buttons"), isOn: settings.prototypeNavigation)
            }
            Button { withAnimation { showsBoards.toggle() } } label: {
                PenpotMenuCheckLabel(label: Text("Boards"), isOn: showsBoards)
            }
            // A display by cable or AirPlay: the prototype alone on it, or the phone mirrored.
            if ExternalDisplay.shared.isConnected {
                Button { settings.prototypeOnExternalDisplay.toggle() } label: {
                    PenpotMenuCheckLabel(label: Text("Show on external display"),
                                         isOn: settings.prototypeOnExternalDisplay)
                }
            }
            Divider()
            if compactBar && !isCommenting {
                Button { withAnimation { isCommenting = true } } label: {
                    PenpotMenuCheckLabel(label: Text("Comments"), isOn: false)
                }
            }
            Button { showsThreadList = true } label: { Text("Comments in this file") }
            if let model, !model.flows.isEmpty {
                Section("Flow starts") {
                    ForEach(model.flows, id: \.id) { flow in
                        Button {
                            if let start = flow.startingFrame, let renders {
                                stage.view?.play(model, renders: renders, from: start)
                            }
                        } label: {
                            Text(verbatim: flow.name ?? "")
                        }
                    }
                }
            }
            Divider()
            Button { showsViewMode = true } label: { Text("Open in Penpot’s view mode") }
        } label: {
            AppIcon.more.image
        }
        .accessibilityLabel("Prototype options")
    }

    private var pageSwitcher: some View {
        PageSwitcher(pages: pages, selection: $selectedPageID, fallbackTitle: title)
    }
}

/// Lets SwiftUI start playback on the UIKit stage it hosts.
@MainActor
final class PrototypeStageHandle {
    weak var view: PrototypeStageView?
}

/// Hosts ``PrototypeStageView`` in SwiftUI.
struct PrototypeStage: UIViewRepresentable {
    let handle: PrototypeStageHandle
    let zoom: PrototypeZoom
    let onLoadingChange: (Bool) -> Void
    let onBoardChange: (String) -> Void
    let onOpenURL: (URL) -> Void
    let onRenderFailed: () -> Void
    let isFullScreen: Bool
    let showsNavigation: Bool
    let presentsOnExternalDisplay: Bool
    let onExitFullScreen: () -> Void
    let onShowBoards: () -> Void
    let isCommenting: Bool
    let threads: [CommentThread]
    /// Changes when the pins do: a load, another page or other comment filters.
    let threadsKey: String
    let onSelectThread: (CommentThread) -> Void
    let onPlaceComment: (Point, String) -> Void
    let onMoveThread: (CommentThread, Point, String) -> Void

    final class Coordinator {
        var threadsKey = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PrototypeStageView {
        let view = PrototypeStageView()
        handle.view = view
        return view
    }

    static func dismantleUIView(_ view: PrototypeStageView, coordinator: Coordinator) {
        ExternalDisplay.shared.present(view, isOn: false)
    }

    func updateUIView(_ view: PrototypeStageView, context: Context) {
        handle.view = view
        view.onLoadingChange = onLoadingChange
        view.onBoardChange = onBoardChange
        view.onOpenURL = onOpenURL
        view.onRenderFailed = onRenderFailed
        view.onExitFullScreen = onExitFullScreen
        view.isFullScreen = isFullScreen
        view.showsNavigation = showsNavigation
        view.isRightToLeft = context.environment.layoutDirection == .rightToLeft
        view.zoom = zoom
        view.onShowBoards = onShowBoards
        view.onSelectThread = onSelectThread
        view.onPlaceComment = onPlaceComment
        view.onMoveThread = onMoveThread
        view.isCommenting = isCommenting
        ExternalDisplay.shared.present(view, isOn: presentsOnExternalDisplay)
        // The pins only change with the threads, not with every update of the player.
        if context.coordinator.threadsKey != threadsKey {
            context.coordinator.threadsKey = threadsKey
            view.threads = threads
        }
    }
}
