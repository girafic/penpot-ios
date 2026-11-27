import CoreGraphics
import Foundation

/// Penpot's inspect values and CSS (`app.util.code-gen.style-css*`) for shapes of a page's
/// objects: `get-page` JSON, camelCase keys (`selrect`, `fills`, `fillColor`, `layoutFlexDir`, …).
///
/// A port of `style_css.cljs`, `style_css_values.cljs`, `style_css_formats.cljs` and
/// `code_gen/common.cljs` (penpot/penpot@develop), quirks included:
/// - numbers print the way JavaScript prints them (`1`, `0.5`, `30.000000000000004`); sizes
///   and positions are rounded to 2 decimals first (`fmt/format-pixels`);
/// - a color is the stored hex plus the opacity in hex (`#ff0000FF`), or `rgba(…)`/`hsla(…)`
///   in those color spaces; gradients are always `to bottom` / `circle`, stops joined
///   without a space;
/// - `left`/`top` are relative to the parent (minus its border), and absent for root boards
///   and for children of a flex or grid layout that aren't absolute;
/// - shapes Penpot draws as SVG (paths, booleans, imported SVG, masks, several fills, a stroke
///   that isn't inner, a text with shadows or strokes) get no background, border, shadow or
///   blur; every shadow and a layer blur count even when hidden, as in Penpot.
///
/// Deliberate differences: declarations without a value (Penpot writes a line of two spaces
/// for them) and empty lists (`box-shadow: ;`) are left out; a text's font family, style and
/// weight come from its own attributes instead of Penpot's font catalogue; the wrapper rule
/// of a rotated layout child lists its properties in source order (Penpot's is a hash set's).
enum InspectCSS {
    typealias Object = [String: Any]

    /// The color spaces of Penpot's inspect ("Select color space": HEX, RGBA, HSLA).
    enum ColorFormat: String, CaseIterable, Sendable {
        case hex, rgba, hsla
    }

    static let rootID = "00000000-0000-0000-0000-000000000000"

    /// `get-css-value`: what Penpot's Info tab shows for `property` ("width", "left", "border-radius",
    /// "display", "margin", "flex-direction", …), nil when the shape has none.
    ///
    /// Penpot also calls this on a stroke (`border-style`, `border-width`, `border-color`, the
    /// per-side widths) and on `["fills": [fill]]` (`background`) for its fill and stroke rows.
    static func value(_ property: String, shape: Object, objects: [String: Object],
                      format: ColorFormat = .hex, server: URL? = nil) -> String? {
        Generator(objects: objects, format: format, server: server).css(property, of: shape)?.value
    }

    /// `get-css-property`: "property: value;", what a row's copy button copies.
    static func declaration(_ property: String, shape: Object, objects: [String: Object],
                            format: ColorFormat = .hex, server: URL? = nil) -> String? {
        Generator(objects: objects, format: format, server: server).css(property, of: shape)?.declaration
    }

    /// `get-shape-properties-css`: a section's copy button, one declaration per line, each
    /// indented by two spaces as Penpot writes them.
    static func declarations(_ properties: [String], shape: Object, objects: [String: Object],
                             format: ColorFormat = .hex, server: URL? = nil) -> String {
        Generator(objects: objects, format: format, server: server).block(properties, of: shape)
    }

    /// The Code tab's stylesheet for `ids` and their whole subtrees, as Penpot's `generate-style`
    /// writes it (selectors from shape names, text runs' rules for texts), after its prelude.
    /// Shapes come in Penpot's order (`sort-z-index`): a parent before its children, the
    /// topmost sibling first.
    static func stylesheet(_ ids: [String], objects: [String: Object], prelude: Bool = true,
                           server: URL? = nil) -> String {
        var generator = Generator(objects: objects, format: .hex, server: server)
        generator.rootShapes = Set(ids)
        var all: [String] = []
        var seen = Set<String>()
        func add(_ id: String) {
            guard seen.insert(id).inserted else { return }
            all.append(id)
        }
        for id in ids {
            add(id)
            generator.descendants(of: id).forEach(add)
        }
        let rules = generator.sortedByZIndex(all)
            .compactMap { objects[$0].flatMap(generator.rule) }
            .joined(separator: "\n\n")
        return (prelude ? Self.prelude : "") + rules
    }

    /// A color as the Info tab's color rows write it in `format` (`format-color-value`).
    static func color(_ hex: String, opacity: Double, format: ColorFormat) -> String {
        Generator(objects: [:], format: format, server: nil)
            .color(Paint(color: hex, opacity: opacity, gradient: nil, image: nil)) ?? hex
    }

    /// `get-css-rule-humanized`: "Width", "Border radius".
    static func humanized(_ property: String) -> String {
        let text = property.components(separatedBy: "-").joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// `shape->selector`: the shape's class, from the first 10 characters of its name and the
    /// last 12 of its id ("rectangle-0123456789ab").
    static func selector(_ shape: Object) -> String {
        let fullName = shape.str("name") ?? ""
        var name = String(decoding: Array(fullName.utf16.prefix(10)), as: UTF16.self)
        name = String(name.unicodeScalars.filter { scalar in
            (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == ":"))
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }.map(Character.init))
        if let first = name.unicodeScalars.first, ("0"..."9").contains(first) { name = "c-" + name }
        let id = Array((shape.str("id") ?? "").utf16)
        let idPart = id.count > 24 ? String(decoding: id[24..<min(36, id.count)], as: UTF16.self) : ""
        var selector = cssSelector(name + " " + idPart)
        if selector.hasPrefix("-") { selector.removeFirst() }
        return selector
    }

    // MARK: - Penpot's property lists

    /// The properties of a shape's rule, in order (`shape-css-properties`).
    static let shapeProperties = [
        "position", "left", "top", "width", "height", "transform", "background", "border",
        "border-block-start-width", "border-inline-end-width", "border-block-end-width",
        "border-inline-start-width", "border-start-start-radius", "border-start-end-radius",
        "border-end-start-radius", "border-end-end-radius", "box-shadow", "filter",
        "backdrop-filter", "opacity", "overflow", "blend-mode",
        // Flex/grid
        "display", "align-items", "align-content", "justify-items", "justify-content", "gap",
        "column-gap", "row-gap", "padding-inline-start", "padding-inline-end",
        "padding-block-start", "padding-block-end", "z-index",
        // Flex
        "flex-direction", "flex-wrap", "flex", "flex-grow",
        // Grid
        "grid-template-rows", "grid-template-columns", "grid-template-areas", "grid-auto-flow",
        // Flex/grid children
        "flex-shrink", "margin-block-start", "margin-block-end", "margin-inline-start",
        "margin-inline-end", "max-height", "max-block-size", "min-height", "min-block-size",
        "max-width", "max-inline-size", "min-width", "min-inline-size", "align-self",
        "justify-self",
        // Grid cells
        "grid-column", "grid-row", "grid-area",
    ]

    /// The Info tab's "Size and position" rows (`attributes/geometry.cljs`).
    static let geometryProperties = ["width", "height", "left", "top", "border-radius", "transform"]
    /// The Info tab's layer rows (`attributes/visibility.cljs`): not for texts and groups.
    static let visibilityProperties = ["opacity", "blend-mode", "visibility"]
    /// The Info tab's "Layout" rows of a flex or grid board (`attributes/layout.cljs`).
    static let layoutProperties = [
        "display", "flex-direction", "flex-wrap", "grid-template-rows", "grid-template-columns",
        "align-items", "align-content", "justify-items", "justify-content", "row-gap",
        "column-gap", "gap", "padding-inline-start", "padding-inline-end", "padding-block-start",
        "padding-block-end",
    ]
    /// The Info tab's rows of a layout child (`attributes/layout_element.cljs`).
    static let layoutElementProperties = [
        "margin", "max-height", "min-height", "max-width", "min-width", "align-self",
        "justify-self", "flex-shrink", "flex", "grid-column", "grid-row",
    ]

    /// A stroke's rows (`attributes/stroke.cljs`): its style and width, or the four side
    /// widths when they differ; the color is its own row (`border-color`).
    static func strokeProperties(_ stroke: Object) -> [String] {
        Generator.perSideWidths(stroke) != nil
            ? ["border-style", "border-block-start-width", "border-inline-end-width",
               "border-block-end-width", "border-inline-start-width"]
            : ["border-style", "border-width"]
    }

    /// The panels Penpot's Info tab shows for a shape type (`attributes.cljs` `type->options`):
    /// `visibility`, `geometry`, `fill`, `stroke`, `shadow`, `blur`, `layout`, `layout-element`,
    /// `text`, `svg`. Images, booleans and imported SVG get none.
    static func panels(forType type: String) -> [String] {
        switch type {
        case "frame": ["visibility", "geometry", "fill", "stroke", "shadow", "blur", "layout", "layout-element"]
        case "group": ["visibility", "geometry", "svg", "layout-element"]
        case "rect", "circle", "path":
            ["visibility", "geometry", "fill", "stroke", "shadow", "blur", "svg", "layout-element"]
        case "text": ["visibility", "geometry", "text", "shadow", "blur", "stroke", "layout-element"]
        default: []
        }
    }

    /// Prepended to the Code tab's stylesheet (`style-css/prelude`).
    static let prelude = """

        html, body {
          margin: 0;
          min-height: 100%;
          min-width: 100%;
          padding: 0;
        }

        body {
          display: flex;
          flex-direction: column;
          align-items: center;
          width: 100vw;
          min-height: 100vh;
        }

        * {
          box-sizing: border-box;
        }

        .text-node { background-clip: text !important; -webkit-background-clip: text !important; }


        """

    // MARK: - Formatting helpers (`app.main.ui.formats`, `app.common.math`)

    /// A number as JavaScript's `String(n)` writes it.
    static func js(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "NaN" : (value > 0 ? "Infinity" : "-Infinity") }
        if value == 0 { return "0" }
        if value == value.rounded(), abs(value) < 1e21 { return String(format: "%.0f", value) }
        let text = "\(value)"
        guard let e = text.firstIndex(of: "e"), let exponent = Int(text[text.index(after: e)...]) else {
            return text
        }
        // Swift writes 1e-05 where JavaScript writes 0.00001 (exponents only below 1e-6).
        let negative = text.hasPrefix("-")
        let mantissa = text[..<e].replacingOccurrences(of: "-", with: "")
        let digits = mantissa.replacingOccurrences(of: ".", with: "")
        if exponent < 0, exponent >= -6 {
            return (negative ? "-" : "") + "0." + String(repeating: "0", count: -exponent - 1) + digits
        }
        return (negative ? "-" : "") + mantissa + "e" + (exponent > 0 ? "+" : "-") + String(abs(exponent))
    }

    /// JavaScript's `Math.round`: halves go up.
    static func jsRound(_ value: Double) -> Double {
        let down = value.rounded(.down)
        return value - down >= 0.5 ? down + 1 : down
    }

    /// `mth/precision`.
    static func precision(_ value: Double, _ digits: Int) -> Double {
        let factor = pow(10, Double(digits))
        return jsRound(value * factor) / factor
    }

    /// `fmt/format-pixels`: "12.35px".
    static func pixels(_ value: Double) -> String { js(precision(value, 2)) + "px" }

    /// `d/format-number`: two decimals at most, trailing zeros dropped ("0.5", "1").
    static func formatNumber(_ value: Double) -> String {
        var text = String(format: "%.2f", value == 0 ? 0 : value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// `fmt/format-matrix`: `matrix(a, b, c, d, e, f)`, two fixed decimals each.
    fileprivate static func fixed(_ value: Double) -> String {
        String(format: "%.2f", value == 0 ? 0 : value)
    }

    /// cuerdas' `css-selector`: a dash before every capital, runs of anything but letters,
    /// digits, apostrophes and brackets as separators, lowercased.
    fileprivate static func cssSelector(_ text: String) -> String {
        var dashed = ""
        for scalar in text.unicodeScalars {
            if scalar.properties.isUppercase, scalar.properties.generalCategory == .uppercaseLetter {
                dashed.unicodeScalars.append("-")
            }
            dashed.unicodeScalars.append(scalar)
        }
        func kept(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber, .openPunctuation, .closePunctuation:
                true
            default:
                scalar == "'"
            }
        }
        var parts: [String] = []
        var current = ""
        var inSeparator = false
        for scalar in dashed.unicodeScalars {
            if kept(scalar) {
                if inSeparator { parts.append(current); current = ""; inSeparator = false }
                current.unicodeScalars.append(scalar)
            } else {
                inSeparator = true
            }
        }
        parts.append(current)
        if inSeparator { parts.append("") }
        return parts.map { $0.lowercased() }.joined(separator: "-")
    }
}

// MARK: - Generator

private typealias Object = InspectCSS.Object

/// What Penpot's `get-value` returns, before `format-value` writes it.
private enum Raw {
    case number(Double)
    /// A string Penpot writes as is ("50%", "hidden", a matrix).
    case string(String)
    /// A keyword (`:fill`, `:absolute`, `:row`), written as its name.
    case keyword(String)
    case numbers([Double])
    case paint(Paint)
    case stroke(Stroke)
    /// `{:width w}`, a side's width.
    case width(Double?)
    case shadows([Object])
    case tracks([Object])
}

/// `{:color :opacity :gradient :image}`.
private struct Paint {
    var color: String?
    var opacity: Double?
    var gradient: Object?
    var image: Object?
}

/// `get-stroke-data`: `{:color :style :width}`.
private struct Stroke {
    var color: Paint
    var style: String?
    var width: Double?
}

private struct Rect {
    var x: Double, y: Double, width: Double, height: Double
    var maxX: Double { x + width }
    var maxY: Double { y + height }

    static func bounding(_ points: [CGPoint]) -> Rect? {
        guard !points.isEmpty else { return nil }
        let xs = points.map { Double($0.x) }, ys = points.map { Double($0.y) }
        return Rect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    static func join(_ rects: [Rect]) -> Rect? {
        guard let first = rects.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.maxX, maxY = first.maxY
        for rect in rects.dropFirst() {
            minX = min(minX, rect.x); minY = min(minY, rect.y)
            maxX = max(maxX, rect.maxX); maxY = max(maxY, rect.maxY)
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func grown(horizontal: Double, vertical: Double) -> Rect {
        Rect(x: x - horizontal, y: y - vertical, width: width + 2 * horizontal, height: height + 2 * vertical)
    }
}

/// Penpot's affine matrix (`gmt`): x' = a·x + c·y + e, y' = b·x + d·y + f.
private struct Matrix {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

    static let identity = Matrix()

    init() {}

    init(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double) {
        (self.a, self.b, self.c, self.d, self.e, self.f) = (a, b, c, d, e, f)
    }

    init?(_ json: Object?) {
        guard let json else { return nil }
        a = json.num("a") ?? 1; b = json.num("b") ?? 0; c = json.num("c") ?? 0
        d = json.num("d") ?? 1; e = json.num("e") ?? 0; f = json.num("f") ?? 0
    }

    /// `gmt/multiply`: self × other.
    func multiplied(_ m: Matrix) -> Matrix {
        Matrix(a: a * m.a + c * m.b, b: b * m.a + d * m.b,
               c: a * m.c + c * m.d, d: b * m.c + d * m.d,
               e: a * m.e + c * m.f + e, f: b * m.e + d * m.f + f)
    }

    var inverted: Matrix? {
        let det = a * d - b * c
        guard det != 0 else { return nil }
        return Matrix(a: d / det, b: -b / det, c: -c / det, d: a / det,
                      e: (c * f - d * e) / det, f: (b * e - a * f) / det)
    }

    /// `gmt/unit?`, to Penpot's 0.001.
    var isUnit: Bool {
        func close(_ x: Double, _ y: Double) -> Bool { abs(x - y) <= 0.001 }
        return close(a, 1) && close(b, 0) && close(c, 0) && close(d, 1) && close(e, 0) && close(f, 0)
    }

    func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(x: Double(p.x) * a + Double(p.y) * c + e, y: Double(p.x) * b + Double(p.y) * d + f)
    }

    static func translation(_ x: Double, _ y: Double) -> Matrix { Matrix(a: 1, b: 0, c: 0, d: 1, e: x, f: y) }
}

private struct Generator {
    let objects: [String: Object]
    var format: InspectCSS.ColorFormat
    var server: URL?
    /// The shapes the stylesheet is for (`:root-shapes`): a layout board among them fills.
    var rootShapes: Set<String> = []

    struct CSS {
        let property: String
        let value: String
        var declaration: String {
            "\(property == "blend-mode" ? "mix-blend-mode" : property): \(value);"
        }
    }

    func css(_ property: String, of shape: Object) -> CSS? {
        guard let raw = raw(property, shape), let value = format(property, raw) else { return nil }
        return CSS(property: property, value: value)
    }

    /// `format-css-properties`: "  property: value;" lines.
    func block(_ properties: [String], of shape: Object) -> String {
        lines(properties.compactMap { css($0, of: shape) })
    }

    func lines(_ declarations: [CSS]) -> String {
        declarations.map { "  " + $0.declaration }.joined(separator: "\n")
    }

    // MARK: Shape predicates (`cfh`, `ctl`, `cgc`)

    func parent(_ shape: Object) -> Object? { shape.str("parentId").flatMap { objects[$0] } }
    func type(_ shape: Object?) -> String? { shape?.str("type") }
    func isFrame(_ shape: Object?) -> Bool { type(shape) == "frame" }
    func isText(_ shape: Object) -> Bool { type(shape) == "text" }

    func isRootFrame(_ shape: Object) -> Bool {
        shape.str("id") != InspectCSS.rootID && isFrame(shape) && shape.str("frameId") == InspectCSS.rootID
    }

    private func layout(_ shape: Object?) -> String? { isFrame(shape) ? shape?.str("layout") : nil }
    func isFlex(_ shape: Object?) -> Bool { layout(shape) == "flex" }
    func isGrid(_ shape: Object?) -> Bool { layout(shape) == "grid" }
    func isAnyLayout(_ shape: Object?) -> Bool { isFlex(shape) || isGrid(shape) }
    func isFlexChild(_ shape: Object) -> Bool { isFlex(parent(shape)) }
    func isGridChild(_ shape: Object) -> Bool { isGrid(parent(shape)) }
    func isLayoutChild(_ shape: Object) -> Bool { isAnyLayout(parent(shape)) }

    /// `ctl/position-absolute?`: absolute in its layout, or hidden.
    func isAbsolute(_ shape: Object) -> Bool { shape.isTrue("layoutItemAbsolute") || shape.truthy("hidden") }

    func isGroupLike(_ shape: Object) -> Bool {
        let type = type(shape)
        return type == "group" || type == "bool" || (type == "svg-raw" && !shape.strs("shapes").isEmpty)
    }

    /// `cgc/svg-markup?`: Penpot's code draws the shape as SVG, not HTML and CSS.
    func isSVGMarkup(_ shape: Object) -> Bool {
        let type = type(shape)
        if ["path", "bool", "svg-raw"].contains(type) { return true }
        if shape.val("svgAttrs") != nil { return true }
        if type == "group", shape.truthy("maskedGroup") { return true }
        let shadows = shape.arr("shadow")?.count ?? 0
        let strokes = shape.objs("strokes")
        if type == "text", shadows > 0 || !strokes.isEmpty { return true }
        if (shape.arr("fills")?.count ?? 0) > 1 { return true }
        return strokes.count > 1 || (strokes.count == 1 && strokes[0].str("strokeAlignment") != "inner")
    }

    /// `cgc/has-wrapper?`: a layout child with a transform goes in a wrapper of its box.
    func hasWrapper(_ shape: Object) -> Bool {
        isLayoutChild(shape) && !isAbsolute(shape) && !(Matrix(shape.obj("transform"))?.isUnit ?? false)
    }

    func selrect(_ shape: Object?) -> Rect? {
        guard let rect = shape?.obj("selrect") else { return nil }
        return Rect(x: rect.num("x") ?? 0, y: rect.num("y") ?? 0,
                    width: rect.num("width") ?? 0, height: rect.num("height") ?? 0)
    }

    func points(_ shape: Object?) -> [CGPoint] {
        (shape?.objs("points") ?? []).compactMap { point in
            guard let x = point.num("x"), let y = point.num("y") else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    /// The shape's corners: its points, else its selrect's.
    func corners(_ shape: Object) -> [CGPoint] {
        let points = points(shape)
        if points.count >= 4 { return points }
        guard let r = selrect(shape) else { return [] }
        return [CGPoint(x: r.x, y: r.y), CGPoint(x: r.maxX, y: r.y),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.x, y: r.maxY)]
    }

    /// `(:transform-inverse parent (gmt/matrix))`.
    func inverseTransform(_ shape: Object?) -> Matrix {
        if let inverse = Matrix(shape?.obj("transformInverse")) { return inverse }
        return Matrix(shape?.obj("transform"))?.inverted ?? .identity
    }

    func descendants(of id: String) -> [String] {
        var result: [String] = []
        var visited = Set<String>()
        func walk(_ id: String) {
            for child in objects[id]?.strs("shapes") ?? [] where visited.insert(child).inserted {
                result.append(child)
                walk(child)
            }
        }
        walk(id)
        return result
    }

    // MARK: Values (`style-css-values/get-value`)

    func raw(_ property: String, _ shape: Object) -> Raw? {
        switch property {
        case "position": return position(shape)
        case "left": return shapePosition(shape, horizontal: true).map(Raw.number)
        case "top": return shapePosition(shape, horizontal: false).map(Raw.number)
        case "z-index":
            if isRootFrame(shape) { return .number(0) }
            return isLayoutChild(shape) ? shape.num("layoutItemZIndex").map(Raw.number) : nil
        case "transform": return transform(shape).map(Raw.string)
        case "width": return width(shape)
        case "height": return height(shape)
        case "max-width", "max-inline-size":
            return isLayoutChild(shape) ? shape.num("layoutItemMaxW").map(Raw.number) : nil
        case "max-height", "max-block-size":
            return isLayoutChild(shape) ? shape.num("layoutItemMaxH").map(Raw.number) : nil
        case "min-width", "min-inline-size": return minSize(shape, horizontal: true)
        case "min-height", "min-block-size": return minSize(shape, horizontal: false)
        case "margin": return margin(shape)
        case "margin-block-start": return marginSide(shape, "m1")
        case "margin-inline-end": return marginSide(shape, "m2")
        case "margin-block-end": return marginSide(shape, "m3")
        case "margin-inline-start": return marginSide(shape, "m4")
        case "padding": return padding(shape)
        case "padding-block-start": return paddingSide(shape, "p1")
        case "padding-inline-end": return paddingSide(shape, "p2")
        case "padding-block-end": return paddingSide(shape, "p3")
        case "padding-inline-start": return paddingSide(shape, "p4")
        case "border":
            return isSVGMarkup(shape) ? nil : Self.strokeData(shape.objs("strokes").first).map(Raw.stroke)
        case "border-style", "border-width", "border-color":
            return isSVGMarkup(shape) ? nil : Self.strokeData(shape).map(Raw.stroke)
        case "border-block-start-width": return sideWidth(shape, 0)
        case "border-inline-end-width": return sideWidth(shape, 1)
        case "border-block-end-width": return sideWidth(shape, 2)
        case "border-inline-start-width": return sideWidth(shape, 3)
        case "border-radius": return borderRadius(shape)
        case "border-start-start-radius": return corner(shape, "r1")
        case "border-start-end-radius": return corner(shape, "r2")
        case "border-end-start-radius": return corner(shape, "r3")
        case "border-end-end-radius": return corner(shape, "r4")
        case "background": return background(shape)
        case "opacity":
            guard let opacity = shape.num("opacity"), opacity < 1 else { return nil }
            return .number(opacity)
        case "box-shadow":
            let shadows = shape.objs("shadow")
            return isSVGMarkup(shape) || shadows.isEmpty ? nil : .shadows(shadows)
        case "filter":
            return isSVGMarkup(shape) ? nil : shape.obj("blur")?.num("value").map(Raw.number)
        case "backdrop-filter":
            return isSVGMarkup(shape) ? nil : shape.obj("backgroundBlur")?.num("value").map(Raw.number)
        case "overflow":
            return isFrame(shape) && !isSVGMarkup(shape) && !shape.truthy("showContent") ? .string("hidden") : nil
        case "display":
            if shape.truthy("hidden") { return .string("none") }
            if isFlex(shape) { return .string("flex") }
            return isGrid(shape) ? .string("grid") : nil
        case "flex": return flex(shape)
        case "flex-grow":
            return rootShapes.contains(shape.str("id") ?? "") && isAnyLayout(shape) ? .number(1) : nil
        case "flex-shrink": return flexShrink(shape)
        case "flex-direction": return shape.str("layoutFlexDir").map(Raw.keyword)
        case "flex-wrap": return shape.str("layoutWrapType").map(Raw.keyword)
        case "align-items": return shape.str("layoutAlignItems").map(Raw.keyword)
        case "align-content": return shape.str("layoutAlignContent").map(Raw.keyword)
        case "justify-items": return shape.str("layoutJustifyItems").map(Raw.keyword)
        case "justify-content": return shape.str("layoutJustifyContent").map(Raw.keyword)
        case "align-self": return alignSelf(shape)
        case "justify-self": return justifySelf(shape)
        case "grid-template-rows": return tracks(shape, "layoutGridRows")
        case "grid-template-columns": return tracks(shape, "layoutGridColumns")
        case "grid-template-areas": return templateAreas(shape)
        case "grid-column": return gridCoordinate(shape, "column", span: "columnSpan")
        case "grid-row": return gridCoordinate(shape, "row", span: "rowSpan")
        case "grid-area": return gridArea(shape)
        case "grid-auto-flow":
            return isGrid(shape) && shape.str("layoutGridDir") == "column" ? .string("column") : nil
        case "gap", "row-gap", "column-gap": return gap(property, shape)
        default: return Self.plain(shape.val(Self.camel(property)))
        }
    }

    private func position(_ shape: Object) -> Raw? {
        let inFlow = isLayoutChild(shape) && !isAbsolute(shape)
        if (inFlow && (isGroupLike(shape) || isFrame(shape) || isSVGMarkup(shape))) || isRootFrame(shape) {
            return .keyword("relative")
        }
        return inFlow ? nil : .keyword("absolute")
    }

    /// `get-shape-position`: the shape's unrotated box in its parent's axes, from the parent's
    /// box, inside its border.
    private func shapePosition(_ shape: Object, horizontal: Bool) -> Double? {
        guard !isRootFrame(shape), !isLayoutChild(shape) || isAbsolute(shape),
              let parent = parent(shape) else { return nil }
        let parentRect = selrect(parent)
        let parentValue = horizontal ? parentRect?.x : parentRect?.y
        var border = 0.0
        if let stroke = parent.objs("strokes").first, stroke.str("strokeStyle") != "none", !isSVGMarkup(parent) {
            border = stroke.num("strokeWidth") ?? 0
        }
        let center = CGPoint(x: (parentRect?.x ?? 0) + (parentRect?.width ?? 0) / 2,
                             y: (parentRect?.y ?? 0) + (parentRect?.height ?? 0) / 2)
        let matrix = Matrix.translation(center.x, center.y)
            .multiplied(inverseTransform(parent))
            .multiplied(.translation(-center.x, -center.y))
        let points = corners(shape).map(matrix.apply)
        guard let geometry = Self.geometry(points) else { return nil }
        return (horizontal ? geometry.x : geometry.y) - (parentValue ?? 0) - border
    }

    /// `gsh/calculate-geometry`'s selrect: the unrotated box the points span.
    static func geometry(_ points: [CGPoint]) -> Rect? {
        guard points.count >= 4, let box = Rect.bounding(points) else { return nil }
        let width = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
        let height = hypot(points[0].x - points[3].x, points[0].y - points[3].y)
        let cx = box.x + box.width / 2, cy = box.y + box.height / 2
        return Rect(x: cx - width / 2, y: cy - height / 2, width: width, height: height)
    }

    private func transform(_ shape: Object) -> String? {
        let parentInverse = inverseTransform(parent(shape))
        let matrix = isSVGMarkup(shape)
            ? parentInverse
            : (Matrix(shape.obj("transform")) ?? .identity).multiplied(parentInverse)
        let text = matrix.isUnit ? nil : "matrix(\([matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f].map(InspectCSS.fixed).joined(separator: ", ")))"
        return hasWrapper(shape) ? "translate(-50%, -50%) " + (text ?? "") : text
    }

    private func width(_ shape: Object) -> Raw? {
        if rootShapes.contains(shape.str("id") ?? ""), isAnyLayout(shape) { return .keyword("fill") }
        if isText(shape), shape.str("growType") == "auto-width" { return nil }
        return shapeSize(shape, horizontal: true)
    }

    private func height(_ shape: Object) -> Raw? {
        if rootShapes.contains(shape.str("id") ?? ""), isAnyLayout(shape) { return nil }
        if isText(shape), shape.str("growType") == "auto-height" { return nil }
        return shapeSize(shape, horizontal: false)
    }

    /// `get-shape-size`: 100 % or auto as the layout sizes it, else the box.
    private func shapeSize(_ shape: Object, horizontal: Bool) -> Raw? {
        let parent = shape.str("id").flatMap { objects[$0] }.flatMap(self.parent) ?? self.parent(shape)
        let h = shape.str("layoutItemHSizing"), v = shape.str("layoutItemVSizing")
        let sizing = horizontal ? h : v
        let direction = parent?.str("layoutFlexDir") ?? ""
        let rows = ["row", "row-reverse"].contains(direction)
        let columns = ["column", "column-reverse"].contains(direction)
        if isFlexChild(shape), (!horizontal && rows && v == "fill") || (horizontal && columns && h == "fill") {
            return .keyword("fill")
        }
        if isFlexChild(shape), sizing == "fill" { return nil }
        if isGridChild(shape), sizing == "fill" { return nil }
        if isAnyLayout(shape), sizing == "auto", !isSVGMarkup(shape) { return .keyword("auto") }
        if let rect = selrect(shape) { return .number(horizontal ? rect.width : rect.height) }
        return shape.num(horizontal ? "width" : "height").map(Raw.number)
    }

    private func minSize(_ shape: Object, horizontal: Bool) -> Raw? {
        if isLayoutChild(shape), let value = shape.num(horizontal ? "layoutItemMinW" : "layoutItemMinH") {
            return .number(value)
        }
        let auto = shape.str(horizontal ? "layoutItemHSizing" : "layoutItemVSizing") == "auto"
        if auto, isFrame(shape), !shape.truthy("showContent"), let rect = selrect(shape) {
            return .number(horizontal ? rect.width : rect.height)
        }
        return nil
    }

    private func margin(_ shape: Object) -> Raw? {
        guard isLayoutChild(shape), !isAbsolute(shape) else { return nil }
        let margin = shape.obj("layoutItemMargin") ?? [:]
        let values = ["m1", "m2", "m3", "m4"].map { margin.num($0) ?? 0 }
        return values.contains { $0 != 0 } ? .numbers(values) : nil
    }

    private func marginSide(_ shape: Object, _ key: String) -> Raw? {
        guard isLayoutChild(shape), !isAbsolute(shape),
              let value = shape.obj("layoutItemMargin")?.num(key), value != 0 else { return nil }
        return .numbers([value])
    }

    private func padding(_ shape: Object) -> Raw? {
        guard let padding = shape.obj("layoutPadding") else { return nil }
        let values = ["p1", "p2", "p3", "p4"].map { padding.num($0) ?? 0 }
        return values.contains { $0 != 0 } ? .numbers(values) : nil
    }

    private func paddingSide(_ shape: Object, _ key: String) -> Raw? {
        guard let value = shape.obj("layoutPadding")?.num(key), value != 0 else { return nil }
        return .numbers([value])
    }

    /// `get-stroke-data`: nil for no stroke or a stroke of style none.
    static func strokeData(_ stroke: Object?) -> Stroke? {
        guard let stroke, stroke.str("strokeStyle") != "none" else { return nil }
        return Stroke(color: Paint(color: stroke.str("strokeColor"), opacity: stroke.num("strokeOpacity"),
                                   gradient: stroke.obj("strokeColorGradient")),
                      style: stroke.str("strokeStyle"), width: stroke.num("strokeWidth"))
    }

    /// `stroke-per-side-widths`: top, right, bottom, left when they differ.
    static func perSideWidths(_ stroke: Object?) -> [Double?]? {
        guard let stroke else { return nil }
        let width = stroke.num("strokeWidth")
        let sides = ["strokeWidthTop", "strokeWidthRight", "strokeWidthBottom", "strokeWidthLeft"]
            .map { stroke.num($0) ?? width }
        return sides.allSatisfy({ $0 == sides[0] }) ? nil : sides
    }

    private func sideWidth(_ shape: Object, _ index: Int) -> Raw? {
        let stroke = shape.val("strokes") != nil ? shape.objs("strokes").first : shape
        guard let widths = Self.perSideWidths(stroke) else { return nil }
        return .width(widths[index])
    }

    private func borderRadius(_ shape: Object) -> Raw? {
        if type(shape) == "circle" { return .string("50%") }
        if shape.val("rx") != nil { return .numbers([shape.num("rx") ?? 0]) }
        let radii = ["r1", "r2", "r3", "r4"].compactMap { shape.num($0) }
        return radii.count == 4 ? .numbers(radii) : nil
    }

    private func corner(_ shape: Object, _ key: String) -> Raw? {
        guard let radius = shape.num(key), radius != 0 else { return nil }
        return .numbers([radius])
    }

    private func background(_ shape: Object) -> Raw? {
        let fills = shape.objs("fills")
        guard (shape.arr("fills")?.count ?? 0) == 1, let fill = fills.first,
              !isSVGMarkup(shape), type(shape) != "group" else { return nil }
        return .paint(Self.paint(fill))
    }

    static func paint(_ fill: Object) -> Paint {
        Paint(color: fill.str("fillColor"), opacity: fill.num("fillOpacity"),
              gradient: fill.obj("fillColorGradient"), image: fill.obj("fillImage"))
    }

    private func flex(_ shape: Object) -> Raw? {
        guard isFlexChild(shape) else { return nil }
        let direction = parent(shape)?.str("layoutFlexDir") ?? ""
        let fills = (["row", "row-reverse"].contains(direction) && shape.str("layoutItemHSizing") == "fill")
            || (["column", "column-reverse"].contains(direction) && shape.str("layoutItemVSizing") == "fill")
        return fills ? .number(1) : nil
    }

    /// `get-flex-shrink`, typos and all: it reads the shape's own direction.
    private func flexShrink(_ shape: Object) -> Raw? {
        guard isFlexChild(shape) else { return nil }
        let direction = shape.str("layoutFlexDir") ?? ""
        let h = shape.str("layoutItemHSizing"), v = shape.str("layoutItemVSizing")
        if ["row", "reverse-row"].contains(direction), h == "fill" { return nil }
        if ["column", "column-row"].contains(direction), v == "fill" { return nil }
        if h == "auto" || v == "auto" { return nil }
        return .number(0)
    }

    private func cells(_ grid: Object?) -> [Object] {
        guard let cells = grid?.obj("layoutGridCells") else { return [] }
        return cells.keys.sorted().compactMap { cells[$0] as? Object }
    }

    private func cell(of shape: Object) -> Object? {
        guard let id = shape.str("id") else { return nil }
        return cells(parent(shape)).first { $0.strs("shapes").contains(id) }
    }

    private func cell(in grid: Object, row: Int, column: Int) -> Object? {
        cells(grid).first { cell in
            let r = Int(cell.num("row") ?? 0), c = Int(cell.num("column") ?? 0)
            let rows = Int(cell.num("rowSpan") ?? 0), columns = Int(cell.num("columnSpan") ?? 0)
            return row >= r && column >= c && column < c + columns && row < r + rows
        }
    }

    private static func isArea(_ cell: Object) -> Bool {
        cell.str("position") == "area" && !(cell.str("areaName") ?? "").isEmpty
    }

    private func alignSelf(_ shape: Object) -> Raw? {
        if isFlexChild(shape) { return shape.str("layoutItemAlignSelf").map(Raw.keyword) }
        guard isGridChild(shape) else { return nil }
        let align = cell(of: shape)?.str("alignSelf")
        if align != "auto" { return align.map(Raw.keyword) }
        return shape.str("layoutItemVSizing") == "fill" ? .keyword("stretch") : nil
    }

    private func justifySelf(_ shape: Object) -> Raw? {
        guard isGridChild(shape) else { return nil }
        let justify = cell(of: shape)?.str("justifySelf")
        if justify != "auto" { return justify.map(Raw.keyword) }
        return shape.str("layoutItemHSizing") == "fill" ? .keyword("stretch") : nil
    }

    private func tracks(_ shape: Object, _ key: String) -> Raw? {
        let tracks = shape.objs(key)
        return tracks.isEmpty ? nil : .tracks(tracks)
    }

    private func templateAreas(_ shape: Object) -> Raw? {
        guard isGrid(shape), cells(shape).contains(where: Self.isArea) else { return nil }
        let rows = shape.arr("layoutGridRows")?.count ?? 0
        let columns = shape.arr("layoutGridColumns")?.count ?? 0
        let lines = (0..<rows).map { row in
            "\"" + (0..<columns).map { column in
                (cell(in: shape, row: row + 1, column: column + 1)?.str("areaName") ?? ".")
                    .replacingOccurrences(of: " ", with: "-")
            }.joined(separator: " ") + "\""
        }
        return .string(lines.joined(separator: "\n"))
    }

    private func gridCoordinate(_ shape: Object, _ key: String, span spanKey: String) -> Raw? {
        guard isGridChild(shape), !isAbsolute(shape), let cell = cell(of: shape), !Self.isArea(cell),
              cell.str("position") == "manual" || (cell.num("rowSpan") ?? 0) > 1 || (cell.num("columnSpan") ?? 0) > 1,
              let value = cell.num(key) else { return nil }
        if let span = cell.num(spanKey), span > 1 {
            return .string("\(InspectCSS.js(value)) / \(InspectCSS.js(value + span))")
        }
        return .number(value)
    }

    private func gridArea(_ shape: Object) -> Raw? {
        guard isGridChild(shape), !isAbsolute(shape), let cell = cell(of: shape), Self.isArea(cell),
              let name = cell.str("areaName") else { return nil }
        return .string(name.replacingOccurrences(of: " ", with: "-"))
    }

    /// `ctl/gaps` → `gap` when row and column gap match, else `row-gap` / `column-gap`.
    private func gap(_ property: String, _ shape: Object) -> Raw? {
        let gap = shape.obj("layoutGap")
        let row = gap?.num("rowGap").flatMap { $0.isFinite ? $0 : 0 } ?? 0
        let column = gap?.num("columnGap").flatMap { $0.isFinite ? $0 : 0 } ?? 0
        switch property {
        case "gap": return row == column && (row != 0 || column != 0) ? .numbers([row]) : nil
        case "row-gap": return row != column && row != 0 ? .numbers([row]) : nil
        default: return row != column && column != 0 ? .numbers([column]) : nil
        }
    }

    /// `(get shape property)`: a property Penpot reads straight off the shape.
    private static func plain(_ value: Any?) -> Raw? {
        switch value {
        case let text as String: return .keyword(text)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .string(number.boolValue ? "true" : "false") }
            return .number(number.doubleValue)
        default: return nil
        }
    }

    /// "blend-mode" → "blendMode", the JSON key.
    static func camel(_ property: String) -> String {
        let parts = property.components(separatedBy: "-")
        return parts[0] + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    // MARK: Formats (`style-css-formats/format-value`)

    private enum Formatter {
        case position, size, color, border, borderStyle, borderWidth, borderColor
        case sizeArray, stringOrSizeArray, tracks, shadows, blur
    }

    private static let formatters: [String: Formatter] = {
        var map: [String: Formatter] = ["left": .position, "top": .position, "background": .color,
                                         "border": .border, "border-style": .borderStyle,
                                         "border-color": .borderColor, "box-shadow": .shadows,
                                         "filter": .blur, "backdrop-filter": .blur,
                                         "grid-template-rows": .tracks, "grid-template-columns": .tracks]
        for key in ["width", "height", "max-height", "max-block-size", "min-height", "min-block-size",
                    "max-width", "max-inline-size", "min-width", "min-inline-size"] { map[key] = .size }
        for key in ["border-radius", "border-start-start-radius", "border-start-end-radius",
                    "border-end-start-radius", "border-end-end-radius"] { map[key] = .stringOrSizeArray }
        for key in ["border-width", "border-block-start-width", "border-inline-end-width",
                    "border-block-end-width", "border-inline-start-width"] { map[key] = .borderWidth }
        for key in ["gap", "row-gap", "column-gap", "padding", "padding-inline-start", "padding-inline-end",
                    "padding-block-start", "padding-block-end", "margin", "margin-block-start",
                    "margin-block-end", "margin-inline-start", "margin-inline-end"] { map[key] = .sizeArray }
        return map
    }()

    func format(_ property: String, _ raw: Raw) -> String? {
        switch (Self.formatters[property], raw) {
        case (.position?, .number(let value)):
            return InspectCSS.pixels(value)
        case (.size?, .keyword("fill")):
            return "100%"
        case (.size?, .keyword("auto")):
            return "auto"
        case (.size?, .number(let value)):
            return InspectCSS.pixels(value)
        case (.color?, .paint(let paint)):
            return color(paint)
        case (.border?, .stroke(let stroke)):
            return [stroke.width.map(InspectCSS.pixels) ?? "", stroke.style ?? "", color(stroke.color) ?? ""]
                .joined(separator: " ")
        case (.borderStyle?, .stroke(let stroke)):
            return stroke.style
        case (.borderWidth?, .stroke(let stroke)):
            return stroke.width.map(InspectCSS.pixels)
        case (.borderWidth?, .width(let width)):
            return width.map(InspectCSS.pixels)
        case (.borderColor?, .stroke(let stroke)):
            return color(stroke.color)
        case (.sizeArray?, .numbers(let values)) where !values.isEmpty,
             (.stringOrSizeArray?, .numbers(let values)) where !values.isEmpty:
            return values.map(InspectCSS.pixels).joined(separator: " ")
        case (.tracks?, .tracks(let tracks)):
            return tracks.map(Self.track).joined(separator: " ")
        case (.shadows?, .shadows(let shadows)):
            return shadows.map(shadow).joined(separator: ", ")
        case (.blur?, .number(let value)):
            return "blur(\(InspectCSS.pixels(value)))"
        default:
            return Self.plainText(raw)
        }
    }

    /// `(if (keyword? value) (d/name value) value)`, as `str` writes it.
    private static func plainText(_ raw: Raw) -> String? {
        switch raw {
        case .number(let value): InspectCSS.js(value)
        case .string(let text), .keyword(let text): text
        case .numbers(let values): values.map(InspectCSS.js).joined(separator: " ")
        default: nil
        }
    }

    private static func track(_ track: Object) -> String {
        let value = track.num("value") ?? 0
        switch track.str("type") {
        case "flex": return InspectCSS.js(InspectCSS.precision(value, 2)) + "fr"
        case "percent": return InspectCSS.js(InspectCSS.precision(value / 100 * 100, 2)) + "%"
        case "auto": return "auto"
        default: return InspectCSS.pixels(value)
        }
    }

    /// `format-shadow->css`: "inset 0px 2px 4px 0px #00000033".
    private func shadow(_ shadow: Object) -> String {
        let color = shadow.obj("color").map { color in
            Paint(color: color.str("color"), opacity: color.num("opacity"),
                  gradient: color.obj("gradient"), image: color.obj("image"))
        } ?? Paint()
        let numbers = ["offsetX", "offsetY", "blur", "spread"].map { key in
            (shadow.num(key).map(InspectCSS.js) ?? "") + "px"
        }
        return (shadow.str("style") == "inner-shadow" ? "inset " : "")
            + numbers.joined(separator: " ") + " " + (self.color(color) ?? "")
    }

    /// `format-color-value`: an image, a gradient, or the color in the chosen color space.
    func color(_ paint: Paint) -> String? {
        if let image = paint.image {
            let id = image.str("id") ?? ""
            let url = image.str("dataUri")
                ?? server.map { $0.appendingPathComponent("assets/by-file-media-id").appendingPathComponent(id).absoluteString }
                ?? "assets/by-file-media-id/\(id)"
            let opacity = paint.opacity ?? 1
            guard opacity != 1 else { return "url(\(url)) no-repeat center center / cover" }
            // CSS can't fade a background image: Penpot lays a white gradient over it.
            let veil: Object = ["type": "linear",
                                "stops": [["color": "#FFFFFF", "opacity": opacity],
                                          ["color": "#FFFFFF", "opacity": opacity]]]
            return "\(Self.gradient(veil)), url(\(url)) no-repeat center center / cover"
        }
        if let gradient = paint.gradient { return Self.gradient(gradient) }
        guard let hex = paint.color else { return nil }
        let opacity = paint.opacity ?? 1
        switch format {
        case .hex:
            return hex + Self.opacityHex(opacity).uppercased()
        case .rgba:
            let (r, g, b) = Self.rgb(hex)
            return "rgba(\(r), \(g), \(b), \(InspectCSS.formatNumber(opacity)))"
        case .hsla:
            let (h, s, l) = Self.hsl(Self.rgb(hex))
            return "hsla(\(Int(h)), \(InspectCSS.formatNumber(s * 100))%, \(InspectCSS.formatNumber(l * 100))%, \(InspectCSS.formatNumber(opacity)))"
        }
    }

    /// `uc/gradient->css`: always top to bottom or a circle, whatever the gradient's geometry.
    static func gradient(_ gradient: Object) -> String {
        let stops = gradient.objs("stops").map { stop -> String in
            let (r, g, b) = rgb(stop.str("color") ?? "")
            let opacity = stop.num("opacity").map(InspectCSS.js) ?? ""
            return "rgba(\(r), \(g), \(b), \(opacity)) \(InspectCSS.js((stop.num("offset") ?? 0) * 100))%"
        }.joined(separator: ",")
        return gradient.str("type") == "linear"
            ? "linear-gradient(to bottom, \(stops))"
            : "radial-gradient(circle, \(stops))"
    }

    /// `d/opacity-to-hex`: "ff" for 1.
    static func opacityHex(_ opacity: Double) -> String {
        let text = String(Int(InspectCSS.jsRound(opacity * 255)), radix: 16)
        return text.count < 2 ? "0" + text : text
    }

    /// `cc/hex->rgb`: `parseInt` of what follows the first character.
    static func rgb(_ hex: String) -> (Int, Int, Int) {
        let digits = hex.dropFirst().prefix { $0.isHexDigit }.prefix(15)
        guard let parsed = Int64(digits, radix: 16) else { return (0, 0, 0) }
        let value = Int32(truncatingIfNeeded: parsed)
        return (Int(value >> 16), Int((value >> 8) & 255), Int(value & 255))
    }

    /// `cc/rgb->hsl`: hue in degrees, saturation and lightness in 0…1.
    static func hsl(_ rgb: (Int, Int, Int)) -> (Double, Double, Double) {
        let r = Double(rgb.0) / 255, g = Double(rgb.1) / 255, b = Double(rgb.2) / 255
        let maximum = max(r, g, b), minimum = min(r, g, b)
        let l = (maximum + minimum) / 2
        var h = 0.0
        if maximum != minimum {
            if maximum == r { h = 60 * ((g - b) / (maximum - minimum)) }
            else if maximum == g { h = 120 + 60 * ((b - r) / (maximum - minimum)) }
            else { h = 240 + 60 * ((r - g) / (maximum - minimum)) }
        }
        let s = maximum == minimum ? 0 : (l <= 0.5 ? (maximum - minimum) / (2 * l) : (maximum - minimum) / (2 - 2 * l))
        return ((h + 360).truncatingRemainder(dividingBy: 360), s, l)
    }

    // MARK: Stylesheet (`get-shape-css-selector`)

    private static let wrapperProperties: [String] = [
        "flex-shrink", "margin-block-start", "margin-block-end", "margin-inline-start",
        "margin-inline-end", "max-height", "min-height", "max-width", "min-width", "align-self",
        "justify-self", "grid-column", "grid-row", "z-index", "top", "left", "position",
    ]

    func rule(_ shape: Object) -> String? {
        guard selrect(shape) != nil else { return nil }
        let selector = InspectCSS.selector(shape)
        let wrapper = hasWrapper(shape)
        let properties = wrapper
            ? InspectCSS.shapeProperties.filter { !Self.wrapperProperties.contains($0) }
            : InspectCSS.shapeProperties
        var parts = ["/* \(shape.str("name") ?? "") */"]
        if wrapper {
            var declarations = Self.wrapperProperties.compactMap { css($0, of: shape) }
            let (width, height) = wrapperSize(shape)
            declarations += [CSS(property: "width", value: InspectCSS.pixels(width)),
                             CSS(property: "height", value: InspectCSS.pixels(height))]
            if !isLayoutChild(shape) || !isAbsolute(shape) {
                declarations.append(CSS(property: "position", value: "relative"))
            }
            parts.append(".\(selector)-wrapper {\n\(lines(declarations))\n}")
            parts.append(".\(selector)-wrapper > * {\n  position: absolute;\n  left: 50%;\n  top: 50%;\n}")
        }
        if isSVGMarkup(shape), let bounds = objectBounds(shape), let box = selrect(shape) {
            let translate = "translate(\(InspectCSS.js(bounds.x - box.x))px,\(InspectCSS.js(bounds.y - box.y))px)"
            parts.append(".\(selector) > svg {\n  position: absolute;\n  top: 0px;\n  left: 0px;\n  transform: \(translate);\n}")
        }
        parts.append(".\(selector) {\n\(block(properties, of: shape))\n}")
        if isText(shape), let text = textCSS(shape, selector: selector) { parts.append(text) }
        return parts.joined(separator: "\n")
    }

    /// `gpo/parent-coords-bounds`: the wrapper's size, the shape's corners in its parent's axes.
    private func wrapperSize(_ shape: Object) -> (Double, Double) {
        let child = corners(shape)
        let parentCorners = parent(shape).map(corners) ?? []
        let origin = parentCorners.first ?? .zero
        var horizontal = CGVector(dx: 1, dy: 0), vertical = CGVector(dx: 0, dy: 1)
        if parentCorners.count >= 4 {
            horizontal = CGVector(dx: parentCorners[1].x - origin.x, dy: parentCorners[1].y - origin.y)
            vertical = CGVector(dx: parentCorners[3].x - origin.x, dy: parentCorners[3].y - origin.y)
        }
        func length(_ v: CGVector) -> Double { hypot(v.dx, v.dy) }
        func t(_ p: CGPoint, along v: CGVector) -> Double {
            let squared = v.dx * v.dx + v.dy * v.dy
            return squared == 0 ? 0 : ((p.x - origin.x) * v.dx + (p.y - origin.y) * v.dy) / squared
        }
        guard !child.isEmpty else { return (0.01, 0.01) }
        let th = child.map { t($0, along: horizontal) }, tv = child.map { t($0, along: vertical) }
        return (max(0.01, (th.max()! - th.min()!) * length(horizontal)),
                max(0.01, (tv.max()! - tv.min()!) * length(vertical)))
    }

    // MARK: Object bounds (`gsb/get-object-bounds`), for an SVG shape's `> svg` rule

    private struct Filter {
        let type: String
        let params: Object
    }

    private func filters(_ shape: Object) -> [Filter] {
        let shadows = shape.objs("shadow").filter { !$0.truthy("hidden") }
        var filters = shadows.filter { $0.str("style") == "drop-shadow" }.map { Filter(type: "drop-shadow", params: $0) }
        filters += shadows.filter { $0.str("style") == "inner-shadow" }.map { Filter(type: "inner-shadow", params: $0) }
        if let blur = shape.obj("blur"), !blur.truthy("hidden"), blur.str("type") == "layer-blur" {
            filters.append(Filter(type: "layer-blur", params: blur))
        }
        return filters
    }

    private func filterBounds(_ rect: Rect, _ filters: [Filter], blur: Double, ignoreShadows: Bool = false) -> Rect {
        var rects = [rect]
        if !ignoreShadows {
            for filter in filters where filter.type == "drop-shadow" {
                let ox = filter.params.num("offsetX") ?? 0, oy = filter.params.num("offsetY") ?? 0
                let spread = filter.params.num("spread") ?? 0, blur = filter.params.num("blur") ?? 0
                rects.append(Rect(x: min(rect.x, rect.x + ox - spread - blur - 5),
                                  y: min(rect.y, rect.y + oy - spread - blur - 5),
                                  width: rect.width + abs(ox) + spread * 2 + blur * 2 + 10,
                                  height: rect.height + abs(oy) + spread * 2 + blur * 2 + 10))
            }
        }
        let delta = blur * 2
        return (Rect.join(rects) ?? rect).grown(horizontal: delta, vertical: delta)
    }

    private func shapeFilterBounds(_ shape: Object) -> Rect? {
        if type(shape) == "svg-raw", shape.obj("content")?.str("tag") != "svg" { return selrect(shape) }
        let box = Rect.bounding(points(shape)) ?? selrect(shape)
        let blur = shape.obj("blur")?.num("value") ?? 0
        guard let box else { return nil }
        if shape.objs("shadow").isEmpty, blur == 0 { return box }
        return filterBounds(box, filters(shape), blur: blur)
    }

    /// `calculate-base-bounds`, ignoring the stroke margin as `get-object-bounds` does.
    private func baseBounds(_ shape: Object) -> Rect? {
        guard let bounds = shapeFilterBounds(shape) else { return nil }
        let shadows = shape.objs("shadow").filter { !$0.truthy("hidden") && ($0.str("style") ?? "drop-shadow") == "drop-shadow" }
        func extent(_ shadow: Object, offset key: String) -> Double {
            let offset: Double = abs(shadow.num(key) ?? 0)
            let spread: Double = shadow.num("spread") ?? 0
            let blur: Double = shadow.num("blur") ?? 0
            return offset + 2 * spread + 2 * blur + 10
        }
        let width = shadows.map { extent($0, offset: "offsetX") }.max() ?? 0
        let height = shadows.map { extent($0, offset: "offsetY") }.max() ?? 0
        return bounds.grown(horizontal: max(0, width).rounded(.up), vertical: max(0, height).rounded(.up))
    }

    private func objectBounds(_ shape: Object) -> Rect? {
        guard let base = baseBounds(shape) else { return nil }
        var rects = [base]
        let children = shape.strs("shapes")
        let leaf = children.isEmpty || shape.truthy("maskedGroup") || type(shape) == "bool"
            || (isFrame(shape) && !shape.truthy("showContent"))
        if !leaf {
            var pending = children
            var processed = Set<String>()
            while !pending.isEmpty {
                let id = pending.removeFirst()
                guard processed.insert(id).inserted, let child = objects[id] else { continue }
                if !child.truthy("hidden"), let bounds = baseBounds(child) { rects.append(bounds) }
                let descends = !child.truthy("hidden") && !child.strs("shapes").isEmpty
                    && (!isFrame(child) || child.truthy("showContent"))
                    && (type(child) != "group" || !child.truthy("maskedGroup"))
                if descends { pending = child.strs("shapes") + pending }
            }
        }
        let joined = Rect.join(rects) ?? base
        return filterBounds(joined, filters(shape), blur: shape.obj("blur")?.num("value") ?? 0)
    }

    // MARK: Text (`generate-text-css`, `app.main.ui.shapes.text.styles`)

    private func textCSS(_ shape: Object, selector: String) -> String? {
        guard let content = shape.obj("content") else { return nil }
        var rules: [String] = []
        var hasList = false
        func visit(_ node: Object, path: String?, index: Int) {
            let id = (path.map { $0 + "-" } ?? "") + (node.str("type") ?? "text") + "-\(index)"
            let properties: [(String, Any?)]
            switch node.str("type") {
            case "root": properties = Self.rootStyles(node)
            case "paragraph-set": properties = Self.paragraphSetStyles(shape)
            case "paragraph":
                var styles = Self.paragraphStyles(node)
                if Self.isList(node) { styles.append(("listStyleType", node.val("listStyleType"))) }
                properties = styles
            default: properties = Self.textStyles(shape, node)
            }
            rules.append(Self.nodeRule(".\(selector) .\(id)", properties))
            if node.str("type") == "paragraph", Self.isList(node) {
                hasList = true
                let span = node.objs("children").first ?? [:]
                var marker: [(String, Any?)] = [("fontSize", "\(Self.text(span.val("fontSize") ?? "14"))px")]
                if let color = Self.markerColor(shape, span) { marker.append(("color", color)) }
                rules.append(Self.nodeRule(".\(selector) .\(id)::marker", marker))
            }
            for (index, child) in node.objs("children").enumerated() { visit(child, path: id, index: index) }
        }
        visit(content, path: nil, index: 0)
        if hasList { rules.append(".\(selector) ul {\n  margin: 0;\n  padding: 0;\n}") }
        return rules.joined(separator: "\n")
    }

    private static func isList(_ node: Object) -> Bool { node.str("listStyleType") == "disc" }

    /// `format-js-styles`: camelCase keys as kebab-case declarations; nil values left out.
    private static func nodeRule(_ selector: String, _ properties: [(String, Any?)]) -> String {
        let lines = properties.compactMap { key, value -> String? in
            guard let value, !(value is NSNull) else { return nil }
            return "  \(kebab(key)): \(text(value));"
        }
        return "\(selector) {\n\(lines.joined(separator: "\n"))\n}"
    }

    private static func kebab(_ key: String) -> String {
        var out = ""
        for character in key {
            if character.isUppercase { out += "-" + character.lowercased() } else { out.append(character) }
        }
        return out
    }

    /// A JSON value as `str` writes it.
    private static func text(_ value: Any) -> String {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return InspectCSS.js(number.doubleValue)
        }
        return "\(value)"
    }

    private static func rootStyles(_ node: Object) -> [(String, Any?)] {
        var styles: [(String, Any?)] = [("height", nil), ("width", nil), ("display", "flex"),
                                        ("whiteSpace", "break-spaces")]
        switch node.str("verticalAlign") ?? "top" {
        case "top": styles.append(("alignItems", "flex-start"))
        case "center": styles.append(("alignItems", "center"))
        case "bottom": styles.append(("alignItems", "flex-end"))
        default: break
        }
        return styles
    }

    private static func paragraphSetStyles(_ shape: Object) -> [(String, Any?)] {
        [("display", "inline-flex"), ("flexDirection", "column"), ("justifyContent", "inherit"),
         ("minWidth", shape.str("growType") == "auto-width" ? nil : "100%"), ("marginRight", "1px"),
         ("verticalAlign", "top")]
    }

    private static func paragraphStyles(_ node: Object) -> [(String, Any?)] {
        var lineHeight = node.val("lineHeight")
        if lineHeight == nil || (lineHeight as? String) == "" { lineHeight = "1.2" }
        return [("fontSize", 0), ("lineHeight", lineHeight), ("margin", 0),
                ("textAlign", node.val("textAlign") ?? "start")]
    }

    private static func textColor(_ data: Object) -> (color: String?, gradient: Bool) {
        let fill = data.objs("fills").first
        let color = fill?.str("fillColor") ?? data.str("fillColor")
        let opacity = fill?.num("fillOpacity") ?? data.num("fillOpacity")
        if let gradient = fill?.obj("fillColorGradient") ?? data.obj("fillColorGradient") {
            return (Self.gradient(gradient), true)
        }
        guard let color, let opacity else { return (nil, false) }
        let (r, g, b) = rgb(color)
        return ("rgba(\(r), \(g), \(b), \(InspectCSS.js(opacity)))", false)
    }

    /// `generate-text-styles` for a run, in Penpot's key order.
    private static func textStyles(_ shape: Object, _ data: Object) -> [(String, Any?)] {
        let (color, gradient) = textColor(data)
        var styles: [(String, Any?)] = [
            ("textDecoration", data.val("textDecoration")),
            ("textTransform", data.val("textTransform")),
            ("fontSize", data.val("fontSize")),
            ("color", gradient ? "transparent" : color),
            ("background", gradient ? color : nil),
            ("caretColor", !gradient && color != nil ? color : "black"),
            ("overflowWrap", "initial"),
            ("lineBreak", "auto"),
            ("whiteSpace", shape.str("growType") == "auto-width" ? "pre" : "break-spaces"),
            ("textRendering", "geometricPrecision"),
        ]
        if data.str("lineHeight") == "0" {
            styles += [("display", "inline-block"), ("verticalAlign", "top")]
        }
        if let spacing = data.val("letterSpacing") as? String, !spacing.isEmpty {
            styles.append(("letterSpacing", spacing + "px"))
        }
        if let size = data.val("fontSize") as? String, !size.isEmpty,
           let index = styles.firstIndex(where: { $0.0 == "fontSize" }) {
            styles[index].1 = size + "px"
        }
        let fontID = data.str("fontId") ?? "sourcesanspro"
        if let family = data.str("fontFamily") ?? (fontID == "sourcesanspro" ? "sourcesanspro" : nil) {
            styles += [("fontFamily", "\"\(family)\""), ("fontStyle", data.val("fontStyle")),
                       ("fontWeight", data.val("fontWeight"))]
        }
        return styles
    }

    /// A bullet's color: its span's, the first stop of a gradient.
    private static func markerColor(_ shape: Object, _ span: Object) -> String? {
        if let gradient = span.objs("fills").first?.obj("fillColorGradient") ?? span.obj("fillColorGradient"),
           let stop = gradient.objs("stops").first {
            let (r, g, b) = rgb(stop.str("color") ?? "")
            return "rgba(\(r), \(g), \(b), \(stop.num("opacity").map(InspectCSS.js) ?? ""))"
        }
        return textStyles(shape, span).first { $0.0 == "color" }?.1 as? String
    }

    // MARK: Order (`ctst/sort-z-index`)

    private func parentsWithIndex(_ id: String) -> (parents: [String], index: [String: Int]) {
        var parents: [String] = []
        var index: [String: Int] = [:]
        var current = id
        while let parentID = objects[current]?.str("parentId"), parentID != current,
              let parent = objects[parentID], !parents.contains(parentID) {
            parents.append(parentID)
            index[parentID] = parent.strs("shapes").firstIndex(of: current)
            current = parentID
        }
        return (parents, index)
    }

    /// The shapes with the topmost sibling first, a parent before its children; in a layout,
    /// by z-index, then in the layout's order.
    func sortedByZIndex(_ ids: [String]) -> [String] {
        let chains = Dictionary(ids.map { ($0, parentsWithIndex($0)) }, uniquingKeysWith: { first, _ in first })
        func isOver(_ a: String, _ b: String) -> Bool {
            let chainA = chains[a] ?? ([], [:]), chainB = chains[b] ?? ([], [:])
            let setB = Set([b] + chainB.parents)
            let base = ([a] + chainA.parents).first(where: setB.contains) ?? InspectCSS.rootID
            if base == a { return false }
            if base == b { return true }
            let indexA = chainA.index[base] ?? -1, indexB = chainB.index[base] ?? -1
            let layered = isAnyLayout(objects[base])
            var zA = 0.0, zB = 0.0
            if layered, let shapes = objects[base]?.strs("shapes") {
                func z(_ index: Int) -> Double {
                    guard shapes.indices.contains(index) else { return 0 }
                    return objects[shapes[index]]?.num("layoutItemZIndex") ?? 0
                }
                zA = z(indexA); zB = z(indexB)
            }
            if zA == zB { return layered ? indexA > indexB : indexA < indexB }
            return zA < zB
        }
        return ids.sorted { a, b in a != b && !isOver(a, b) }
    }
}

// MARK: - JSON

private extension Dictionary where Key == String, Value == Any {
    /// The value, with JSON's null as nil.
    func val(_ key: String) -> Any? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        return value
    }

    func str(_ key: String) -> String? { val(key) as? String }

    /// A number (not a boolean).
    func num(_ key: String) -> Double? {
        guard let number = val(key) as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    func obj(_ key: String) -> [String: Any]? { val(key) as? [String: Any] }
    func arr(_ key: String) -> [Any]? { val(key) as? [Any] }
    func objs(_ key: String) -> [[String: Any]] { arr(key)?.compactMap { $0 as? [String: Any] } ?? [] }
    func strs(_ key: String) -> [String] { arr(key)?.compactMap { $0 as? String } ?? [] }

    /// `(true? x)`.
    func isTrue(_ key: String) -> Bool {
        guard let number = val(key) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    /// Clojure's truthiness: present and not false.
    func truthy(_ key: String) -> Bool {
        guard let value = val(key) else { return false }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        return true
    }
}
