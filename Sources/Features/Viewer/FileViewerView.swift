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

    private var allBoards: [Board] { pages.flatMap(\.boards) }
    private var canvasPages: [CanvasPage] { pages.map { CanvasPage(id: $0.id, name: $0.name) } }

    var body: some View {
        content
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .fullScreenCover(item: $canvasPage) { page in
                if let baseURL = appState.client?.baseURL {
                    PenpotCanvasView(baseURL: baseURL, fileID: file.id, teamID: file.teamId,
                                     pages: canvasPages, initialPageID: page.id, title: file.name)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && allBoards.isEmpty {
            LoadingView(message: "Loading file…")
        } else if let errorMessage, allBoards.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if allBoards.isEmpty {
            EmptyStateView(title: "No boards", systemImage: "rectangle.on.rectangle",
                           description: "This file has no boards to display.")
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

    @ViewBuilder
    private func pageSection(_ page: PenpotPageSummary, baseURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(page.name).font(.title3.bold())
                Spacer()
                Text("^[\(page.boards.count) board](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { canvasPage = page } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open canvas")
            }

            if page.boards.isEmpty {
                Text("No boards on this page")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
