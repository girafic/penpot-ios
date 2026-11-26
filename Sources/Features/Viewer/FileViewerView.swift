import SwiftUI
import UIKit

/// Shows all boards in a file as a grid of Penpot-rendered thumbnails.
struct FileViewerView: View {
    @Environment(AppState.self) private var appState
    let file: FileListItem

    @State private var pages: [PenpotPageSummary] = []
    @State private var thumbnails: [String: String] = [:]
    /// The file's `revn`: keys the previews rendered for boards without a thumbnail.
    @State private var revision: Int?
    /// Only the first page is shown so far; the whole file is still loading.
    @State private var showsFirstPageOnly = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var canvasPage: PenpotPageSummary?
    @State private var nativeCanvasPage: PenpotPageSummary?
    @State private var viewModePage: PenpotPageSummary?
    @State private var showShareLinks = false
    @State private var showVersions = false
    @State private var showFileInfo = false
    @State private var exportBoardTarget: Board?
    @State private var isExporting = false
    @State private var exportedDocument: ExportedDocument?
    @State private var actionError: String?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    private var hasAnyContent: Bool { pages.contains(where: \.hasContent) }
    private var canvasPages: [CanvasPage] { pages.map { CanvasPage(id: $0.id, name: $0.name) } }
    private var prototypePages: [CanvasPage] {
        pages.filter(\.hasPrototype).map { CanvasPage(id: $0.id, name: $0.name) }
    }

    var body: some View {
        content
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFileInfo = true } label: { AppIcon.info.image }
                        .accessibilityLabel("File info")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showVersions = true } label: { AppIcon.history.image }
                        .accessibilityLabel("Version history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showShareLinks = true } label: { AppIcon.share.image }
                        .accessibilityLabel("Share links")
                }
            }
            .task { await load() }
            .refreshable { await load() }
            // Reload on dismiss so boards added elsewhere in the meantime (e.g. on the
            // desktop) show up as thumbnails right away.
            .fullScreenCover(item: $canvasPage, onDismiss: { Task { await load() } }) { page in
                if let baseURL = appState.client?.baseURL {
                    PenpotCanvasView(baseURL: baseURL, fileID: file.id, teamID: file.teamId,
                                     pages: canvasPages, initialPageID: page.id, title: file.name)
                }
            }
            .fullScreenCover(item: $nativeCanvasPage) { page in
                PageCanvasView(page: page, fileID: file.id, revision: revision,
                               thumbnails: thumbnails, teamID: file.teamId,
                               pages: canvasPages, fileName: file.name)
            }
            .fullScreenCover(item: $viewModePage) { page in
                PrototypePlayerView(fileID: file.id, teamID: file.teamId, revision: revision,
                                    pages: prototypePages, initialPageID: page.id,
                                    title: file.name)
            }
            .sheet(isPresented: $showShareLinks) {
                ShareLinksSheet(fileID: file.id, fallbackPageIDs: pages.map(\.id))
            }
            // Restore bumps revn and regenerates all thumbnails server-side — reload so
            // boards re-fetch (new media ids, so no cache invalidation needed).
            .sheet(isPresented: $showVersions) {
                VersionsSheet(fileID: file.id, teamID: file.teamId,
                              onRestored: { Task { await load() } })
            }
            .sheet(isPresented: $showFileInfo) {
                FileInfoSheet(fileID: file.id, fileName: file.name)
            }
            .sheet(item: $exportBoardTarget) { board in
                ExportBoardSheet(board: board) { format, scale in
                    Task { await exportBoard(board, format: format, scale: scale) }
                }
            }
            .fileExportPresentation(isExporting: $isExporting, document: $exportedDocument)
            .alert("Something went wrong", isPresented: actionErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
    }

    private var actionErrorAlert: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && (pages.isEmpty || (showsFirstPageOnly && !hasAnyContent)) {
            LoadingView(message: "Loading file…")
        } else if let errorMessage, !hasAnyContent {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if !hasAnyContent {
            emptyFileView
        } else if let baseURL = appState.client?.baseURL {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(pages) { page in
                        pageSection(page, baseURL: baseURL)
                    }
                    if showsFirstPageOnly {
                        HStack(spacing: 12) {
                            PencilLoaderView()
                                .frame(width: 44)
                            Text("Loading file…")
                                .font(.workSans(.footnote))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
        }
    }

    /// Shown when no page has boards or canvas objects. The canvas stays reachable so
    /// an empty file isn't a dead end (and files whose page data the app couldn't read
    /// remain viewable), but editing only happens in Penpot on a computer.
    private var emptyFileView: some View {
        EmptyStateView(title: "File is empty",
                       icon: .board,
                       description: "This file has no boards or objects yet. Use Penpot on your computer to add content.") {
            if let firstPage = pages.first {
                Button {
                    canvasPage = firstPage
                } label: {
                    AppIcon.expand.label("Open canvas")
                }
                .buttonStyle(.penpot(.primary, size: .compact))
            }
        }
    }

    @ViewBuilder
    private func pageSection(_ page: PenpotPageSummary, baseURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(page.name).font(.workSans(.title3, weight: .bold))
                Spacer()
                // Explicit plural entry in the catalog ("%lld boards") — the automatic
                // inflect engine can't be trusted for German.
                Text("\(page.boards.count) boards")
                    .font(.workSans(.caption))
                    .foregroundStyle(.secondary)
                if page.hasPrototype {
                    Button { viewModePage = page } label: {
                        AppIcon.play.image
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Play prototype")
                }
                // The native canvas shows boards and loose shapes alike; Penpot's own (web)
                // canvas is one tap away from there.
                Button {
                    nativeCanvasPage = page
                } label: {
                    AppIcon.expand.image
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open canvas")
            }

            if page.boards.isEmpty {
                if page.canvasObjectCount > 0 {
                    canvasContentCard(for: page)
                } else {
                    Text("No boards on this page")
                        .font(.workSans(.footnote))
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(page.boards) { board in
                        NavigationLink {
                            BoardDetailView(fileID: file.id,
                                            board: board,
                                            mediaID: thumbnails[board.id],
                                            baseURL: baseURL,
                                            revision: revision,
                                            teamID: file.teamId,
                                            pages: canvasPages,
                                            prototypePages: pages.filter(\.hasPrototype),
                                            pageBoardIDs: Set(page.boards.map(\.id)))
                        } label: {
                            BoardThumbnailCard(fileID: file.id,
                                               revision: revision,
                                               board: board,
                                               mediaID: thumbnails[board.id],
                                               baseURL: baseURL,
                                               teamID: file.teamId)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { exportBoardTarget = board } label: {
                                AppIcon.download.label("Export board…")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Shown for a page whose only content lives directly on the canvas (outside any
    /// board). Penpot renders no thumbnails for loose shapes; the native canvas draws them.
    private func canvasContentCard(for page: PenpotPageSummary) -> some View {
        Button { nativeCanvasPage = page } label: {
            VStack(spacing: 8) {
                AppIcon.board.image
                    .font(.workSans(.title2))
                    .foregroundStyle(.secondary)
                Text("\(page.canvasObjectCount) objects on the canvas")
                    .font(.workSans(.subheadline, weight: .medium))
                Text("Not inside a board — open the canvas to view them.")
                    .font(.workSans(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the live canvas")
    }

    /// A big file takes `get-file` tens of seconds, so: a file opened before shows its
    /// cached outline at once and is only revalidated (304 when unchanged); a file opened
    /// for the first time shows its first page alone while the whole file loads.
    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        let cache = FileOutlineCache.shared
        let cached = cache.entry(server: client.baseURL, fileID: file.id)
        if pages.isEmpty, let cached { apply(cached.outline) }

        let firstPage: Task<Void, Never>? = pages.isEmpty ? Task {
            guard let page = try? await client.firstPage(fileID: file.id),
                  !Task.isCancelled, pages.isEmpty else { return }
            pages = [page]
            showsFirstPageOnly = true
        } : nil
        defer {
            firstPage?.cancel()
            showsFirstPageOnly = false
        }

        do {
            async let thumbsTask = client.objectThumbnails(fileID: file.id)
            switch try await client.fileOutline(id: file.id, ifNoneMatch: cached?.etag) {
            case .notModified:
                break
            case .loaded(let outline, let etag):
                firstPage?.cancel()
                apply(outline)
                if let etag {
                    cache.store(.init(etag: etag, outline: outline), server: client.baseURL, fileID: file.id)
                }
            }
            thumbnails = try await thumbsTask
        } catch {
            // A cached outline stays up (offline, server hiccup); a lone first page would
            // pass for the whole file, so it makes way for the error.
            if showsFirstPageOnly { pages = [] }
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func apply(_ outline: FileOutline) {
        pages = outline.pages
        revision = outline.revision
        showsFirstPageOnly = false
    }

    private func exportBoard(_ board: Board, format: BoardExportFormat, scale: Int) async {
        guard let client = appState.client else { return }
        isExporting = true
        defer { isExporting = false }
        if let teamID = file.teamId {
            await appState.resolveProfileIfNeeded(teamID: teamID)
        }
        // profile-id is only the exporter's progress pub/sub topic (not auth-checked);
        // with wait=true any uuid works, so a cold session still exports.
        let profileID = appState.profile?.id ?? UUID().uuidString.lowercased()
        do {
            let (data, filename) = try await client.exportBoard(
                fileID: file.id, pageID: board.pageID, boardID: board.id,
                boardName: board.name, profileID: profileID, format: format, scale: scale)
            exportedDocument = try ExportedDocument.file(
                data: data, filename: filename,
                fallbackName: "\(board.name).\(format.fileExtension)")
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private struct BoardThumbnailCard: View {
    let fileID: String
    let revision: Int?
    let board: Board
    let mediaID: String?
    let baseURL: URL
    let teamID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground))
                BoardImage(fileID: fileID, revision: revision, board: board,
                           mediaID: mediaID, baseURL: baseURL, teamID: teamID)
                    .padding(8)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            Text(board.name)
                .font(.workSans(.subheadline))
                .lineLimit(1)
        }
    }
}
