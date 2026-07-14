import SwiftUI
import UIKit

/// Shows all boards in a file as a grid of Penpot-rendered thumbnails.
struct FileViewerView: View {
    @Environment(AppState.self) private var appState
    let file: FileListItem

    @State private var pages: [PenpotPageSummary] = []
    @State private var thumbnails: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var canvasPage: PenpotPageSummary?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    private var hasAnyContent: Bool { pages.contains(where: \.hasContent) }
    private var canvasPages: [CanvasPage] { pages.map { CanvasPage(id: $0.id, name: $0.name) } }

    var body: some View {
        content
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
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
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && pages.isEmpty {
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
                       systemImage: "rectangle.dashed",
                       description: "This file has no boards or objects yet. Use Penpot on your computer to add content.") {
            if let firstPage = pages.first {
                Button {
                    canvasPage = firstPage
                } label: {
                    Label("Open canvas", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func pageSection(_ page: PenpotPageSummary, baseURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(page.name).font(.title3.bold())
                Spacer()
                // Explicit plural entry in the catalog ("%lld boards") — the automatic
                // inflect engine can't be trusted for German.
                Text("\(page.boards.count) boards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { canvasPage = page } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open canvas")
            }

            if page.boards.isEmpty {
                if page.canvasObjectCount > 0 {
                    canvasContentCard(for: page)
                } else {
                    Text("No boards on this page")
                        .font(.footnote)
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
                                            teamID: file.teamId,
                                            pages: canvasPages)
                        } label: {
                            BoardThumbnailCard(board: board,
                                               mediaID: thumbnails[board.id],
                                               baseURL: baseURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Shown for a page whose only content lives directly on the canvas (outside any
    /// board). Penpot renders no thumbnails for loose shapes, so this routes to the
    /// live canvas instead.
    private func canvasContentCard(for page: PenpotPageSummary) -> some View {
        Button { canvasPage = page } label: {
            VStack(spacing: 8) {
                Image(systemName: "square.on.square.dashed")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("\(page.canvasObjectCount) objects on the canvas")
                    .font(.subheadline.weight(.medium))
                Text("Not inside a board — open the canvas to view them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the live canvas")
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let fileTask = client.file(id: file.id)
            async let thumbsTask = client.objectThumbnails(fileID: file.id)
            let (loadedFile, loadedThumbs) = try await (fileTask, thumbsTask)
            pages = loadedFile.pages
            thumbnails = loadedThumbs
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }
}

private struct BoardThumbnailCard: View {
    let board: Board
    let mediaID: String?
    let baseURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground))
                RemoteImage(mediaID: mediaID, baseURL: baseURL, contentMode: .fit)
                    .padding(8)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))

            Text(board.name)
                .font(.subheadline)
                .lineLimit(1)
        }
    }
}
