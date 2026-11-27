import SwiftUI
import UIKit

/// A board's vector PDF (``BoardPreviewRenderer``, kind `.vector`), drawn through a
/// `CATiledLayer`. As the board detail zooms in (`scaleEffect`, up to 6×), Core Animation
/// asks for tiles at a finer level of detail, so text and shapes stay sharp where a bitmap
/// thumbnail blurs. Photos in the design stay the bitmaps they are.
struct BoardVectorView: UIViewRepresentable {
    let document: CGPDFDocument

    func makeUIView(context: Context) -> PageView {
        let view = PageView()
        view.pageLayer.page = document.page(at: 1)
        return view
    }

    /// A new render of the board (it changed live, ``LiveFile``) replaces the page.
    func updateUIView(_ view: PageView, context: Context) {
        guard let page = document.page(at: 1), view.pageLayer.page !== page else { return }
        view.pageLayer.page = page
        view.pageLayer.setNeedsDisplay()
    }

    final class PageView: UIView {
        override class var layerClass: AnyClass { PageLayer.self }
        var pageLayer: PageLayer { layer as! PageLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            isUserInteractionEnabled = false   // the detail's gestures and pins sit above
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }

    /// Draws its own tiles, on Core Animation's background threads; `page` is set before
    /// the first draw, and again when the board is drawn anew.
    final class PageLayer: CATiledLayer {
        var page: CGPDFPage?

        override class func fadeDuration() -> CFTimeInterval { 0.1 }

        override init() {
            super.init()
            levelsOfDetail = 1
            levelsOfDetailBias = 3   // up to 8×, past the detail's 6× zoom
            tileSize = CGSize(width: 512, height: 512)
            needsDisplayOnBoundsChange = true
        }

        override init(layer: Any) {
            super.init(layer: layer)
            page = (layer as? PageLayer)?.page
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func draw(in ctx: CGContext) {
            guard let page else { return }
            let box = page.getBoxRect(.mediaBox)
            guard box.width > 0, box.height > 0, bounds.width > 0, bounds.height > 0 else { return }
            // PDF space is bottom-up; the layer's is top-down. The page fills the bounds,
            // whose aspect is the board's, as the exporter's page is.
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: bounds.width / box.width, y: -bounds.height / box.height)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
        }
    }
}
