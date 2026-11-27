import XCTest
@testable import PenpotiOS

/// The on-device renderer's SVG must follow Penpot's classic renderer where it matters:
/// transforms around the shape center, per-corner radii, fill stacking, editor-like text
/// with its fonts, imported SVG attributes and flex z-order.
final class PenpotSVGTests: XCTestCase {
    private let server = URL(string: "https://penpot.test")!
    private let root = PenpotSVG.rootID

    /// A page with one board holding `children`, all given as shape dictionaries; `nested`
    /// shapes are on the page but not direct children of the board.
    private func page(_ children: [[String: Any]], nested: [[String: Any]] = [],
                      board: [String: Any] = [:]) throws -> PenpotSVG.Page {
        var objects: [String: Any] = [:]
        var boardShape: [String: Any] = [
            "id": "board", "type": "frame", "name": "Board", "parentId": root,
            "selrect": ["x": 0, "y": 0, "width": 400, "height": 300],
            "fills": [["fillColor": "#ffffff", "fillOpacity": 1]],
            "shapes": children.map { $0["id"] as! String },
        ]
        boardShape.merge(board) { $1 }
        objects[root] = ["id": root, "type": "frame", "parentId": root, "shapes": ["board"]]
        objects["board"] = boardShape
        for child in children + nested { objects[child["id"] as! String] = child }
        let data = try JSONSerialization.data(withJSONObject: ["id": "page", "name": "Page", "objects": objects])
        return try PenpotSVG.Page(pageJSON: data, server: server)
    }

    private func svg(_ children: [[String: Any]], nested: [[String: Any]] = [],
                     board: [String: Any] = [:]) throws -> String {
        try XCTUnwrap(page(children, nested: nested, board: board).drawing(board: "board")).html
    }

    func testBoardDocumentIsExactlyTheBoard() throws {
        let drawing = try XCTUnwrap(page([]).drawing(board: "board"))
        XCTAssertEqual(drawing.origin, .zero)
        XCTAssertEqual(drawing.size, CGSize(width: 400, height: 300))
        XCTAssertTrue(drawing.html.contains("viewBox=\"0 0 400 300\""))
        XCTAssertTrue(drawing.html.contains("fill:#ffffff"), "board background missing")
    }

    // Penpot: M = T(center) · transform · T(-center); a 90° turn of a 100×50 rect at (10,20).
    /// The prototype player draws a board's shapes fixed when scrolling as a layer of their
    /// own: `scroll-<id>` without them, `fixed-<id>` only them, both on the board's rect.
    /// A shape marked fixed inside a group stays in the board, as in Penpot.
    func testFixedScrollLayers() throws {
        let page = try page([
            ["id": "content", "type": "rect", "parentId": "board", "frameId": "board",
             "selrect": ["x": 0, "y": 0, "width": 400, "height": 200],
             "fills": [["fillColor": "#00ff00", "fillOpacity": 1]]],
            ["id": "nav", "type": "rect", "parentId": "board", "frameId": "board", "fixedScroll": true,
             "selrect": ["x": 0, "y": 250, "width": 400, "height": 50],
             "fills": [["fillColor": "#ff0000", "fillOpacity": 1]]],
            ["id": "group", "type": "group", "parentId": "board", "frameId": "board", "shapes": ["grouped"],
             "selrect": ["x": 0, "y": 200, "width": 10, "height": 10]],
        ], nested: [
            ["id": "grouped", "type": "rect", "parentId": "group", "frameId": "board", "fixedScroll": true,
             "selrect": ["x": 0, "y": 200, "width": 10, "height": 10],
             "fills": [["fillColor": "#0000ff", "fillOpacity": 1]]],
        ])
        XCTAssertEqual(page.fixedScrollIDs(board: "board"), ["nav"])
        let scrolling = try XCTUnwrap(page.drawing(board: "scroll-board"))
        XCTAssertEqual(scrolling.size, CGSize(width: 400, height: 300))
        XCTAssertTrue(scrolling.html.contains("#00ff00"))
        XCTAssertTrue(scrolling.html.contains("#0000ff"), "a fixed shape in a group isn't fixed")
        XCTAssertFalse(scrolling.html.contains("#ff0000"))
        let fixed = try XCTUnwrap(page.drawing(board: "fixed-board"))
        XCTAssertEqual(fixed.size, CGSize(width: 400, height: 300))
        XCTAssertTrue(fixed.html.contains("#ff0000"))
        XCTAssertFalse(fixed.html.contains("#00ff00"))
        XCTAssertFalse(fixed.html.contains("fill:#ffffff"), "no board background under the fixed layer")
        // The whole board still has everything.
        XCTAssertTrue(try XCTUnwrap(page.drawing(board: "board")).html.contains("#ff0000"))
    }

    func testTransformIsAppliedAroundTheShapeCenter() throws {
        let html = try svg([[
            "id": "r", "type": "rect", "parentId": "board",
            "selrect": ["x": 10, "y": 20, "width": 100, "height": 50],
            "transform": ["a": 0, "b": 1, "c": -1, "d": 0, "e": 0, "f": 0],
            "fills": [["fillColor": "#ff0000", "fillOpacity": 1]],
        ]])
        // center (60, 45): e = 60 - 0·60 - (-1)·45 = 105, f = 45 - 1·60 - 0·45 = -15
        XCTAssertTrue(html.contains("transform=\"matrix(0,1,-1,0,105,-15)\""), html)
    }

    func testMixedCornerRadiiBecomeAPath() throws {
        let html = try svg([[
            "id": "r", "type": "rect", "parentId": "board",
            "selrect": ["x": 0, "y": 0, "width": 100, "height": 50],
            "r1": 10, "r2": 0, "r3": 0, "r4": 0,
            "fills": [["fillColor": "#000000", "fillOpacity": 1]],
        ]])
        XCTAssertTrue(html.contains("<path d=\"M10,0 h90 a0,0 0 0 1 0,0"), html)
    }

    func testSeveralFillsStackInAPatternWithTheFirstOnTop() throws {
        let html = try svg([[
            "id": "r", "type": "rect", "parentId": "board",
            "selrect": ["x": 0, "y": 0, "width": 100, "height": 50],
            "fills": [["fillColor": "#111111", "fillOpacity": 1], ["fillColor": "#222222", "fillOpacity": 0.5]],
        ]])
        let pattern = try XCTUnwrap(html.range(of: "<pattern"))
        let bottom = try XCTUnwrap(html.range(of: "fill:#222222", range: pattern.upperBound..<html.endIndex))
        let top = try XCTUnwrap(html.range(of: "fill:#111111", range: pattern.upperBound..<html.endIndex))
        XCTAssertLessThan(bottom.lowerBound, top.lowerBound, "fills[0] must be painted last")
        XCTAssertTrue(html.contains("style=\"fill:url(#fill-0-"))
    }

    // Text is laid out from its content (like the editor), with its font loaded.
    func testTextIsHTMLWithItsFontFaces() throws {
        let leaf: [String: Any] = [
            "text": "Hello <world>", "fontId": "sourcesanspro", "fontFamily": "sourcesanspro",
            "fontVariantId": "300", "fontWeight": "300", "fontStyle": "normal", "fontSize": "32",
            "fills": [["fillColor": "#336699", "fillOpacity": 1]],
        ]
        let google: [String: Any] = [
            "text": "Plex", "fontId": "gfont-ibm-plex-sans", "fontFamily": "IBM Plex Sans",
            "fontVariantId": "regular", "fontWeight": "400", "fontSize": "14",
        ]
        let html = try svg([[
            "id": "t", "type": "text", "parentId": "board", "growType": "auto-width",
            "selrect": ["x": 5, "y": 5, "width": 200, "height": 40],
            "content": ["type": "root", "verticalAlign": "center", "children": [[
                "type": "paragraph-set", "children": [[
                    "type": "paragraph", "lineHeight": "1.5", "textAlign": "center",
                    "children": [leaf, google],
                ]],
            ]]],
        ]])
        XCTAssertTrue(html.contains("<foreignObject x=\"5\" y=\"5\" width=\"200\" height=\"40\""))
        XCTAssertTrue(html.contains("Hello &lt;world&gt;"), "text must be escaped")
        XCTAssertTrue(html.contains("align-items:center"))
        XCTAssertTrue(html.contains("line-height:1.5;margin:0;text-align:center"))
        XCTAssertTrue(html.contains("font-size:32px;"))
        XCTAssertTrue(html.contains("color:rgba(51,102,153,1)"))
        XCTAssertTrue(html.contains("white-space:pre;"), "auto-width text must not wrap")
        XCTAssertTrue(html.contains("src:url(https://penpot.test/fonts/sourcesanspro-light.woff)"), html)
        XCTAssertTrue(html.contains("/internal/gfonts/css?family=IBM+Plex+Sans:regular"), html)
    }

    // Imported SVG keeps its attributes in `content.attrs` when there are no `svgAttrs`.
    /// An imported shape's clip path refers to definitions in the imported file's own
    /// coordinates; like Penpot's WebGL renderer, the shape is drawn unclipped. Its other
    /// SVG attributes (here the fill rule) stay.
    func testImportedClipPathsAndMasksAreLeftOut() throws {
        let html = try svg([
            ["id": "ring", "type": "circle", "parentId": "board",
             "selrect": ["x": 100, "y": 100, "width": 100, "height": 100],
             "strokes": [["strokeColor": "#ff1ebd", "strokeOpacity": 1, "strokeWidth": 10]],
             "svgAttrs": ["clipPath": "url('#c')", "mask": "url(#m)", "filter": "url(#f)",
                          "fillRule": "evenodd", "id": "b"],
             "svgDefs": ["c": ["tag": "clipPath", "attrs": ["id": "c"],
                               "content": [["tag": "use", "attrs": ["href": "#b"], "content": []]]]]],
        ])
        XCTAssertFalse(html.contains("clip-path=\"url(&#39;#c&#39;)\""), html)
        XCTAssertFalse(html.contains("mask=\"url(#m)\""), html)
        XCTAssertFalse(html.contains("filter=\"url(#f)\""), html)
        XCTAssertTrue(html.contains("fill-rule=\"evenodd\""), html)
        XCTAssertTrue(html.contains("stroke:#ff1ebd"), html)
    }

    func testImportedSVGUsesItsContentAttributes() throws {
        let html = try svg([
            ["id": "s", "type": "svg-raw", "parentId": "board", "shapes": ["p"],
             "selrect": ["x": 0, "y": 0, "width": 24, "height": 24],
             "content": ["tag": "svg", "attrs": ["viewBox": "0 0 24 24"]]],
        ], nested: [
            ["id": "p", "type": "svg-raw", "parentId": "s",
             "selrect": ["x": 0, "y": 0, "width": 24, "height": 24],
             "fills": [["fillColor": "#00ff00", "fillOpacity": 1]],
             "content": ["tag": "path", "attrs": ["d": "M0 0L24 24", "fillRule": "evenodd"]]],
        ])
        XCTAssertTrue(html.contains("<svg x=\"0\" y=\"0\" width=\"24\" height=\"24\" preserveAspectRatio=\"none\" viewBox=\"0 0 24 24\""), html)
        XCTAssertTrue(html.contains("<path d=\"M0 0L24 24\" fill-rule=\"evenodd\" style=\"fill:#00ff00;fill-opacity:1\">"), html)
    }

    func testFlexBoardPaintsLaterChildrenFirst() throws {
        let child = { (id: String) -> [String: Any] in
            ["id": id, "type": "rect", "parentId": "board",
             "selrect": ["x": 0, "y": 0, "width": 10, "height": 10],
             "fills": [["fillColor": "#00000\(id.last!)", "fillOpacity": 1]]]
        }
        let html = try svg([child("a1"), child("b2")], board: ["layout": "flex"])
        // Same z-index: higher index first, so shapes[0] ends up on top like in Penpot.
        let first = try XCTUnwrap(html.range(of: "fill:#000002"))
        let second = try XCTUnwrap(html.range(of: "fill:#000001"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
    }

    private func shadow(_ style: String) -> [String: Any] {
        ["style": style, "offsetX": 4, "offsetY": 4, "blur": 8, "spread": 0,
         "color": ["color": "#000000", "opacity": 0.5]]
    }

    // `createPDF` rasterizes filtered elements: the shadows come from a copy, the shape
    // itself carries no filter and stays vector.
    func testShadowsAreDrawnFromCopiesOfTheShape() throws {
        let html = try svg([[
            "id": "r", "type": "rect", "parentId": "board",
            "selrect": ["x": 0, "y": 0, "width": 100, "height": 50],
            "fills": [["fillColor": "#ff0000", "fillOpacity": 1]],
            "shadow": [shadow("drop-shadow"), shadow("inner-shadow")],
        ]])
        let drops = try XCTUnwrap(html.range(of: "<g filter=\"url(#filter-drops-"))
        let plain = try XCTUnwrap(html.range(of: "<g class=\"fills\"><rect", range: drops.upperBound..<html.endIndex))
        let inners = try XCTUnwrap(html.range(of: "<g filter=\"url(#filter-inners-"))
        XCTAssertLessThan(plain.lowerBound, inners.lowerBound, "inner shadows go over the shape")
        XCTAssertFalse(html.contains("in=\"SourceGraphic\""), "no filter may draw the shape itself")
    }

    // A shadow without blur on a filled rect is a path, not a filter (Carbon's table
    // rules: hundreds of them per board turned into bitmaps).
    func testHardShadowsArePaths() throws {
        var line = shadow("inner-shadow")
        line["offsetX"] = 1; line["offsetY"] = 0; line["blur"] = 0
        var drop = shadow("drop-shadow")
        drop["blur"] = 0; drop["spread"] = 2
        let html = try svg([[
            "id": "r", "type": "rect", "parentId": "board",
            "selrect": ["x": 0, "y": 0, "width": 100, "height": 50],
            "fills": [["fillColor": "#ffffff", "fillOpacity": 1]],
            "shadow": [line, drop],
        ]])
        XCTAssertFalse(html.contains("<filter"), html)
        // The drop: the outline moved by (4,4) and grown by the spread.
        XCTAssertTrue(html.contains("<path d=\"M2,2 h104"), html)
        // The inner rule: the outline minus itself moved right by 1, cut to the outline.
        XCTAssertTrue(html.contains("<clipPath id=\"inner-shadow-r2-0\"><rect x=\"0\" y=\"0\" width=\"100\" height=\"50\"/></clipPath>"), html)
        XCTAssertTrue(html.contains("fill-rule=\"evenodd\" d=\"M-2,-1 H102 V51 H-2 Z M1,0 h100"), html)
    }

    // A board without a fill counts as its outline when filled children cover it.
    func testUnfilledBoardCoveredByChildrenGetsPathShadows() throws {
        var rule = shadow("inner-shadow")
        rule["offsetX"] = 0; rule["offsetY"] = 1; rule["blur"] = 0
        let cell = { (id: String, x: Double, width: Double) -> [String: Any] in
            ["id": id, "type": "frame", "parentId": "row", "shapes": [],
             "selrect": ["x": x, "y": 0, "width": width, "height": 40],
             "fills": [["fillColor": "#eeeeee", "fillOpacity": 1]]]
        }
        let row = { (cells: [String]) -> [String: Any] in
            ["id": "row", "type": "frame", "parentId": "board", "shapes": cells, "showContent": true,
             "selrect": ["x": 0, "y": 0, "width": 200, "height": 40], "shadow": [rule]]
        }
        let covered = try svg([row(["a", "b"])], nested: [cell("a", 0, 120), cell("b", 120, 80)])
        XCTAssertFalse(covered.contains("<filter"), covered)
        let gap = try svg([row(["a", "b"])], nested: [cell("a", 0, 100), cell("b", 120, 80)])
        XCTAssertTrue(gap.contains("filter-inners-"), "a gap lets the content's own alpha through")
    }

    func testLayerBlurKeepsOneFilter() throws {
        let html = try svg([[
            "id": "r", "type": "rect", "parentId": "board",
            "selrect": ["x": 0, "y": 0, "width": 100, "height": 50],
            "fills": [["fillColor": "#ff0000", "fillOpacity": 1]],
            "shadow": [shadow("drop-shadow")], "blur": ["type": "layer-blur", "value": 4],
        ]])
        XCTAssertTrue(html.contains("<g class=\"fills\" filter=\"url(#filter-r"), html)
        XCTAssertTrue(html.contains("<feGaussianBlur stdDeviation=\"4\" result=\"blur\"/>"))
    }

    // A card's outline casts its shadow; its text is laid out once and stays vector.
    func testOpaqueBoardCastsItsShadowFromItsOutline() throws {
        let html = try svg([[
            "id": "card", "type": "frame", "parentId": "board", "shapes": ["label"],
            "selrect": ["x": 10, "y": 10, "width": 200, "height": 100],
            "fills": [["fillColor": "#ffffff", "fillOpacity": 1]],
            "shadow": [shadow("drop-shadow")],
        ]], nested: [[
            "id": "label", "type": "text", "parentId": "card",
            "selrect": ["x": 20, "y": 20, "width": 100, "height": 20],
            "content": ["type": "root", "children": [["type": "paragraph-set", "children": [[
                "type": "paragraph", "children": [["text": "Title", "fontSize": "14"]],
            ]]]]],
        ]])
        XCTAssertTrue(html.contains("<g filter=\"url(#filter-drops-r2)\"><rect x=\"10\" y=\"10\" width=\"200\" height=\"100\" style=\"fill:#000000\"/></g>"), html)
        XCTAssertEqual(html.components(separatedBy: ">Title<").count, 2, "the text must not be copied")
    }

    // The document ends at the board's edges, so its own drop shadow can't show.
    func testDocumentBoardLeavesOutItsDropShadow() throws {
        let html = try svg([], board: ["shadow": [shadow("drop-shadow")]])
        XCTAssertFalse(html.contains("filter-drops"), html)
    }

    // A plain opaque mask is a clip path (vector); anything else stays a `<mask>`.
    func testPlainMasksBecomeClipPaths() throws {
        let group: [String: Any] = [
            "id": "g", "type": "group", "parentId": "board", "maskedGroup": true, "shapes": ["m", "c"],
            "selrect": ["x": 0, "y": 0, "width": 50, "height": 50],
        ]
        var mask: [String: Any] = [
            "id": "m", "type": "circle", "parentId": "g",
            "selrect": ["x": 0, "y": 0, "width": 50, "height": 50],
            "fills": [["fillColor": "#000000", "fillOpacity": 1]],
        ]
        let content: [String: Any] = [
            "id": "c", "type": "rect", "parentId": "g",
            "selrect": ["x": 0, "y": 0, "width": 80, "height": 80],
            "fills": [["fillColor": "#123456", "fillOpacity": 1]],
        ]
        let clipped = try svg([group], nested: [mask, content])
        XCTAssertTrue(clipped.contains("<clipPath id=\"r2-mask\"><ellipse cx=\"25\" cy=\"25\" rx=\"25\" ry=\"25\"/></clipPath>"), clipped)
        XCTAssertFalse(clipped.contains("<mask"))

        mask["fills"] = [["fillColor": "#000000", "fillOpacity": 0.5]]
        let masked = try svg([group], nested: [mask, content])
        XCTAssertTrue(masked.contains("<mask id=\"r2-mask\""), masked)
    }

    // WebKit draws no `backdrop-filter` into a PDF: the glass is a blurred copy of what
    // lies under the shape, cut to its outline and drawn before it.
    func testBackgroundBlurBlursACopyOfWhatLiesUnderTheShape() throws {
        let html = try svg([
            ["id": "under", "type": "rect", "parentId": "board",
             "selrect": ["x": 0, "y": 0, "width": 100, "height": 100],
             "fills": [["fillColor": "#ff0000", "fillOpacity": 1]]],
            ["id": "glass", "type": "rect", "parentId": "board",
             "selrect": ["x": 20, "y": 20, "width": 60, "height": 60],
             "fills": [["fillColor": "#00ff00", "fillOpacity": 0.3]],
             "backgroundBlur": ["type": "background-blur", "value": 10]],
        ])
        let glass = try XCTUnwrap(html.range(of: "<g class=\"background-blur\">"))
        let shape = try XCTUnwrap(html.range(of: "<g id=\"shape-glass\""))
        XCTAssertLessThan(glass.lowerBound, shape.lowerBound)
        XCTAssertTrue(html.contains("<clipPath id=\"background-blur-clip-r3\"><rect x=\"20\" y=\"20\" width=\"60\" height=\"60\"/></clipPath>"), html)
        XCTAssertTrue(html.contains("<feGaussianBlur stdDeviation=\"6.27"), "Skia's radius → sigma")
        let blurred = html[glass.upperBound..<shape.lowerBound]
        XCTAssertTrue(blurred.contains("fill:#ff0000"), "the shape under the glass")
        XCTAssertTrue(blurred.contains("fill:#ffffff"), "the board's own fill")
        XCTAssertFalse(blurred.contains("fill:#00ff00"), "not the glass itself")
    }

    // MARK: Layout

    /// A text shape; `measured` gives it the `positionData` Penpot's editor writes.
    private func text(_ id: String, x: Double, width: Double, parent: String = "row",
                      measured: Bool = false) -> [String: Any] {
        var shape: [String: Any] = [
            "id": id, "type": "text", "parentId": parent, "growType": "auto-width",
            "selrect": ["x": x, "y": 0, "width": width, "height": 20],
            "content": ["type": "root", "children": [["type": "paragraph-set", "children": [[
                "type": "paragraph", "children": [["text": "Label \(id)", "fontSize": "14"]],
            ]]]]],
        ]
        if measured { shape["positionData"] = [["x": x, "y": 0, "width": width, "height": 20, "text": "Label"]] }
        return shape
    }

    private func flexRow(_ shapes: [String]) -> [String: Any] {
        ["id": "row", "type": "frame", "parentId": "board", "shapes": shapes,
         "selrect": ["x": 0, "y": 0, "width": 100, "height": 20],
         "layout": "flex", "layoutFlexDir": "row", "layoutGap": ["rowGap": 0, "columnGap": 16],
         "layoutPadding": ["p1": 8, "p2": 4, "p3": 8, "p4": 4], "layoutAlignItems": "center",
         "layoutJustifyContent": "start", "layoutItemHSizing": "auto", "layoutItemVSizing": "auto"]
    }

    // Texts the editor measured are trusted; one it never laid out makes the board stale.
    func testOnlyBoardsWithUnmeasuredTextsNeedLayout() throws {
        let measured = try page([flexRow(["a"])], nested: [text("a", x: 0, width: 50, measured: true)])
        XCTAssertFalse(measured.needsLayout(board: "board"))
        let stale = try page([flexRow(["a"])], nested: [text("a", x: 0, width: 50)])
        XCTAssertTrue(stale.needsLayout(board: "board"))
    }

    // Penpot's flex layout as CSS flexbox, its children in reverse `shapes` order; what
    // nothing stale touches keeps its stored geometry.
    func testLayoutProbeMirrorsPenpotFlex() throws {
        let icon: [String: Any] = [
            "id": "icon", "type": "frame", "parentId": "row", "shapes": [],
            "selrect": ["x": 80, "y": 0, "width": 24, "height": 24], "layout": "flex",
            "layoutItemHSizing": "auto", "layoutItemVSizing": "auto",
        ]
        let html = try XCTUnwrap(page([flexRow(["icon", "b", "a"])],
                                      nested: [text("a", x: 0, width: 10), text("b", x: 26, width: 10), icon])
            .layoutProbe(board: "board"))
        XCTAssertTrue(html.contains("display:flex;flex-direction:row;flex-wrap:nowrap;row-gap:0px;column-gap:16px;padding:8px 4px 8px 4px;justify-content:flex-start;align-items:center;"), html)
        let a = try XCTUnwrap(html.range(of: "data-id=\"a\""))
        let b = try XCTUnwrap(html.range(of: "data-id=\"b\""))
        XCTAssertLessThan(a.lowerBound, b.lowerBound, "the last shape comes first in the layout")
        XCTAssertTrue(html.contains("data-id=\"a\" style=\"position:relative;flex-shrink:0;width:max-content;"), html)
        XCTAssertTrue(html.contains("data-id=\"icon\" style=\"position:relative;flex-shrink:0;width:24px;height:24px;\""),
                      "a hug board with nothing stale in it keeps its size")
    }

    // Measured shapes are drawn where the layout put them: moved as a whole, a text at its
    // measured size.
    func testMeasuredLayoutMovesAndResizesShapes() throws {
        let page = try page([flexRow(["b", "a"])], nested: [text("a", x: 4, width: 10), text("b", x: 30, width: 10)])
        let html = try XCTUnwrap(page.drawing(board: "board", layout: [
            "row": CGRect(x: 0, y: 0, width: 180, height: 36),
            "a": CGRect(x: 4, y: 8, width: 60, height: 20),
            "b": CGRect(x: 80, y: 8, width: 70, height: 20),
        ])).html
        XCTAssertTrue(html.contains("<foreignObject x=\"4\" y=\"0\" width=\"60\" height=\"20\""), html)
        XCTAssertTrue(html.contains("<g transform=\"translate(50,8)\"><g id=\"shape-b\""), html)
        XCTAssertTrue(html.contains("<rect x=\"0\" y=\"0\" width=\"180\" height=\"36\""), "the hug board grows")
    }

    // MARK: Islands

    /// A page whose root holds `shapes` in this paint order (bottom first).
    private func canvas(_ shapes: [[String: Any]]) throws -> PenpotSVG.Page {
        var objects: [String: Any] = [root: ["id": root, "type": "frame", "parentId": root,
                                             "shapes": shapes.map { $0["id"] as! String }]]
        for shape in shapes { objects[shape["id"] as! String] = shape }
        let data = try JSONSerialization.data(withJSONObject: ["id": "page", "objects": objects])
        return try PenpotSVG.Page(pageJSON: data, server: server)
    }

    private func rect(_ id: String, x: Double, y: Double = 0, type: String = "rect") -> [String: Any] {
        ["id": id, "type": type, "parentId": root,
         "selrect": ["x": x, "y": y, "width": 40, "height": 40],
         "fills": [["fillColor": "#123456", "fillOpacity": 1]]]
    }

    // Loose shapes close together share an island; one far away gets its own.
    func testLooseShapesFormIslandsByDistance() throws {
        let page = try canvas([rect("a", x: 0), rect("b", x: 60), rect("far", x: 1000),
                               rect("board", x: 2000, type: "frame")])
        XCTAssertEqual(page.islands.map(\.shapeIDs), [["a", "b"], ["far"]])
        let near = page.islands[0]
        XCTAssertEqual(near.id, PenpotSVG.islandPrefix + "a")
        XCTAssertEqual(near.layer, 1, "drawn where its topmost shape is")
        XCTAssertEqual(near.bounds, CGRect(x: -1, y: -1, width: 102, height: 42), "antialiasing room")
        XCTAssertEqual(page.layers["board"], 3)
    }

    // One shape under a board and one over it can't be drawn as one island.
    func testABoardBetweenShapesInPaintOrderSplitsTheirIsland() throws {
        var board = rect("board", x: 20, type: "frame")
        board["selrect"] = ["x": 20, "y": 0, "width": 100, "height": 40]
        let page = try canvas([rect("under", x: 0), board, rect("over", x: 80)])
        XCTAssertEqual(page.islands.map(\.shapeIDs), [["under"], ["over"]])
        XCTAssertEqual(page.islands.map(\.layer), [0, 2])
    }

    func testAnIslandIsDrawnLikeABoardOfItsShapes() throws {
        let page = try canvas([rect("a", x: 0), rect("b", x: 60)])
        let island = try XCTUnwrap(page.islands.first)
        let drawing = try XCTUnwrap(page.drawing(board: island.id))
        XCTAssertEqual(drawing.origin, island.bounds.origin)
        XCTAssertTrue(drawing.html.contains("viewBox=\"-1 -1 102 42\""), drawing.html)
        XCTAssertTrue(drawing.html.contains("<g id=\"shape-a\"") && drawing.html.contains("<g id=\"shape-b\""))
        XCTAssertFalse(page.needsLayout(board: island.id))
    }

    func testHiddenShapesAreLeftOut() throws {
        let html = try svg([[
            "id": "r", "type": "rect", "parentId": "board", "hidden": true,
            "selrect": ["x": 0, "y": 0, "width": 10, "height": 10],
            "fills": [["fillColor": "#abcdef", "fillOpacity": 1]],
        ]])
        XCTAssertFalse(html.contains("#abcdef"))
    }
}
