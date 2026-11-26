import SwiftUI

/// Plays a page's prototype natively (``PrototypeStageView``): Penpot's clicks, delays,
/// navigation with its transitions, overlays, going back, links and shapes fixed while a
/// board scrolls, on the boards the app renders itself. Penpot's own view mode
/// (``PenpotViewModeView``) loads the whole file into a web view, which a design system's
/// size can crash on an iPhone; this needs one page. The menu still opens it.
struct PrototypePlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var appState
    let fileID: String
    let teamID: String?
    let revision: Int?
    /// Pages that have something to play (the page picker only offers these).
    let pages: [CanvasPage]
    let title: String

    @State private var selectedPageID: String
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

    init(fileID: String, teamID: String?, revision: Int?, pages: [CanvasPage],
         initialPageID: String, initialBoardID: String? = nil, title: String) {
        self.fileID = fileID
        self.teamID = teamID
        self.revision = revision
        self.pages = pages
        self.title = title
        _selectedPageID = State(initialValue: initialPageID)
        _startBoardID = State(initialValue: initialBoardID)
    }

    private var currentPageName: String {
        pages.first { $0.id == selectedPageID }?.name ?? title
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.penpotPage.ignoresSafeArea()
                if let model, let renders {
                    PrototypeStage(handle: stage, zoom: zoom,
                                   onLoadingChange: { isRendering = $0 },
                                   onBoardChange: { currentBoardID = $0; renderFailed = false },
                                   onOpenURL: { openURL($0) },
                                   onRenderFailed: { renderFailed = true },
                                   showsExitButton: isFullScreen,
                                   onExitFullScreen: { withAnimation { isFullScreen = false } })
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
                } else if model == nil || isRendering {
                    PencilLoadingBadge(message: Text("Loading \(currentPageName)…"))
                } else if renderFailed && currentBoardID == nil {
                    ErrorStateView(message: .appLocalized("Couldn't load the presentation.")) {
                        renderFailed = false
                        if let model, let renders, let start = model.startBoard(preferred: startBoardID) {
                            stage.view?.play(model, renders: renders, from: start)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .principal) { pageSwitcher }
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            }
            .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        }
        .statusBarHidden(isFullScreen)
        .persistentSystemOverlays(isFullScreen ? .hidden : .automatic)
        .task(id: selectedPageID) { await loadPage() }
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
    }

    private var renders: BoardRenders? {
        guard let client = appState.client else { return nil }
        return BoardRenders(client: client, fileID: fileID, revision: revision,
                            profileID: appState.profile?.id ?? UUID().uuidString.lowercased(),
                            teamID: teamID)
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

    @ViewBuilder
    private var pageSwitcher: some View {
        if pages.count > 1 {
            Menu {
                PenpotMenuChoices(selection: $selectedPageID,
                                  options: pages.map { (value: $0.id, label: Text($0.name)) })
            } label: {
                HStack(spacing: 4) {
                    Text(currentPageName).font(.workSans(.headline)).lineLimit(1)
                    AppIcon.chevronDown.image(size: 12)
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Switch page, current \(currentPageName)")
        } else {
            Text(currentPageName).font(.workSans(.headline)).lineLimit(1)
        }
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
    let showsExitButton: Bool
    let onExitFullScreen: () -> Void

    func makeUIView(context: Context) -> PrototypeStageView {
        let view = PrototypeStageView()
        handle.view = view
        return view
    }

    func updateUIView(_ view: PrototypeStageView, context: Context) {
        handle.view = view
        view.onLoadingChange = onLoadingChange
        view.onBoardChange = onBoardChange
        view.onOpenURL = onOpenURL
        view.onRenderFailed = onRenderFailed
        view.onExitFullScreen = onExitFullScreen
        view.showsExitButton = showsExitButton
        view.zoom = zoom
    }
}
