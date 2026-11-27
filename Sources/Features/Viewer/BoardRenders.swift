import UIKit

/// Fetches a board's pictures for the native board views: Penpot's own thumbnail, a
/// preview, and the vector PDF. PDFs are rendered on the device (``LocalBoardRenderer``);
/// the exporter (``BoardPreviewRenderer``'s queue) is only the fallback when that fails.
struct BoardRenders: Sendable {
    let client: PenpotClient
    let fileID: String
    /// The file's `revn`, keying the renders.
    let revision: Int?
    /// Only the exporter's progress topic, not auth-checked (see `exportBoard`).
    let profileID: String
    /// For text in the team's own fonts (`get-font-variants`).
    var teamID: String? = nil
    /// Boards that changed live (``LiveFile``), with the revision they changed at: only
    /// those are drawn again, the rest keep the renders of ``revision``.
    var boardRevisions: [String: Int] = [:]
    /// The revision the page last changed at live: its islands are drawn at that one.
    var pageRevision: Int? = nil

    /// The revision a board, an island or a board's prototype layer is drawn at.
    func revision(for id: String) -> Int {
        if id.hasPrefix(PenpotSVG.islandPrefix) { return pageRevision ?? revision ?? 0 }
        let boardID = PenpotSVG.Page.layer(id)?.board ?? id
        return boardRevisions[boardID] ?? revision ?? 0
    }

    func key(for board: Board, kind: BoardPreviewRenderer.Kind) -> BoardPreviewRenderer.Key {
        .init(server: client.baseURL.absoluteString, fileID: fileID, boardID: board.id,
              revision: revision(for: board.id), kind: kind)
    }

    /// Penpot's thumbnail when the board has one, else a preview drawn from its PDF.
    func picture(of board: Board, mediaID: String?) async -> UIImage? {
        if let mediaID,
           let image = await RemoteImageLoader.shared.image(mediaID: mediaID, baseURL: client.baseURL) {
            return image
        }
        return await preview(of: board)
    }

    /// A ``BoardPreviewRenderer/targetPixels`` bitmap of the board, drawn from its PDF and
    /// cached; the exporter's PNG if there is no PDF.
    func preview(of board: Board) async -> UIImage? {
        let renderer = BoardPreviewRenderer.shared
        let key = key(for: board, kind: .preview)
        if let cached = await renderer.cachedImage(for: key) { return cached }
        if let document = await vector(of: board, exporterFallback: false),
           let page = document.page(at: 1),
           let image = await Self.rasterize(page) {
            if let png = image.pngData() { await renderer.store(png, for: key) }
            return image
        }
        let (client, fileID, profileID) = (client, fileID, profileID)
        let scale = BoardPreviewRenderer.scale(width: board.selrect.width, height: board.selrect.height)
        return await renderer.image(for: key) {
            try await client.renderBoardPreview(fileID: fileID, pageID: board.pageID,
                                                boardID: board.id, boardName: board.name,
                                                profileID: profileID, scale: scale)
        }
    }

    /// The board as a vector PDF: rendered on the device, else by the exporter.
    func vector(of board: Board, exporterFallback: Bool = true) async -> CGPDFDocument? {
        if let data = try? await LocalBoardRenderer.shared.pdf(of: board, using: self),
           let document = Self.document(data) {
            return document
        }
        // A caller that went away doesn't want the exporter's version either.
        guard exporterFallback, !Task.isCancelled else { return nil }
        let (client, fileID, profileID) = (client, fileID, profileID)
        let data = await BoardPreviewRenderer.shared.pdf(for: key(for: board, kind: .vector)) {
            try await client.exportBoard(fileID: fileID, pageID: board.pageID, boardID: board.id,
                                         boardName: board.name, profileID: profileID,
                                         format: .pdf, scale: 1).data
        }
        return data.flatMap(Self.document)
    }

    private static func document(_ data: Data) -> CGPDFDocument? {
        CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init)
    }

    /// A document drawn on the device (an asset's sample) as a cached bitmap whose long
    /// side is `pixels`; `id` names it in the cache, beside the file's boards.
    func picture(of drawing: @autoclosure () -> PenpotSVG.Drawing, id: String, name: String,
                 pixels: Double = BoardPreviewRenderer.targetPixels) async -> UIImage? {
        let renderer = BoardPreviewRenderer.shared
        let key = BoardPreviewRenderer.Key(server: client.baseURL.absoluteString, fileID: fileID, boardID: id,
                                           revision: revision ?? 0, kind: .preview)
        if let cached = await renderer.cachedImage(for: key) { return cached }
        var vectorKey = key
        vectorKey.kind = .vector
        guard let data = try? await LocalBoardRenderer.shared.pdf(of: drawing(), name: name, server: client.baseURL,
                                                                    key: vectorKey),
              let page = Self.document(data)?.page(at: 1),
              let image = await Self.rasterize(page, pixels: pixels) else { return nil }
        if let png = image.pngData() { await renderer.store(png, for: key) }
        return image
    }

    /// Draws a PDF page into a bitmap whose long side is `pixels`.
    private static func rasterize(_ page: CGPDFPage, pixels: Double = BoardPreviewRenderer.targetPixels) async -> UIImage? {
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = pixels / max(box.width, box.height)
        let size = CGSize(width: (box.width * scale).rounded(), height: (box.height * scale).rounded())
        return await Task.detached(priority: .utility) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                let ctx = context.cgContext
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: size.width / box.width, y: -size.height / box.height)
                ctx.translateBy(x: -box.minX, y: -box.minY)
                ctx.drawPDFPage(page)
            }
        }.value
    }
}
