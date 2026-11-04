import SwiftUI
import UIKit

/// A board's picture: Penpot's own thumbnail when it has one, otherwise a preview drawn
/// on the device (``BoardRenders/preview(of:)``). The pencil loader shows while that
/// preview is being made; the image glyph stays if it can't be had.
struct BoardImage: View {
    @Environment(AppState.self) private var appState
    let fileID: String
    /// The file's `revn`; a new revision renders the preview again.
    let revision: Int?
    let board: Board
    let mediaID: String?
    let baseURL: URL
    var contentMode: ContentMode = .fit
    /// `false` uses a preview only if one is cached: the board detail shows the board's PDF
    /// instead and needs no second render.
    var rendersMissingPreview = true
    /// For text in the team's own fonts.
    var teamID: String? = nil

    @State private var preview: UIImage?
    @State private var isRendering = false

    var body: some View {
        if mediaID != nil {
            RemoteImage(mediaID: mediaID, baseURL: baseURL, contentMode: contentMode)
        } else {
            Group {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder
                }
            }
            .task(id: "\(board.id)@\(revision ?? 0)") { await renderPreview() }
        }
    }

    /// Same look as ``RemoteImage``'s placeholder, with the loader in place of the glyph.
    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if isRendering {
                PencilLoaderView()
                    .frame(width: 44)
            } else {
                AppIcon.image.image
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func renderPreview() async {
        guard let client = appState.client else { return }
        let renders = BoardRenders(client: client, fileID: fileID, revision: revision,
                                   profileID: appState.profile?.id ?? UUID().uuidString.lowercased(),
                                   teamID: teamID)
        guard rendersMissingPreview else {
            preview = await BoardPreviewRenderer.shared.cachedImage(
                for: renders.key(for: board, kind: .preview))
            return
        }
        isRendering = true
        preview = await renders.preview(of: board)
        isRendering = false
    }
}
