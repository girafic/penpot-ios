import SwiftUI
import UIKit

/// Shows all boards in a file as a grid of Penpot-rendered thumbnails.
struct FileViewerView: View {
    @Environment(AppState.self) private var appState
    let file: FileListItem

    @State private var boards: [Board] = []
    @State private var thumbnails: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        content
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && boards.isEmpty {
            LoadingView(message: "Loading file…")
        } else if let errorMessage, boards.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if boards.isEmpty {
            EmptyStateView(title: "No boards", systemImage: "rectangle.on.rectangle",
                           description: "This file has no boards to display.")
        } else if let baseURL = appState.client?.baseURL {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(boards) { board in
                        NavigationLink {
                            BoardDetailView(fileID: file.id,
                                            board: board,
                                            mediaID: thumbnails[board.id],
                                            baseURL: baseURL)
                        } label: {
                            BoardThumbnailCard(board: board,
                                               mediaID: thumbnails[board.id],
                                               baseURL: baseURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
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
            boards = loadedFile.boards
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
