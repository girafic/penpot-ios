import CoreGraphics
import XCTest
@testable import PenpotiOS

/// The inspect values and CSS must be what Penpot's own `app.util.code-gen.style-css*`
/// writes for the same shapes: its units, its colors (`#ff0000FF`), its numbers (JavaScript's)
/// and which properties a shape gets at all.
final class InspectCSSTests: XCTestCase {
    private let root = InspectCSS.rootID
    private let identity: [String: Any] = ["a": 1, "b": 0, "c": 0, "d": 1, "e": 0, "f": 0]

    private func box(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [String: Any] {
        ["x": x, "y": y, "width": width, "height": height]
    }

    private func corners(_ x: Double, _ y: Double, _ width: Double, _ height: Double,
                         turnedBy degrees: Double = 0) -> [[String: Any]] {
        let cx = x + width / 2, cy = y + height / 2
        let angle = degrees * .pi / 180
        return [(x, y), (x + width, y), (x + width, y + height), (x, y + height)].map { px, py in
            let dx = px - cx, dy = py - cy
            return ["x": cx + dx * cos(angle) - dy * sin(angle), "y": cy + dx * sin(angle) + dy * cos(angle)]
        }
    }

    /// A shape with the geometry Penpot stores: selrect, points and transform.
    private func shape(_ id: String, _ type: String, name: String, parent: String = "board",
                       _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                       _ extra: [String: Any] = [:]) -> [String: Any] {
        var shape: [String: Any] = [
            "id": id, "type": type, "name": name, "parentId": parent, "frameId": "board",
            "selrect": box(x, y, width, height), "points": corners(x, y, width, height),
            "transform": identity, "transformInverse": identity,
        ]
        shape.merge(extra) { $1 }
        return shape
    }

    /// The page root and a 400×300 root board at (0, 0) holding `shapes` (by their parent ids).
    private func objects(_ shapes: [[String: Any]], board: [String: Any] = [:]) -> [String: InspectCSS.Object] {
        var objects: [String: InspectCSS.Object] = [:]
        for shape in shapes { objects[shape["id"] as! String] = shape }
        func children(of id: String) -> [String] {
            shapes.filter { $0["parentId"] as? String == id }.map { $0["id"] as! String }
        }
        var boardShape = shape("board", "frame", name: "Board", parent: root, 0, 0, 400, 300,
                               ["frameId": root, "fills": [["fillColor": "#ffffff", "fillOpacity": 1]]])
        boardShape.merge(board) { $1 }
        boardShape["shapes"] = children(of: "board")
        objects["board"] = boardShape
        objects[root] = ["id": root, "type": "frame", "parentId": root, "frameId": root,
                         "selrect": box(0, 0, 0.01, 0.01), "shapes": ["board"]]
        for (id, var object) in objects where id != root && id != "board" {
            let kids = children(of: id)
            if !kids.isEmpty { object["shapes"] = kids; objects[id] = object }
        }
        return objects
    }

    private let rectID = "11111111-1111-4111-8111-0123456789ab"

    private var plainRect: [String: Any] {
        shape(rectID, "rect", name: "Rectangle", 20, 30, 100, 50,
              ["r1": 8, "r2": 8, "r3": 8, "r4": 8, "fills": [["fillColor": "#ff0000", "fillOpacity": 1]]])
    }

    // MARK: - Geometry, background, the rule

    func testPlainRect() {
        let rect = plainRect, objects = objects([rect])
        func value(_ property: String, format: InspectCSS.ColorFormat = .hex) -> String? {
            InspectCSS.value(property, shape: rect, objects: objects, format: format)
        }
        XCTAssertEqual(value("width"), "100px")
        XCTAssertEqual(value("height"), "50px")
        XCTAssertEqual(value("left"), "20px")
        XCTAssertEqual(value("top"), "30px")
        XCTAssertEqual(value("position"), "absolute")
        XCTAssertEqual(value("border-radius"), "8px 8px 8px 8px")
        XCTAssertNil(value("transform"), "an unrotated shape has no transform")
        // The stored color and the opacity in hex, upper-cased: Penpot's `color->format->background`.
        XCTAssertEqual(value("background"), "#ff0000FF")
        XCTAssertEqual(value("background", format: .rgba), "rgba(255, 0, 0, 1)")
        XCTAssertEqual(value("background", format: .hsla), "hsla(0, 100%, 50%, 1)")
        XCTAssertNil(value("box-shadow"))
        XCTAssertNil(value("z-index"))

        XCTAssertEqual(InspectCSS.declaration("left", shape: rect, objects: objects), "left: 20px;")
        XCTAssertEqual(InspectCSS.declarations(InspectCSS.geometryProperties, shape: rect, objects: objects),
                       "  width: 100px;\n  height: 50px;\n  left: 20px;\n  top: 30px;\n  border-radius: 8px 8px 8px 8px;")

        XCTAssertEqual(InspectCSS.stylesheet([rectID], objects: objects, prelude: false), """
            /* Rectangle */
            .rectangle-0123456789ab {
              position: absolute;
              left: 20px;
              top: 30px;
              width: 100px;
              height: 50px;
              background: #ff0000FF;
              border-start-start-radius: 8px;
              border-start-end-radius: 8px;
              border-end-start-radius: 8px;
              border-end-end-radius: 8px;
            }
            """)
        XCTAssertTrue(InspectCSS.stylesheet([rectID], objects: objects).hasPrefix(InspectCSS.prelude))
    }

    func testRootBoard() throws {
        let objects = objects([plainRect])
        let board = try XCTUnwrap(objects["board"])
        XCTAssertEqual(InspectCSS.value("position", shape: board, objects: objects), "relative")
        XCTAssertEqual(InspectCSS.value("z-index", shape: board, objects: objects), "0")
        XCTAssertNil(InspectCSS.value("left", shape: board, objects: objects), "a root board has no position")
        XCTAssertEqual(InspectCSS.value("overflow", shape: board, objects: objects), "hidden")
        XCTAssertEqual(InspectCSS.value("width", shape: board, objects: objects), "400px")
        // The board's rule comes before its children's.
        let css = InspectCSS.stylesheet(["board"], objects: objects, prelude: false)
        let boardRule = try XCTUnwrap(css.range(of: "/* Board */"))
        let rectRule = try XCTUnwrap(css.range(of: "/* Rectangle */"))
        XCTAssertLessThan(boardRule.lowerBound, rectRule.lowerBound)
    }

    func testRotatedRect() {
        let angle = 45 * Double.pi / 180
        let turn: [String: Any] = ["a": cos(angle), "b": sin(angle), "c": -sin(angle), "d": cos(angle), "e": 0, "f": 0]
        let inverse: [String: Any] = ["a": cos(angle), "b": -sin(angle), "c": sin(angle), "d": cos(angle), "e": 0, "f": 0]
        let rect = shape(rectID, "rect", name: "Rotated", 20, 30, 100, 50,
                         ["points": corners(20, 30, 100, 50, turnedBy: 45), "transform": turn,
                          "transformInverse": inverse, "fills": [["fillColor": "#ff0000", "fillOpacity": 1]]])
        let objects = objects([rect])
        XCTAssertEqual(InspectCSS.value("transform", shape: rect, objects: objects),
                       "matrix(0.71, 0.71, -0.71, 0.71, 0.00, 0.00)")
        // The unrotated box: a turn doesn't move left/top or change the size.
        XCTAssertEqual(InspectCSS.value("left", shape: rect, objects: objects), "20px")
        XCTAssertEqual(InspectCSS.value("top", shape: rect, objects: objects), "30px")
        XCTAssertEqual(InspectCSS.value("width", shape: rect, objects: objects), "100px")
    }

    /// A rotated child of a layout gets a wrapper of its bounding box, the turn stays inside.
    func testRotatedLayoutChildIsWrapped() {
        let angle = 45 * Double.pi / 180
        let turn: [String: Any] = ["a": cos(angle), "b": sin(angle), "c": -sin(angle), "d": cos(angle), "e": 0, "f": 0]
        let flex = shape("22222222-2222-4222-8222-000000000001", "frame", name: "Row", 0, 0, 400, 200,
                         ["layout": "flex", "layoutFlexDir": "row"])
        let rect = shape(rectID, "rect", name: "Rotated", parent: flex["id"] as! String, 20, 30, 100, 50,
                         ["points": corners(20, 30, 100, 50, turnedBy: 45), "transform": turn,
                          "layoutItemHSizing": "fix", "layoutItemVSizing": "fix"])
        let objects = objects([flex, rect])
        XCTAssertEqual(InspectCSS.value("transform", shape: rect, objects: objects),
                       "translate(-50%, -50%) matrix(0.71, 0.71, -0.71, 0.71, 0.00, 0.00)")
        let css = InspectCSS.stylesheet([rectID], objects: objects, prelude: false)
        XCTAssertTrue(css.contains("""
            .rotated-0123456789ab-wrapper {
              flex-shrink: 0;
              width: 106.07px;
              height: 106.07px;
              position: relative;
            }
            .rotated-0123456789ab-wrapper > * {
              position: absolute;
              left: 50%;
              top: 50%;
            }
            """), css)
    }

    // MARK: - Strokes, shadows, blur

    func testInnerStrokeIsABorder() {
        let stroke: [String: Any] = ["strokeStyle": "solid", "strokeAlignment": "inner", "strokeWidth": 2,
                                     "strokeColor": "#000000", "strokeOpacity": 0.5]
        let rect = shape(rectID, "rect", name: "Outlined", 20, 30, 100, 50, ["strokes": [stroke]])
        // The parent's own border is discounted from left/top, as CSS places inside it.
        let objects = objects([rect], board: ["strokes": [["strokeStyle": "solid", "strokeAlignment": "inner",
                                                           "strokeWidth": 4, "strokeColor": "#cccccc",
                                                           "strokeOpacity": 1]]])
        XCTAssertEqual(InspectCSS.value("border", shape: rect, objects: objects), "2px solid #00000080")
        XCTAssertEqual(InspectCSS.value("left", shape: rect, objects: objects), "16px")
        XCTAssertEqual(InspectCSS.value("top", shape: rect, objects: objects), "26px")
        // The stroke panel's rows ask the stroke itself.
        XCTAssertEqual(InspectCSS.strokeProperties(stroke), ["border-style", "border-width"])
        XCTAssertEqual(InspectCSS.value("border-style", shape: stroke, objects: objects), "solid")
        XCTAssertEqual(InspectCSS.value("border-width", shape: stroke, objects: objects), "2px")
        XCTAssertEqual(InspectCSS.value("border-color", shape: stroke, objects: objects), "#00000080")

        var sides = stroke
        sides["strokeWidthTop"] = 1
        XCTAssertEqual(InspectCSS.strokeProperties(sides).count, 5)
        XCTAssertEqual(InspectCSS.value("border-block-start-width", shape: sides, objects: objects), "1px")
        XCTAssertEqual(InspectCSS.value("border-inline-end-width", shape: sides, objects: objects), "2px")
    }

    /// A center stroke makes Penpot's code draw the shape as SVG: no border, no background.
    func testCenterStrokeIsSVG() {
        let rect = shape(rectID, "rect", name: "Outlined", 20, 30, 100, 50,
                         ["fills": [["fillColor": "#ff0000", "fillOpacity": 1]],
                          "strokes": [["strokeStyle": "solid", "strokeAlignment": "center", "strokeWidth": 2,
                                       "strokeColor": "#000000", "strokeOpacity": 1]]])
        let objects = objects([rect])
        XCTAssertNil(InspectCSS.value("border", shape: rect, objects: objects))
        XCTAssertNil(InspectCSS.value("background", shape: rect, objects: objects))
        XCTAssertTrue(InspectCSS.stylesheet([rectID], objects: objects, prelude: false).contains("""
            .outlined-0123456789ab > svg {
              position: absolute;
              top: 0px;
              left: 0px;
              transform: translate(0px,0px);
            }
            """))
    }

    func testShadowsAndBlur() {
        let rect = shape(rectID, "rect", name: "Card", 20, 30, 100, 50, [
            "shadow": [
                ["style": "drop-shadow", "offsetX": 0, "offsetY": 4, "blur": 8, "spread": 0, "hidden": false,
                 "color": ["color": "#000000", "opacity": 0.2]],
                // Penpot writes hidden shadows too.
                ["style": "inner-shadow", "offsetX": 1, "offsetY": 2, "blur": 3, "spread": 1, "hidden": true,
                 "color": ["color": "#ffffff", "opacity": 1]],
            ],
            "blur": ["type": "layer-blur", "value": 5, "hidden": false],
        ])
        let objects = objects([rect])
        XCTAssertEqual(InspectCSS.value("box-shadow", shape: rect, objects: objects),
                       "0px 4px 8px 0px #00000033, inset 1px 2px 3px 1px #ffffffFF")
        XCTAssertEqual(InspectCSS.value("filter", shape: rect, objects: objects), "blur(5px)")
        XCTAssertEqual(InspectCSS.declarations(["box-shadow", "filter"], shape: rect, objects: objects),
                       "  box-shadow: 0px 4px 8px 0px #00000033, inset 1px 2px 3px 1px #ffffffFF;\n  filter: blur(5px);")
    }

    // MARK: - Layout

    private let flexID = "33333333-3333-4333-8333-000000000001"

    private var flexBoard: [String: Any] {
        shape(flexID, "frame", name: "Toolbar", 10, 10, 300, 80, [
            "layout": "flex", "layoutFlexDir": "row", "layoutGap": ["rowGap": 8, "columnGap": 8],
            "layoutPadding": ["p1": 16, "p2": 24, "p3": 16, "p4": 24], "layoutAlignItems": "center",
            "layoutJustifyContent": "space-between", "layoutWrapType": "nowrap",
            "layoutItemHSizing": "fix", "layoutItemVSizing": "auto",
            "fills": [["fillColor": "#eeeeee", "fillOpacity": 1]],
        ])
    }

    func testFlexBoard() {
        let flex = flexBoard, objects = objects([flex])
        func value(_ property: String) -> String? { InspectCSS.value(property, shape: flex, objects: objects) }
        XCTAssertEqual(value("display"), "flex")
        XCTAssertEqual(value("flex-direction"), "row")
        XCTAssertEqual(value("gap"), "8px", "equal gaps are one gap")
        XCTAssertNil(value("row-gap"))
        XCTAssertNil(value("column-gap"))
        XCTAssertEqual(value("padding"), "16px 24px 16px 24px")
        XCTAssertEqual(value("padding-block-start"), "16px")
        XCTAssertEqual(value("padding-inline-end"), "24px")
        XCTAssertEqual(value("width"), "300px")
        XCTAssertEqual(value("height"), "auto", "a hugging layout")
        XCTAssertEqual(value("min-height"), "80px")
        XCTAssertEqual(value("left"), "10px")
        XCTAssertEqual(value("overflow"), "hidden")
        XCTAssertEqual(InspectCSS.declarations(InspectCSS.layoutProperties, shape: flex, objects: objects), """
              display: flex;
              flex-direction: row;
              flex-wrap: nowrap;
              align-items: center;
              justify-content: space-between;
              gap: 8px;
              padding-inline-start: 24px;
              padding-inline-end: 24px;
              padding-block-start: 16px;
              padding-block-end: 16px;
            """)
        // The Code tab's root layout fills the page.
        let css = InspectCSS.stylesheet([flexID], objects: objects, prelude: false)
        XCTAssertTrue(css.contains("  width: 100%;\n"), css)
        XCTAssertTrue(css.contains("  flex-grow: 1;\n"), css)
        XCTAssertFalse(css.contains("  height:"), css)
    }

    func testFlexChild() {
        let item = shape(rectID, "rect", name: "Item", parent: flexID, 34, 26, 100, 40, [
            "layoutItemHSizing": "fill", "layoutItemVSizing": "fix",
            "layoutItemMargin": ["m1": 0, "m2": 4, "m3": 0, "m4": 4],
        ])
        let objects = objects([flexBoard, item])
        func value(_ property: String) -> String? { InspectCSS.value(property, shape: item, objects: objects) }
        XCTAssertNil(value("left"), "the layout places it")
        XCTAssertNil(value("top"))
        XCTAssertNil(value("position"))
        XCTAssertNil(value("width"), "it fills along the row: flex: 1")
        XCTAssertEqual(value("height"), "40px")
        XCTAssertEqual(value("flex"), "1")
        XCTAssertEqual(value("flex-shrink"), "0")
        XCTAssertEqual(value("margin"), "0px 4px 0px 4px")
        XCTAssertEqual(value("margin-inline-end"), "4px")
        XCTAssertNil(value("margin-block-start"))

        // Filling across a column is 100 %.
        let column = shape("44444444-4444-4444-8444-000000000001", "frame", name: "Column", 0, 100, 200, 200,
                           ["layout": "flex", "layoutFlexDir": "column"])
        let wide = shape("55555555-5555-4555-8555-000000000001", "rect", name: "Wide", parent: column["id"] as! String,
                         0, 100, 200, 40, ["layoutItemHSizing": "fill", "layoutItemVSizing": "fix"])
        let columnObjects = self.objects([column, wide])
        XCTAssertEqual(InspectCSS.value("width", shape: wide, objects: columnObjects), "100%")

        // An absolute child keeps its position.
        let pinned = shape(rectID, "rect", name: "Badge", parent: flexID, 50, 20, 10, 10, ["layoutItemAbsolute": true])
        let pinnedObjects = self.objects([flexBoard, pinned])
        XCTAssertEqual(InspectCSS.value("left", shape: pinned, objects: pinnedObjects), "40px")
        XCTAssertEqual(InspectCSS.value("position", shape: pinned, objects: pinnedObjects), "absolute")
    }

    func testGrid() {
        let gridID = "66666666-6666-4666-8666-000000000001"
        let grid = shape(gridID, "frame", name: "Grid", 0, 0, 300, 200, [
            "layout": "grid", "layoutGridDir": "column",
            "layoutGridRows": [["type": "flex", "value": 1], ["type": "fixed", "value": 100]],
            "layoutGridColumns": [["type": "percent", "value": 50], ["type": "auto", "value": 0]],
            "layoutGridCells": ["c1": ["id": "c1", "row": 1, "column": 1, "rowSpan": 1, "columnSpan": 2,
                                       "position": "manual", "shapes": [rectID],
                                       "alignSelf": "auto", "justifySelf": "center"]],
        ])
        let cell = shape(rectID, "rect", name: "Cell", parent: gridID, 0, 0, 300, 100,
                         ["layoutItemHSizing": "fix", "layoutItemVSizing": "fix"])
        let objects = objects([grid, cell])
        XCTAssertEqual(InspectCSS.value("display", shape: grid, objects: objects), "grid")
        XCTAssertEqual(InspectCSS.value("grid-template-rows", shape: grid, objects: objects), "1fr 100px")
        XCTAssertEqual(InspectCSS.value("grid-template-columns", shape: grid, objects: objects), "50% auto")
        XCTAssertEqual(InspectCSS.value("grid-auto-flow", shape: grid, objects: objects), "column")
        XCTAssertEqual(InspectCSS.value("grid-column", shape: cell, objects: objects), "1 / 3")
        XCTAssertEqual(InspectCSS.value("grid-row", shape: cell, objects: objects), "1")
        XCTAssertEqual(InspectCSS.value("justify-self", shape: cell, objects: objects), "center")
        XCTAssertNil(InspectCSS.value("align-self", shape: cell, objects: objects))
    }

    // MARK: - Text

    func testTextRuns() {
        let textID = "77777777-7777-4777-8777-0123456789ab"
        func run(_ text: String, weight: String, color: String, opacity: Double,
                 spacing: String, extra: [String: Any] = [:]) -> [String: Any] {
            var run: [String: Any] = ["text": text, "fontId": "gfont-inter", "fontFamily": "Inter",
                                      "fontVariantId": weight == "400" ? "regular" : weight, "fontSize": "24",
                                      "fontWeight": weight, "fontStyle": "normal", "lineHeight": "1.5",
                                      "letterSpacing": spacing,
                                      "fills": [["fillColor": color, "fillOpacity": opacity]]]
            run.merge(extra) { $1 }
            return run
        }
        let content: [String: Any] = [
            "type": "root", "verticalAlign": "center",
            "children": [["type": "paragraph-set", "children": [[
                "type": "paragraph", "lineHeight": "1.5", "textAlign": "left",
                "children": [run("Hello ", weight: "400", color: "#111111", opacity: 1, spacing: "0"),
                             run("World", weight: "700", color: "#ff0000", opacity: 0.5, spacing: "0.5",
                                 extra: ["textDecoration": "underline"])],
            ]]]],
        ]
        let text = shape(textID, "text", name: "Title", 20, 200, 120, 29,
                         ["growType": "auto-width", "content": content])
        let objects = objects([text])
        XCTAssertNil(InspectCSS.value("width", shape: text, objects: objects), "auto width: no width")
        XCTAssertEqual(InspectCSS.value("height", shape: text, objects: objects), "29px")
        XCTAssertEqual(InspectCSS.stylesheet([textID], objects: objects, prelude: false), """
            /* Title */
            .title-0123456789ab {
              position: absolute;
              left: 20px;
              top: 200px;
              height: 29px;
            }
            .title-0123456789ab .root-0 {
              display: flex;
              white-space: break-spaces;
              align-items: center;
            }
            .title-0123456789ab .root-0-paragraph-set-0 {
              display: inline-flex;
              flex-direction: column;
              justify-content: inherit;
              margin-right: 1px;
              vertical-align: top;
            }
            .title-0123456789ab .root-0-paragraph-set-0-paragraph-0 {
              font-size: 0;
              line-height: 1.5;
              margin: 0;
              text-align: left;
            }
            .title-0123456789ab .root-0-paragraph-set-0-paragraph-0-text-0 {
              font-size: 24px;
              color: rgba(17, 17, 17, 1);
              caret-color: rgba(17, 17, 17, 1);
              overflow-wrap: initial;
              line-break: auto;
              white-space: pre;
              text-rendering: geometricPrecision;
              letter-spacing: 0px;
              font-family: "Inter";
              font-style: normal;
              font-weight: 400;
            }
            .title-0123456789ab .root-0-paragraph-set-0-paragraph-0-text-1 {
              text-decoration: underline;
              font-size: 24px;
              color: rgba(255, 0, 0, 0.5);
              caret-color: rgba(255, 0, 0, 0.5);
              overflow-wrap: initial;
              line-break: auto;
              white-space: pre;
              text-rendering: geometricPrecision;
              letter-spacing: 0.5px;
              font-family: "Inter";
              font-style: normal;
              font-weight: 700;
            }
            """)
    }

    // MARK: - Gradients and images

    func testGradientAndImageFills() {
        let stops: [[String: Any]] = [["color": "#ff0000", "opacity": 1, "offset": 0],
                                      ["color": "#0000ff", "opacity": 0.5, "offset": 0.57],
                                      ["color": "#00ff00", "opacity": 1, "offset": 1]]
        func fill(_ gradientType: String) -> [String: Any] {
            ["fillOpacity": 1, "fillColorGradient": ["type": gradientType, "startX": 0.5, "startY": 0,
                                                     "endX": 0.5, "endY": 1, "width": 1, "stops": stops]]
        }
        // Penpot ignores the gradient's angle, and prints the offset as JavaScript computes it.
        XCTAssertEqual(InspectCSS.value("background", shape: ["fills": [fill("linear")]], objects: [:]),
                       "linear-gradient(to bottom, rgba(255, 0, 0, 1) 0%,rgba(0, 0, 255, 0.5) 56.99999999999999%,rgba(0, 255, 0, 1) 100%)")
        XCTAssertEqual(InspectCSS.value("background", shape: ["fills": [fill("radial")]], objects: [:]),
                       "radial-gradient(circle, rgba(255, 0, 0, 1) 0%,rgba(0, 0, 255, 0.5) 56.99999999999999%,rgba(0, 255, 0, 1) 100%)")

        let server = URL(string: "https://penpot.test")!
        let image: [String: Any] = ["id": "img1", "width": 10, "height": 10, "mtype": "image/png"]
        XCTAssertEqual(InspectCSS.value("background", shape: ["fills": [["fillImage": image, "fillOpacity": 1]]],
                                        objects: [:], server: server),
                       "url(https://penpot.test/assets/by-file-media-id/img1) no-repeat center center / cover")
        XCTAssertEqual(InspectCSS.value("background", shape: ["fills": [["fillImage": image, "fillOpacity": 0.5]]],
                                        objects: [:], server: server),
                       "linear-gradient(to bottom, rgba(255, 255, 255, 0.5) 0%,rgba(255, 255, 255, 0.5) 0%), url(https://penpot.test/assets/by-file-media-id/img1) no-repeat center center / cover")
    }

    // MARK: - Names and numbers

    func testHumanizedAndSelectors() {
        XCTAssertEqual(InspectCSS.humanized("width"), "Width")
        XCTAssertEqual(InspectCSS.humanized("border-radius"), "Border radius")
        XCTAssertEqual(InspectCSS.humanized("padding-inline-start"), "Padding inline start")

        let id = "88888888-8888-4888-8888-0123456789ab"
        XCTAssertEqual(InspectCSS.selector(["name": "My Button 2", "id": id]), "my-button-0123456789ab")
        XCTAssertEqual(InspectCSS.selector(["name": "1st item", "id": id]), "c-1st-item-0123456789ab")
        XCTAssertEqual(InspectCSS.selector(["name": "iPhone 15 Pro", "id": id]), "i-phone-15-0123456789ab")
        XCTAssertEqual(InspectCSS.selector(["name": "Ünïcode ✓", "id": id]), "ncode-0123456789ab")
    }

    func testJavaScriptNumbers() {
        XCTAssertEqual(InspectCSS.js(100), "100")
        XCTAssertEqual(InspectCSS.js(0.5), "0.5")
        XCTAssertEqual(InspectCSS.js(0.1 + 0.2), "0.30000000000000004")
        XCTAssertEqual(InspectCSS.js(0.00001), "0.00001")
        XCTAssertEqual(InspectCSS.js(1e-7), "1e-7")
        XCTAssertEqual(InspectCSS.pixels(10.456), "10.46px")
        XCTAssertEqual(InspectCSS.pixels(-2.5), "-2.5px")
        XCTAssertEqual(InspectCSS.jsRound(-2.5), -2)
        XCTAssertEqual(InspectCSS.formatNumber(0.5), "0.5")
        XCTAssertEqual(InspectCSS.formatNumber(1), "1")
    }
}
