import WebKit
import XCTest
@testable import PenpotiOS

/// Probe for the on-device renderer's core assumption: an offscreen WKWebView turns an
/// SVG (with HTML text in a foreignObject) into a vector PDF of any rect of the document,
/// also far outside its own frame.
@MainActor
final class SVGToPDFProbeTests: XCTestCase {
    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume(); continuation = nil
        }
    }

    private func load(_ html: String, in webView: WKWebView) async {
        let waiter = LoadWaiter()
        webView.navigationDelegate = waiter
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    // The layout pass in a real WebKit: two texts whose stored widths are far too small
    // end up side by side, the gap between them, the row around them grown to fit.
    func testLayoutProbeReflowsAFlexRow() async throws {
        let root = PenpotSVG.rootID
        func text(_ id: String, x: Double) -> [String: Any] {
            ["id": id, "type": "text", "parentId": "row", "growType": "auto-width",
             "selrect": ["x": x, "y": 10, "width": 10, "height": 20],
             "content": ["type": "root", "children": [["type": "paragraph-set", "children": [[
                "type": "paragraph", "children": [["text": "A rather long headline", "fontFamily": "Helvetica",
                                                   "fontSize": "24"]],
             ]]]]]]
        }
        let objects: [String: Any] = [
            root: ["id": root, "type": "frame", "parentId": root, "shapes": ["board"]],
            "board": ["id": "board", "type": "frame", "parentId": root, "shapes": ["row"],
                      "selrect": ["x": 100, "y": 50, "width": 800, "height": 200]],
            "row": ["id": "row", "type": "frame", "parentId": "board", "shapes": ["b", "a"],
                    "selrect": ["x": 110, "y": 60, "width": 36, "height": 20],
                    "layout": "flex", "layoutFlexDir": "row", "layoutGap": ["rowGap": 0, "columnGap": 16],
                    "layoutItemHSizing": "auto", "layoutItemVSizing": "auto"],
            "a": text("a", x: 110), "b": text("b", x: 126),
        ]
        let data = try JSONSerialization.data(withJSONObject: ["id": "page", "objects": objects])
        let page = try PenpotSVG.Page(pageJSON: data, server: URL(string: "https://penpot.test")!)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        await load(try XCTUnwrap(page.layoutProbe(board: "board")), in: webView)
        let result = try await webView.evaluateJavaScript(PenpotSVG.layoutScript)
        let json = try XCTUnwrap(result as? String)
        let layout = page.layout(measured: json, board: "board")

        let a = try XCTUnwrap(layout["a"]), b = try XCTUnwrap(layout["b"]), row = try XCTUnwrap(layout["row"])
        XCTAssertEqual(a.minX, 110, accuracy: 0.5, "the row stays where it is, in canvas coordinates")
        XCTAssertGreaterThan(a.width, 100, "measured, not the stored 10")
        XCTAssertEqual(b.minX, a.maxX + 16, accuracy: 0.5)
        XCTAssertEqual(row.width, a.width + 16 + b.width, accuracy: 0.5)
    }

    func testOffscreenWebViewRendersARectOfALargeSVGAsVectorPDF() async throws {
        let html = """
            <!doctype html><html><head><meta charset="utf-8">
            <style>html,body{margin:0;padding:0}</style></head><body>
            <svg xmlns="http://www.w3.org/2000/svg" width="6000" height="4000" viewBox="1000 500 6000 4000">
              <rect x="5000" y="3000" width="400" height="200" fill="#e00"/>
              <foreignObject x="5000" y="3000" width="400" height="200">
                <div xmlns="http://www.w3.org/1999/xhtml" style="font: 32px Helvetica; color: #fff">Board text</div>
              </foreignObject>
            </svg></body></html>
            """
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let waiter = LoadWaiter()
        webView.navigationDelegate = waiter
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        let configuration = WKPDFConfiguration()
        // Document coordinates: the viewBox starts at (1000, 500).
        configuration.rect = CGRect(x: 4000, y: 2500, width: 400, height: 200)
        let data = try await webView.pdf(configuration: configuration)

        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(document.numberOfPages, 1)
        let box = try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 400, accuracy: 1)
        XCTAssertEqual(box.height, 200, accuracy: 1)
        // Real text, not pixels: the PDF carries a font.
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(raw.contains("/Font"), "PDF has no font, the text was rasterized")
        // And it isn't an empty page: draw it and look for the red.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            let ctx = context.cgContext
            ctx.translateBy(x: 0, y: 20); ctx.scaleBy(x: 0.1, y: -0.1)
            ctx.drawPDFPage(document.page(at: 1)!)
        }
        let pixel = image.cgImage!.dataProvider!.data! as Data
        XCTAssertGreaterThan(pixel[0...3].first ?? 0, 0, "the rect rendered blank")
    }
}
