import CoreGraphics
import Foundation

/// One board's shapes for the Inspect mode, Penpot's view-mode "Inspect" tab
/// (`ui/inspect/*`), read from the page data the board is drawn from
/// (``LocalBoardRenderer/page(of:using:)``).
///
/// Coordinates are the canvas', as in the page data: the board's rect is its `selrect`.
struct InspectBoard {
    typealias Object = [String: Any]

    let page: PenpotSVG.Page
    let boardID: String
    /// The board's rect on the canvas.
    let rect: CGRect

    var objects: [String: Object] { page.objects }

    init?(page: PenpotSVG.Page, boardID: String) {
        guard let board = page.objects[boardID] else { return nil }
        self.page = page
        self.boardID = boardID
        rect = Self.selrect(board)
    }

    func shape(_ id: String) -> Object? { objects[id] }

    func name(_ id: String) -> String { objects[id]?["name"] as? String ?? "" }

    func type(_ id: String) -> String { objects[id]?["type"] as? String ?? "" }

    // MARK: - Picking

    /// The innermost visible shape under `point` (canvas coordinates), the one Penpot's
    /// inspect hovers there: every shape handles the pointer itself, so the deepest one
    /// under it wins, the topmost first. A group is only the sum of its children; a board
    /// is picked where none of its children is, and clips them when it clips its content.
    func shape(at point: CGPoint) -> String? {
        pick(boardID, point) ?? (rect.contains(point) ? boardID : nil)
    }

    private func pick(_ id: String, _ point: CGPoint) -> String? {
        guard let shape = objects[id], shape["hidden"] as? Bool != true else { return nil }
        let children = children(of: id)
        switch shape["type"] as? String {
        case "frame":
            let inside = contains(id, point)
            // `showContent` is Penpot's "clip content" switched off.
            let clips = shape["showContent"] as? Bool != true
            if inside || !clips {
                for child in children.reversed() {
                    if let hit = pick(child, point) { return hit }
                }
            }
            return inside ? id : nil
        case "group":
            var members = children
            if shape["maskedGroup"] as? Bool == true, let mask = members.first {
                // The mask is the bottom child; the rest only shows inside it.
                guard contains(mask, point) else { return nil }
                members.removeFirst()
            }
            for child in members.reversed() {
                if let hit = pick(child, point) { return hit }
            }
            return nil
        default:
            // Paths, rects, ellipses, texts, images, boolean groups and imported SVG are
            // drawn as one element each.
            return contains(id, point) ? id : nil
        }
    }

    /// The shape's children, the bottom one first (Penpot's `shapes`).
    func children(of id: String) -> [String] {
        (objects[id]?["shapes"] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    /// The shapes from the board down to `id`, both included.
    func path(to id: String) -> [String] {
        var path = [id]
        var current = id
        while current != boardID, let parent = objects[current]?["parentId"] as? String,
              parent != current, parent != PenpotSVG.rootID, path.count < 200 {
            path.insert(parent, at: 0)
            current = parent
        }
        return path.first == boardID ? path : [boardID] + path.filter { $0 != boardID }
    }

    // MARK: - Geometry

    /// The shape's four corners on the canvas (`points`, rotation included), else its rect.
    func outline(_ id: String) -> [CGPoint] {
        guard let shape = objects[id] else { return [] }
        let points = (shape["points"] as? [Any])?.compactMap { item -> CGPoint? in
            guard let point = item as? Object, let x = Self.number(point["x"]),
                  let y = Self.number(point["y"]) else { return nil }
            return CGPoint(x: x, y: y)
        } ?? []
        if points.count == 4 { return points }
        let rect = Self.selrect(shape)
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    /// The box around ``outline(_:)``: what Penpot's selection and its distances measure
    /// (`gsh/shapes->rect`).
    func bounds(_ id: String) -> CGRect {
        let points = outline(id)
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { box, point in
            box.union(CGRect(origin: point, size: .zero))
        }
    }

    /// The shape's own width and height, unrotated: what its size label shows.
    func size(_ id: String) -> CGSize {
        guard let shape = objects[id] else { return .zero }
        return Self.selrect(shape).size
    }

    private func contains(_ id: String, _ point: CGPoint) -> Bool {
        let corners = outline(id)
        guard corners.count >= 3 else { return false }
        if type(id) == "circle", let shape = objects[id] {
            // An ellipse: test in its own, unrotated coordinates.
            let rect = Self.selrect(shape)
            let local = Self.unrotate(point, shape: shape, around: CGPoint(x: rect.midX, y: rect.midY))
            guard rect.width > 0, rect.height > 0 else { return false }
            let dx = (local.x - rect.midX) / (rect.width / 2)
            let dy = (local.y - rect.midY) / (rect.height / 2)
            return dx * dx + dy * dy <= 1
        }
        // Even-odd ray casting; the four corners are convex, so this is exact.
        var inside = false
        var j = corners.count - 1
        for i in corners.indices {
            let (a, b) = (corners[i], corners[j])
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// `point` taken back through the shape's `transform` around its centre.
    private static func unrotate(_ point: CGPoint, shape: Object, around center: CGPoint) -> CGPoint {
        guard let t = shape["transformInverse"] as? Object,
              let a = number(t["a"]), let b = number(t["b"]),
              let c = number(t["c"]), let d = number(t["d"]) else { return point }
        let x = point.x - center.x, y = point.y - center.y
        return CGPoint(x: center.x + a * x + c * y, y: center.y + b * x + d * y)
    }

    static func selrect(_ shape: Object) -> CGRect {
        if let sel = shape["selrect"] as? Object,
           let x = number(sel["x"]), let y = number(sel["y"]),
           let w = number(sel["width"]), let h = number(sel["height"]) {
            return CGRect(x: x, y: y, width: w, height: h)
        }
        let x = number(shape["x"]) ?? 0, y = number(shape["y"]) ?? 0
        return CGRect(x: x, y: y, width: number(shape["width"]) ?? 0,
                      height: number(shape["height"]) ?? 0)
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let text as String: Double(text)
        default: nil
        }
    }

    // MARK: - Attributes

    /// A fill or a stroke's paint, as Penpot's `color-row` shows it.
    struct Paint: Hashable {
        enum Kind: Hashable {
            /// `#rrggbb`.
            case color(String)
            case linearGradient([Stop])
            case radialGradient([Stop])
            /// An image fill: its file name and size.
            case image(name: String, width: Double, height: Double)
        }

        struct Stop: Hashable {
            let color: String
            let opacity: Double
            let offset: Double
        }

        let kind: Kind
        let opacity: Double
    }

    static func paint(_ item: Object, prefix: String) -> Paint? {
        let opacity = number(item["\(prefix)Opacity"]) ?? 1
        if let gradient = item["\(prefix)ColorGradient"] as? Object {
            let stops = (gradient["stops"] as? [Any] ?? []).compactMap { stop -> Paint.Stop? in
                guard let stop = stop as? Object, let color = stop["color"] as? String else { return nil }
                return .init(color: color, opacity: number(stop["opacity"]) ?? 1,
                             offset: number(stop["offset"]) ?? 0)
            }
            let radial = gradient["type"] as? String == "radial"
            return Paint(kind: radial ? .radialGradient(stops) : .linearGradient(stops), opacity: opacity)
        }
        if let image = item["\(prefix)Image"] as? Object {
            return Paint(kind: .image(name: image["name"] as? String ?? "",
                                      width: number(image["width"]) ?? 0,
                                      height: number(image["height"]) ?? 0),
                         opacity: opacity)
        }
        if let color = item["\(prefix)Color"] as? String {
            return Paint(kind: .color(color), opacity: opacity)
        }
        return nil
    }

    /// A fill or a stroke, and its JSON for ``InspectCSS``.
    struct Layer {
        let paint: Paint
        let raw: Object
    }

    /// The shape's fills, the topmost first as Penpot lists them. A text's fills belong to
    /// its runs (``TextRun``).
    func fills(_ id: String) -> [Layer] {
        guard let shape = objects[id], type(id) != "text" else { return [] }
        return (shape["fills"] as? [Any] ?? []).compactMap { item in
            guard let fill = item as? Object, let paint = Self.paint(fill, prefix: "fill") else { return nil }
            return Layer(paint: paint, raw: fill)
        }
    }

    typealias Stroke = Layer

    func strokes(_ id: String) -> [Stroke] {
        (objects[id]?["strokes"] as? [Any] ?? []).compactMap { item in
            guard let stroke = item as? Object, let paint = Self.paint(stroke, prefix: "stroke") else { return nil }
            return Stroke(paint: paint, raw: stroke)
        }
    }

    struct Shadow {
        let inner: Bool
        let offsetX: Double
        let offsetY: Double
        let blur: Double
        let spread: Double
        let paint: Paint
    }

    func shadows(_ id: String) -> [Shadow] {
        (objects[id]?["shadow"] as? [Any] ?? []).compactMap { item in
            guard let shadow = item as? Object, shadow["hidden"] as? Bool != true,
                  let color = shadow["color"] as? Object,
                  let paint = Self.colorPaint(color) else { return nil }
            return Shadow(inner: shadow["style"] as? String == "inner-shadow",
                          offsetX: Self.number(shadow["offsetX"]) ?? 0,
                          offsetY: Self.number(shadow["offsetY"]) ?? 0,
                          blur: Self.number(shadow["blur"]) ?? 0,
                          spread: Self.number(shadow["spread"]) ?? 0,
                          paint: paint)
        }
    }

    /// A shadow's `{color, opacity}`.
    private static func colorPaint(_ color: Object) -> Paint? {
        guard let hex = color["color"] as? String else { return nil }
        return Paint(kind: .color(hex), opacity: number(color["opacity"]) ?? 1)
    }

    /// The layer blur's value, and the background blur's (WebGL renderer only).
    func blurs(_ id: String) -> (layer: Double?, background: Double?) {
        guard let shape = objects[id] else { return (nil, nil) }
        func value(_ key: String) -> Double? {
            guard let blur = shape[key] as? Object, blur["hidden"] as? Bool != true,
                  let value = Self.number(blur["value"]), value > 0 else { return nil }
            return value
        }
        return (value("blur"), value("backgroundBlur"))
    }

    // MARK: - Text

    /// A stretch of a text in one style, as Penpot's typography block lists them
    /// (`content->text+styles`, defaults from `get-default-text-attrs`).
    struct TextRun: Identifiable {
        let id: Int
        let text: String
        let fontName: String
        let fontFamily: String
        let fontStyle: String
        let fontWeight: String
        let fontSize: Double
        let lineHeight: Double
        let letterSpacing: Double
        let textDecoration: String
        let textTransform: String
        let fills: [Paint]
    }

    func textRuns(_ id: String) -> [TextRun] {
        guard type(id) == "text", let content = objects[id]?["content"] as? Object else { return [] }
        var runs: [(style: [String: String], fills: [Paint], text: String)] = []
        func walk(_ node: Object, inherited: [String: String]) {
            var style = inherited
            for key in Self.textStyleKeys {
                if let value = node[key] {
                    style[key] = (value as? String) ?? Self.number(value).map { Self.trim($0) } ?? style[key]
                }
            }
            if let text = node["text"] as? String {
                let fills = (node["fills"] as? [Any] ?? []).compactMap { ($0 as? Object).flatMap { Self.paint($0, prefix: "fill") } }
                if let last = runs.last, last.style == style, last.fills == fills {
                    runs[runs.count - 1].text += text
                } else {
                    runs.append((style, fills, text))
                }
                return
            }
            let children = (node["children"] as? [Any] ?? []).compactMap { $0 as? Object }
            for (index, child) in children.enumerated() {
                walk(child, inherited: style)
                // Paragraphs end in a line break, as in the text's content.
                if node["type"] as? String == "paragraph-set", index < children.count - 1, !runs.isEmpty {
                    runs[runs.count - 1].text += "\n"
                }
            }
        }
        walk(content, inherited: [:])
        return runs.enumerated().compactMap { index, run in
            guard !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let style = run.style
            let family = style["fontFamily"] ?? "sourcesanspro"
            let fontID = style["fontId"] ?? "sourcesanspro"
            let name = fontID == "sourcesanspro" || family == "sourcesanspro" ? "Source Sans Pro" : family
            return TextRun(id: index, text: run.text.trimmingCharacters(in: .whitespacesAndNewlines),
                           fontName: name, fontFamily: family,
                           fontStyle: style["fontStyle"] ?? "normal",
                           fontWeight: style["fontWeight"] ?? "400",
                           fontSize: Double(style["fontSize"] ?? "") ?? 14,
                           lineHeight: Double(style["lineHeight"] ?? "") ?? 1.2,
                           letterSpacing: Double(style["letterSpacing"] ?? "") ?? 0,
                           textDecoration: style["textDecoration"] ?? "none",
                           textTransform: style["textTransform"] ?? "none",
                           fills: run.fills.isEmpty ? [Paint(kind: .color("#000000"), opacity: 1)] : run.fills)
        }
    }

    private static let textStyleKeys = ["fontId", "fontFamily", "fontStyle", "fontWeight", "fontSize",
                                        "lineHeight", "letterSpacing", "textDecoration", "textTransform"]

    /// A number as Penpot's `fmt/format-number` writes it: at most two decimals, no
    /// trailing zeros.
    static func trim(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}
