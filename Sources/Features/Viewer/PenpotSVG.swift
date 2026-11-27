import CoreGraphics
import Foundation

/// A Penpot page (`get-page` JSON) as one static SVG document, for the on-device renderer
/// (``LocalBoardRenderer``).
///
/// Follows Penpot's classic SVG renderer (`frontend/src/app/main/render.cljs` `page-svg`
/// and `ui/shapes/*`): shape transforms, fills and fill patterns, gradients, strokes with
/// inner/outer alignment, shadows, layer and background blur, masks, board clipping and
/// imported SVG.
/// One deliberate difference: text is laid out from its content tree as HTML in a
/// `foreignObject`, the way Penpot's editor shows it, instead of being placed from the
/// stored `positionData`. Those positions can be stale (the exporter then clips text,
/// e.g. "Back Toke"), and `page-svg` draws nothing for text that has none.
///
/// Not covered yet: stroke end markers (arrows), per-run text gradients (the first stop's
/// color is used), radial gradients on paths (drawn unrotated) and id remapping inside
/// imported SVG defs.
enum PenpotSVG {
    struct Drawing {
        /// A complete HTML document: the SVG plus the CSS that loads its fonts.
        let html: String
        /// Canvas coordinates of the document's top-left corner; 1 CSS px is 1 canvas unit.
        let origin: CGPoint
        let size: CGSize
        /// Each root board's rect in canvas coordinates.
        let boards: [String: CGRect]
    }

    static let rootID = "00000000-0000-0000-0000-000000000000"

    /// "Ag" in a typography's font, black on transparent, as Penpot's assets panel shows a
    /// typography: its family, weight and style at the panel's size, not its own.
    static func typographySample(_ typography: LibraryTypography, server: URL, customFonts: [FontVariant]) -> Drawing {
        Writer(objects: [:], server: server, customFonts: customFonts)
            .textSample("Ag", fontID: typography.fontId, family: typography.fontFamily,
                        variantID: typography.fontVariantId, weight: typography.fontWeight,
                        style: typography.fontStyle, size: 32, box: CGSize(width: 64, height: 44))
    }

    /// An image of a file's library (an SVG most of the time) at its own size, for WebKit to
    /// draw: the app can't read an SVG itself.
    static func mediaDrawing(_ media: LibraryMedia, server: URL) -> Drawing {
        let width = max(media.width ?? 100, 1)
        let height = max(media.height ?? 100, 1)
        let html = "<!doctype html><html><head><meta charset=\"utf-8\"><style>html,body{margin:0;padding:0;background:transparent}"
            + "img{display:block;width:\(num(width))px;height:\(num(height))px}</style></head>"
            + "<body><img src=\"\(escape(media.url(server: server).absoluteString))\"></body></html>"
        return Drawing(html: html, origin: .zero, size: CGSize(width: width, height: height), boards: [:])
    }

    /// Shapes straight on the canvas, outside any board, that lie close together: drawn in
    /// one document, like a board, on the page canvas.
    struct Island: Sendable {
        /// ``islandPrefix`` and the id of its lowest shape.
        let id: String
        /// Its shapes, in paint order.
        let shapeIDs: [String]
        /// What they cover, strokes and effects included, in canvas coordinates.
        let bounds: CGRect
        /// Its place in the page's paint order: the index of its topmost shape among the
        /// root shapes (boards and loose shapes).
        let layer: Int
    }

    static let islandPrefix = "island-"

    /// Run in a loaded ``Page/layoutProbe(board:)``: every shape's box, relative to the
    /// board, as a JSON string `{id: [x, y, width, height]}`.
    static let layoutScript = """
        JSON.stringify(Object.fromEntries([...document.querySelectorAll('[data-id]')].map(e => {
          const r = e.getBoundingClientRect();
          return [e.dataset.id, [r.left + scrollX, r.top + scrollY, r.width, r.height]];
        })))
        """

    /// A parsed page, from which boards are drawn one document each: a document per board
    /// keeps WebKit's layout and `createPDF` small, where a whole design-system page as one
    /// document took seconds per board.
    final class Page: @unchecked Sendable {
        /// The page's shapes by id (`get-page` JSON), for the Inspect mode too.
        let objects: [String: [String: Any]]
        /// Whether a shape has a background blur, which needs the backdrop tracked.
        fileprivate let hasBackgroundBlur: Bool
        /// The shapes outside any board, see ``Island``.
        let islands: [Island]
        /// Each root shape's index in the page's paint order (0 is the bottom).
        let layers: [String: Int]
        private let islandsByID: [String: Island]
        let server: URL
        /// Team fonts the texts may use (`get-font-variants`), see ``customFontIDs``.
        var customFonts: [FontVariant] = []

        init(pageJSON: Data, server: URL) throws {
            objects = try parseObjects(pageJSON).objects
            hasBackgroundBlur = objects.values.contains { Writer.visibleBackgroundBlur($0) != nil }
            let rootIDs = objects[PenpotSVG.rootID]?.array("shapes") as? [String] ?? []
            layers = Dictionary(rootIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            islands = PenpotSVG.islands(rootIDs, objects: objects)
            islandsByID = Dictionary(islands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.server = server
        }

        /// The ids of custom team fonts (`custom-<uuid>`) the page's texts use.
        var customFontIDs: Set<String> {
            var ids = Set<String>()
            for shape in objects.values where shape.string("type") == "text" {
                forEachLeaf(shape.object("content")) { leaf in
                    if let id = leaf.string("fontId"), id.hasPrefix("custom-") { ids.insert(id) }
                }
            }
            return ids
        }

        /// The root board `id` alone, its document exactly the board's rect. `layout` holds
        /// shape rects measured by ``layoutProbe(board:)`` (canvas coordinates): the shapes
        /// are drawn there instead of at their stored positions and sizes.
        func drawing(board id: String, layout: [String: CGRect] = [:]) -> Drawing? {
            if let (boardID, fixedLayer) = Self.layer(id) {
                return drawing(layerOf: boardID, fixed: fixedLayer, layout: layout)
            }
            if let island = islandsByID[id] {
                return Writer(objects: objects, server: server, customFonts: customFonts,
                              tracksBackdrop: hasBackgroundBlur, layout: layout)
                    .document(ids: island.shapeIDs, bounds: island.bounds, boards: [:])
            }
            guard let shape = objects[id] else { return nil }
            // A component's main copy that is no board (the Assets view): the shape alone,
            // with what its strokes and shadows cover.
            guard shape.string("type") == "frame" else {
                let bounds = Writer.visualBounds(shape, objects: objects)
                guard bounds.width > 0, bounds.height > 0 else { return nil }
                return Writer(objects: objects, server: server, customFonts: customFonts,
                              tracksBackdrop: hasBackgroundBlur, layout: layout)
                    .document(ids: [id], bounds: bounds, boards: [:])
            }
            let rect = Writer.selrect(shape)
            guard rect.width > 0, rect.height > 0 else { return nil }
            return Writer(objects: objects, server: server, customFonts: customFonts,
                          documentBoard: id, tracksBackdrop: hasBackgroundBlur, layout: layout)
                .document(ids: [id], bounds: rect, boards: [id: rect])
        }

        /// The prototype player's layers of a board: `scroll-<id>` is the board without its
        /// shapes fixed when scrolling, `fixed-<id>` those shapes alone (transparent around
        /// them, on the board's rect). Penpot's viewer draws the fixed ones in a layer that
        /// doesn't scroll (`ui/viewer/interactions.cljs`).
        static let scrollLayerPrefix = "scroll-"
        static let fixedLayerPrefix = "fixed-"

        static func layer(_ id: String) -> (board: String, fixed: Bool)? {
            if id.hasPrefix(scrollLayerPrefix) { return (String(id.dropFirst(scrollLayerPrefix.count)), false) }
            if id.hasPrefix(fixedLayerPrefix) { return (String(id.dropFirst(fixedLayerPrefix.count)), true) }
            return nil
        }

        /// The board's shapes fixed when scrolling, as ``PrototypeModel/fixedShapes(onBoard:)``
        /// finds them: a frame's direct child with `fixedScroll`, the outermost ones.
        func fixedScrollIDs(board id: String) -> [String] {
            var result: [String] = []
            var stack = objects[id]?.array("shapes") as? [String] ?? []
            var visited: Set<String> = [id]
            while let next = stack.popLast() {
                guard visited.insert(next).inserted, let shape = objects[next], !shape.flag("hidden") else { continue }
                let parent = shape.string("parentId")
                if shape.flag("fixedScroll"), parent != nil, parent == shape.string("frameId"),
                   shape.string("frameId") != PenpotSVG.rootID {
                    result.append(next)
                } else {
                    stack += shape.array("shapes") as? [String] ?? []
                }
            }
            return result.sorted()
        }

        private func drawing(layerOf id: String, fixed: Bool, layout: [String: CGRect]) -> Drawing? {
            guard let shape = objects[id], shape.string("type") == "frame" else { return nil }
            let rect = Writer.selrect(shape)
            guard rect.width > 0, rect.height > 0 else { return nil }
            let fixedIDs = fixedScrollIDs(board: id)
            if fixed {
                return Writer(objects: objects, server: server, customFonts: customFonts,
                              documentBoard: id, tracksBackdrop: hasBackgroundBlur, layout: layout)
                    .document(ids: fixedIDs, bounds: rect, boards: [:])
            }
            // A fixed shape is a frame's direct child: dropping it from that frame's
            // children leaves the board without it.
            var trimmed = objects
            let dropped = Set(fixedIDs)
            for fixedID in fixedIDs {
                guard let parentID = objects[fixedID]?.string("parentId"), var parent = trimmed[parentID] else { continue }
                parent["shapes"] = (parent.array("shapes") as? [String] ?? []).filter { !dropped.contains($0) }
                trimmed[parentID] = parent
            }
            return Writer(objects: trimmed, server: server, customFonts: customFonts,
                          documentBoard: id, tracksBackdrop: hasBackgroundBlur, layout: layout)
                .document(ids: [id], bounds: rect, boards: [id: rect])
        }

        /// Whether the board's stored geometry may be stale: a text in it was never laid out
        /// by Penpot's editor (it has no `positionData`, e.g. in an imported file). Its stored
        /// size can be far off, and so can the flex layouts around it; the editor measures
        /// such texts when a page opens and reflows the layouts.
        func needsLayout(board id: String) -> Bool {
            let id = Self.layer(id)?.board ?? id
            var stack = islandsByID[id]?.shapeIDs ?? [id]
            while let next = stack.popLast() {
                guard let shape = objects[next], !shape.flag("hidden") else { continue }
                if shape.string("type") == "text", shape.objects("positionData").isEmpty { return true }
                stack += shape.array("shapes") as? [String] ?? []
            }
            return false
        }

        /// The board's layout as HTML for WebKit to measure (``layoutScript``): flex boards
        /// as CSS flexboxes (which Penpot's flex layout follows), texts with their fonts,
        /// everything else at its stored offset. See ``layout(measured:board:)``.
        func layoutProbe(board id: String) -> String? {
            guard let root = layoutRoot(id) else { return nil }
            return Writer(objects: objects, server: server, customFonts: customFonts).layoutProbe(board: root)
        }

        /// The board, or for an island a group holding its shapes.
        private func layoutRoot(_ id: String) -> JSON? {
            let id = Self.layer(id)?.board ?? id
            if let island = islandsByID[id] {
                let box = island.bounds
                return ["id": id, "type": "group", "shapes": island.shapeIDs,
                        "selrect": ["x": box.minX, "y": box.minY, "width": box.width, "height": box.height]]
            }
            guard let shape = objects[id], shape.string("type") == "frame" else { return nil }
            return shape
        }

        /// The rects ``layoutScript`` measured in a ``layoutProbe(board:)``, in canvas
        /// coordinates.
        func layout(measured json: String, board id: String) -> [String: CGRect] {
            guard let root = layoutRoot(id),
                  let measured = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [Double]]
            else { return [:] }
            let origin = Writer.selrect(root).origin
            return measured.compactMapValues { rect in
                guard rect.count == 4 else { return nil }
                return CGRect(x: origin.x + rect[0], y: origin.y + rect[1], width: rect[2], height: rect[3])
            }
        }

        /// The whole page, with some room around its outermost shapes.
        func drawing() -> Drawing {
            let rootChildren = objects[PenpotSVG.rootID]?.array("shapes") as? [String] ?? []
            var bounds = CGRect.null
            var boards: [String: CGRect] = [:]
            for id in rootChildren {
                guard let shape = objects[id], !shape.flag("hidden") else { continue }
                bounds = bounds.union(Writer.pointsBox(shape) ?? Writer.selrect(shape))
                if shape.string("type") == "frame" { boards[id] = Writer.selrect(shape) }
            }
            if bounds.isNull { bounds = CGRect(x: 0, y: 0, width: 1, height: 1) }
            return Writer(objects: objects, server: server, customFonts: customFonts,
                          tracksBackdrop: hasBackgroundBlur)
                .document(ids: rootChildren, bounds: bounds.insetBy(dx: -32, dy: -32).integral, boards: boards)
        }
    }

    fileprivate static func parseObjects(_ data: Data) throws -> (page: JSON, objects: [String: JSON]) {
        guard let page = try JSONSerialization.jsonObject(with: data) as? JSON,
              let objects = page["objects"] as? [String: JSON] else {
            throw PenpotError.invalidResponse
        }
        return (page, objects)
    }

    /// The root shapes that aren't boards, grouped into islands: shapes whose bounds come
    /// within ``islandGap`` of each other share one, unless a board they overlap lies
    /// between them in paint order (one is under it, the other over it). So an island is
    /// either under or over every board it overlaps, and its ``Island/layer`` places it.
    fileprivate static func islands(_ rootIDs: [String], objects: [String: JSON]) -> [Island] {
        var boards: [(index: Int, rect: CGRect)] = []
        var loose: [(id: String, index: Int, box: CGRect)] = []
        for (index, id) in rootIDs.enumerated() {
            guard let shape = objects[id], !shape.flag("hidden"), Writer.isValid(shape) else { continue }
            if shape.string("type") == "frame" {
                boards.append((index, Writer.selrect(shape)))
            } else {
                let box = Writer.visualBounds(shape, objects: objects)
                if box.width > 0 || box.height > 0 { loose.append((id, index, box)) }
            }
        }
        guard !loose.isEmpty else { return [] }

        var parent = Array(loose.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        // Sweep along x: only shapes whose spans come within the gap can join.
        let byX = loose.indices.sorted { loose[$0].box.minX < loose[$1].box.minX }
        for (position, i) in byX.enumerated() {
            let a = loose[i].box.insetBy(dx: -islandGap / 2, dy: -islandGap / 2)
            for j in byX[(position + 1)...] {
                if loose[j].box.minX - islandGap / 2 > a.maxX { break }
                let b = loose[j].box.insetBy(dx: -islandGap / 2, dy: -islandGap / 2)
                guard a.intersects(b) else { continue }
                let low = min(loose[i].index, loose[j].index), high = max(loose[i].index, loose[j].index)
                let separated = boards.contains { board in
                    board.index > low && board.index < high
                        && (board.rect.intersects(loose[i].box) || board.rect.intersects(loose[j].box))
                }
                if !separated { parent[find(i)] = find(j) }
            }
        }
        var members: [Int: [Int]] = [:]
        for i in loose.indices { members[find(i), default: []].append(i) }
        return members.values.map { group -> Island in
            let sorted = group.sorted { loose[$0].index < loose[$1].index }
            let bounds = sorted.reduce(CGRect.null) { $0.union(loose[$1].box) }.integral
            return Island(id: islandPrefix + loose[sorted[0]].id, shapeIDs: sorted.map { loose[$0].id },
                          bounds: bounds, layer: loose[sorted.last!].index)
        }.sorted { $0.layer < $1.layer }
    }

    /// Canvas units between shapes that still form one island.
    static let islandGap = 48.0

    fileprivate static func forEachLeaf(_ node: JSON?, _ body: (JSON) -> Void) {
        guard let node else { return }
        guard let children = node.array("children") as? [JSON] else {
            if node["text"] != nil { body(node) }
            return
        }
        for child in children { forEachLeaf(child, body) }
    }
}

fileprivate typealias JSON = [String: Any]

fileprivate extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
    func number(_ key: String) -> Double? {
        if let number = self[key] as? NSNumber { return number.doubleValue }
        if let string = self[key] as? String { return Double(string) }
        return nil
    }
    func object(_ key: String) -> JSON? { self[key] as? JSON }
    func array(_ key: String) -> [Any]? { self[key] as? [Any] }
    func objects(_ key: String) -> [JSON] { (self[key] as? [Any])?.compactMap { $0 as? JSON } ?? [] }
    func flag(_ key: String) -> Bool { (self[key] as? Bool) ?? false }
}

// MARK: - Formatting

/// A number as SVG wants it: at most 4 decimals, no trailing zeros, never NaN.
fileprivate func num(_ value: Double) -> String {
    guard value.isFinite else { return "0" }
    if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
    var text = String(format: "%.4f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text == "-0" ? "0" : text
}

fileprivate func escape(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.count)
    for character in text {
        switch character {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&#39;"
        default: out.append(character)
        }
    }
    return out
}

/// `"#rrggbb"` + opacity → `rgba(r,g,b,a)`.
fileprivate func rgba(_ hex: String, _ opacity: Double) -> String {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard digits.count >= 6, let value = UInt32(digits.prefix(6), radix: 16) else {
        return "rgba(0,0,0,\(num(opacity)))"
    }
    return "rgba(\(value >> 16 & 0xff),\(value >> 8 & 0xff),\(value & 0xff),\(num(opacity)))"
}

/// camelCase → kebab-case, the JSON writer's camelising undone (`strokeWidth` →
/// `stroke-width`). SVG's natively camelCase attributes keep their case.
fileprivate func svgName(_ name: String) -> String {
    switch name {
    case "className": return "class"
    case "xlinkHref": return "href"
    default: break
    }
    if nativeCamelAttributes.contains(name) { return name }
    var out = ""
    for character in name {
        if character.isUppercase {
            out += "-" + character.lowercased()
        } else {
            out.append(character)
        }
    }
    return out
}

fileprivate let nativeCamelAttributes: Set<String> = [
    "viewBox", "preserveAspectRatio", "gradientTransform", "gradientUnits", "patternUnits",
    "patternContentUnits", "patternTransform", "clipPathUnits", "maskUnits", "maskContentUnits",
    "filterUnits", "primitiveUnits", "stdDeviation", "textLength", "lengthAdjust", "spreadMethod",
    "markerWidth", "markerHeight", "markerUnits", "refX", "refY", "numOctaves", "baseFrequency",
    "kernelMatrix", "kernelUnitLength", "tableValues", "surfaceScale", "specularExponent",
    "specularConstant", "diffuseConstant", "pointsAtX", "pointsAtY", "pointsAtZ",
    "limitingConeAngle", "startOffset", "xChannelSelector", "yChannelSelector", "edgeMode",
    "targetX", "targetY", "preserveAlpha", "pathLength", "attributeName", "repeatCount",
]

fileprivate let svgTags: Set<String> = [
    "svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text",
    "tspan", "textPath", "defs", "linearGradient", "radialGradient", "stop", "clipPath", "mask",
    "pattern", "use", "symbol", "image", "filter", "marker", "style", "title", "desc", "switch",
    "feBlend", "feColorMatrix", "feComponentTransfer", "feComposite", "feConvolveMatrix",
    "feDiffuseLighting", "feDisplacementMap", "feDistantLight", "feDropShadow", "feFlood",
    "feFuncA", "feFuncB", "feFuncG", "feFuncR", "feGaussianBlur", "feImage", "feMerge",
    "feMergeNode", "feMorphology", "feOffset", "fePointLight", "feSpecularLighting",
    "feSpotLight", "feTile", "feTurbulence",
]

fileprivate let graphicTags: Set<String> = [
    "svg", "circle", "ellipse", "image", "line", "path", "polygon", "polyline", "rect", "symbol",
    "text", "textPath", "use",
]

// MARK: - Writer

private final class Writer {
    let objects: [String: JSON]
    let server: URL
    let customFonts: [FontVariant]
    /// The board whose rect is the whole document, if any.
    let documentBoard: String?
    private let tracksBackdrop: Bool
    /// Everything written so far under the shape being written, as standalone markup: what
    /// a background blur shows through (``backgroundBlur(_:)``).
    private var backdrop = ""
    private var counter = 0
    /// Font faces the texts use, as `@font-face` rules (local and team fonts).
    private var fontFaces = Set<String>()
    /// Google fonts by family, with the variant ids used.
    private var googleFonts: [String: Set<String>] = [:]
    /// The nearest imported-SVG root, which scopes `<style>` elements inside it.
    private var svgRootStack: [String] = []

    /// How far each measured shape moved from its stored position (``PenpotSVG/Page/layout(measured:board:)``).
    private let moves: [String: CGPoint]
    /// The move of the shape being written, which its children's moves are relative to.
    private var currentMove = CGPoint.zero

    init(objects: [String: JSON], server: URL, customFonts: [FontVariant], documentBoard: String? = nil,
         tracksBackdrop: Bool = false, layout: [String: CGRect] = [:]) {
        var objects = objects
        var moves: [String: CGPoint] = [:]
        for (id, measured) in layout {
            guard var shape = objects[id] else { continue }
            let stored = Self.layoutRect(shape)
            moves[id] = CGPoint(x: ((measured.minX - stored.minX) * 100).rounded() / 100,
                                y: ((measured.minY - stored.minY) * 100).rounded() / 100)
            // A text takes its measured size, a board the size its layout gives it. The
            // shape stays at its stored origin: the move is a translation around it.
            let type = shape.string("type")
            guard type == "text" || type == "frame", id != documentBoard, Self.transform(shape) == nil,
                  abs(measured.width - stored.width) > 0.01 || abs(measured.height - stored.height) > 0.01
            else { continue }
            shape["selrect"] = ["x": stored.minX, "y": stored.minY, "width": measured.width, "height": measured.height]
            objects[id] = shape
        }
        self.objects = objects
        self.moves = moves
        self.server = server
        self.customFonts = customFonts
        self.documentBoard = documentBoard
        self.tracksBackdrop = tracksBackdrop
    }

    private func nextRID() -> String {
        counter += 1
        return "r\(counter)"
    }

    private var base: String {
        var text = server.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    // MARK: Document

    /// The shapes `ids` as one document showing `bounds` (canvas units).
    func document(ids: [String], bounds: CGRect, boards: [String: CGRect]) -> PenpotSVG.Drawing {
        let body = renderChildren(ids)
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" \
            width="\(num(bounds.width))" height="\(num(bounds.height))" \
            viewBox="\(num(bounds.minX)) \(num(bounds.minY)) \(num(bounds.width)) \(num(bounds.height))" \
            fill="none">\(body)</svg>
            """
        let html = "<!doctype html><html><head>\(head())</head><body>\(svg)</body></html>"
        return PenpotSVG.Drawing(html: html, origin: bounds.origin, size: bounds.size, boards: boards)
    }

    /// `text` alone in one font, centred in `box`: a typography's sample.
    func textSample(_ text: String, fontID: String, family: String, variantID: String, weight: String,
                    style: String, size: Double, box: CGSize) -> PenpotSVG.Drawing {
        registerFont(fontID: fontID, family: family, variantID: variantID, weight: weight, style: style)
        let family = family.replacingOccurrences(of: "'", with: "")
        let div = "<div style=\"width:\(num(box.width))px;height:\(num(box.height))px;display:flex;"
            + "align-items:center;justify-content:center;white-space:nowrap;color:#000;line-height:1;"
            + "font-family:'\(escape(family))',sourcesanspro,sans-serif;font-weight:\(escape(weight));"
            + "font-style:\(escape(style));font-size:\(num(size))px\">\(escape(text))</div>"
        let html = "<!doctype html><html><head>\(head())</head><body>\(div)</body></html>"
        return PenpotSVG.Drawing(html: html, origin: .zero, size: box, boards: [:])
    }

    /// The document head: base styles and the fonts the texts written so far use.
    private func head() -> String {
        var head = "<meta charset=\"utf-8\"><style>html,body{margin:0;padding:0;background:transparent}"
        head += "svg{display:block;overflow:visible}"
        head += ".text-node{background-clip:text;-webkit-background-clip:text}"
        head += fontFaces.sorted().joined() + "</style>"
        for (family, variants) in googleFonts.sorted(by: { $0.key < $1.key }) {
            let familyParam = family.replacingOccurrences(of: " ", with: "+")
            let query = "\(familyParam):\(variants.sorted().joined(separator: ","))"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? familyParam
            head += "<link rel=\"stylesheet\" href=\"\(base)/internal/gfonts/css?family=\(query)&amp;display=block\">"
        }
        return head
    }

    // MARK: Dispatch

    private func render(_ id: String, stripEffects: Bool = false) -> String {
        guard let shape = objects[id], !shape.flag("hidden"), Self.isValid(shape) else { return "" }
        // A shape the layout moved is translated as a whole, children included; theirs
        // are relative to it.
        let parentMove = currentMove
        let move = moves[id] ?? parentMove
        currentMove = move
        defer { currentMove = parentMove }
        let glass = stripEffects ? "" : backgroundBlur(shape)
        let markup: String
        switch shape.string("type") {
        case "frame": markup = glass + frame(shape, stripEffects: stripEffects)
        case "group": markup = glass + group(shape, stripEffects: stripEffects)
        case "text": markup = text(shape, stripEffects: stripEffects)
        case "svg-raw": markup = svgRaw(shape)
        case "rect", "circle", "path", "bool", "image": markup = glass + basic(shape, stripEffects: stripEffects)
        default: markup = ""
        }
        let dx = move.x - parentMove.x, dy = move.y - parentMove.y
        guard !markup.isEmpty, abs(dx) >= 0.01 || abs(dy) >= 0.01 else { return markup }
        return "<g transform=\"translate(\(num(dx)),\(num(dy)))\">\(markup)</g>"
    }

    /// `ids` in paint order, each written over the backdrop so far plus `base` (the
    /// parent's own fills) and the siblings before it.
    private func renderChildren(_ ids: [String], over base: String = "") -> String {
        guard tracksBackdrop else { return ids.map { render($0) }.joined() }
        let saved = backdrop
        defer { backdrop = saved }
        backdrop += base
        var out = ""
        for id in ids {
            let markup = render(id)
            out += markup
            backdrop += markup
        }
        return out
    }

    /// Children in paint order: `shapes[0]` first. Flex and grid boards sort by z-index.
    private func children(of shape: JSON) -> [String] {
        let ids = shape.array("shapes") as? [String] ?? []
        guard shape.string("type") == "frame",
              let layout = shape.string("layout"), layout == "flex" || layout == "grid" else { return ids }
        let reversed = ["row-reverse", "column-reverse"].contains(shape.string("layoutFlexDir") ?? "")
        return ids.enumerated().sorted { lhs, rhs in
            let lz = objects[lhs.element]?.number("layoutItemZIndex") ?? 0
            let rz = objects[rhs.element]?.number("layoutItemZIndex") ?? 0
            if lz != rz { return lz < rz }
            return reversed ? lhs.offset < rhs.offset : lhs.offset > rhs.offset
        }.map(\.element)
    }

    // MARK: Geometry

    static func isValid(_ shape: JSON) -> Bool {
        let rect = selrect(shape)
        return rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
    }

    static func selrect(_ shape: JSON) -> CGRect {
        if let sel = shape.object("selrect"), let x = sel.number("x"), let y = sel.number("y"),
           let w = sel.number("width"), let h = sel.number("height") {
            return CGRect(x: x, y: y, width: w, height: h)
        }
        return CGRect(x: shape.number("x") ?? 0, y: shape.number("y") ?? 0,
                      width: shape.number("width") ?? 0, height: shape.number("height") ?? 0)
    }

    static func pointsBox(_ shape: JSON) -> CGRect? {
        let points = shape.objects("points").compactMap { point -> CGPoint? in
            guard let x = point.number("x"), let y = point.number("y") else { return nil }
            return CGPoint(x: x, y: y)
        }
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// What the shape paints on: its outline's box (a group's spans its children) grown by
    /// its outer strokes, drop shadows and layer blur.
    static func visualBounds(_ shape: JSON, objects: [String: JSON]) -> CGRect {
        var box = pointsBox(shape) ?? selrect(shape)
        if shape.string("type") == "group" {
            for child in (shape.array("shapes") as? [String] ?? []).compactMap({ objects[$0] })
            where !child.flag("hidden") && isValid(child) {
                box = box.union(visualBounds(child, objects: objects))
            }
        }
        var margin = 1.0
        for stroke in shape.objects("strokes") {
            let width = stroke.number("strokeWidth") ?? 1
            switch stroke.string("strokeAlignment") {
            case "inner": break
            case "outer": margin = max(margin, width + 1)
            default: margin = max(margin, width / 2 + 1)
            }
        }
        for shadow in shape.objects("shadow") where !shadow.flag("hidden") && shadow.string("style") != "inner-shadow" {
            let offset = max(abs(shadow.number("offsetX") ?? 0), abs(shadow.number("offsetY") ?? 0))
            margin = max(margin, offset + 2 * (shadow.number("blur") ?? 0) + (shadow.number("spread") ?? 0))
        }
        if let blur = shape.object("blur"), !blur.flag("hidden") { margin = max(margin, 3 * (blur.number("value") ?? 0)) }
        return box.insetBy(dx: -margin, dy: -margin)
    }

    /// The box a layout places: the selrect, or for a transformed shape its outline's box.
    static func layoutRect(_ shape: JSON) -> CGRect {
        transform(shape) == nil ? selrect(shape) : (pointsBox(shape) ?? selrect(shape))
    }

    /// `T(center) · transform · T(-center)` as an SVG `matrix(…)`, or `nil` for none.
    private static func transform(_ shape: JSON) -> String? {
        guard let t = shape.object("transform"), let a = t.number("a"), let b = t.number("b"),
              let c = t.number("c"), let d = t.number("d") else { return nil }
        let e = t.number("e") ?? 0, f = t.number("f") ?? 0
        if a == 1, b == 0, c == 0, d == 1, e == 0, f == 0 { return nil }
        let rect = selrect(shape)
        let cx = rect.midX, cy = rect.midY
        let tx = cx - a * cx - c * cy + e
        let ty = cy - b * cx - d * cy + f
        return "matrix(\(num(a)),\(num(b)),\(num(c)),\(num(d)),\(num(tx)),\(num(ty)))"
    }

    private static func transformAttribute(_ shape: JSON) -> String {
        transform(shape).map { " transform=\"\($0)\"" } ?? ""
    }

    /// The shape's geometry element (`<rect>`, corner path, `<ellipse>` or `<path>`) with
    /// `attributes` appended; `withTransform` false for elements used inside a transformed g.
    private func geometry(_ shape: JSON, attributes: String, withTransform: Bool = true) -> String {
        let rect = Self.selrect(shape)
        let transform = withTransform ? Self.transformAttribute(shape) : ""
        switch shape.string("type") {
        case "path", "bool":
            let d = shape.string("content") ?? ""
            return "<path d=\"\(escape(d))\"\(attributes)/>"
        case "circle":
            return "<ellipse cx=\"\(num(rect.midX))\" cy=\"\(num(rect.midY))\" rx=\"\(num(rect.width / 2))\" ry=\"\(num(rect.height / 2))\"\(transform)\(attributes)/>"
        default:
            let radii = ["r1", "r2", "r3", "r4"].map { shape.number($0) ?? 0 }
            if radii.allSatisfy({ $0 == radii[0] }) {
                let r = Self.fixRadius(radii[0], rect)
                let corner = r > 0 ? " rx=\"\(num(r))\" ry=\"\(num(r))\"" : ""
                return "<rect x=\"\(num(rect.minX))\" y=\"\(num(rect.minY))\" width=\"\(num(rect.width))\" height=\"\(num(rect.height))\"\(corner)\(transform)\(attributes)/>"
            }
            return "<path d=\"\(Self.cornerPath(rect, radii))\"\(transform)\(attributes)/>"
        }
    }

    private static func fixRadius(_ r: Double, _ rect: CGRect) -> Double {
        guard r > 0.001 else { return 0 }
        return r * min(1, rect.width / (2 * r), rect.height / (2 * r))
    }

    private static func cornerPath(_ rect: CGRect, _ radii: [Double]) -> String {
        let w = rect.width, h = rect.height
        var r = radii
        let sums = [r[0] + r[1], r[1] + r[2], r[2] + r[3], r[3] + r[0]]
        let limits = [w / max(sums[0], 0.0001), h / max(sums[1], 0.0001),
                      w / max(sums[2], 0.0001), h / max(sums[3], 0.0001)]
        let factor = min(1, limits.min() ?? 1)
        r = r.map { $0 * factor }
        let (r1, r2, r3, r4) = (r[0], r[1], r[2], r[3])
        return "M\(num(rect.minX + r1)),\(num(rect.minY)) h\(num(w - r1 - r2)) "
            + "a\(num(r2)),\(num(r2)) 0 0 1 \(num(r2)),\(num(r2)) v\(num(h - r2 - r3)) "
            + "a\(num(r3)),\(num(r3)) 0 0 1 \(num(-r3)),\(num(r3)) h\(num(-(w - r3 - r4))) "
            + "a\(num(r4)),\(num(r4)) 0 0 1 \(num(-r4)),\(num(-r4)) v\(num(-(h - r4 - r1))) "
            + "a\(num(r1)),\(num(r1)) 0 0 1 \(num(r1)),\(num(-r1)) z"
    }

    // MARK: Wrapper

    private static func wrapperStyle(_ shape: JSON, withOpacity: Bool = true) -> String {
        var style = ""
        if withOpacity, let opacity = shape.number("opacity"), opacity < 1 { style += "opacity:\(num(opacity));" }
        if let blend = shape.string("blendMode"), blend != "normal" { style += "mix-blend-mode:\(blend);" }
        return style.isEmpty ? "" : " style=\"\(style)\""
    }

    // MARK: Basic shapes

    private func basic(_ shape: JSON, stripEffects: Bool) -> String {
        guard let id = shape.string("id") else { return "" }
        let rid = nextRID()
        let type = shape.string("type") ?? ""
        let rect = Self.selrect(shape)
        let fill = fillPaint(shape, rid: rid, box: rect,
                             patternTransform: type == "path" || type == "bool" ? Self.transform(shape) : nil)
        let filters = stripEffects ? Filters() : self.filters(shape, rid: rid)
        let svgAttributes = Self.svgAttributes(shape)

        var out = "<g id=\"shape-\(id)\"\(Self.wrapperStyle(shape))><defs>\(fill.defs)\(filters.defs)</defs>"
        var fills = geometry(shape, attributes: svgAttributes + fill.styleAttribute)
        if type == "image", let image = shape.object("metadata"), let imageID = image.string("id") {
            fills += "<image href=\"\(base)/assets/by-file-media-id/\(imageID)\" x=\"\(num(rect.minX))\" y=\"\(num(rect.minY))\" width=\"\(num(rect.width))\" height=\"\(num(rect.height))\" preserveAspectRatio=\"none\"\(Self.transformAttribute(shape))/>"
        }
        let strokes = { (filter: String?) in
            self.strokes(shape, rid: rid, filter: filter) { attributes, withTransform in
                self.geometry(shape, attributes: attributes, withTransform: withTransform)
            }
        }
        // Like Penpot, the effects go on the fills; on the strokes only when there are none.
        let hasFills = !shape.objects("fills").isEmpty
        if let all = filters.all {
            out += "<g class=\"fills\" filter=\"url(#\(all))\">\(fills)</g>"
            out += strokes(filters.blur)
        } else if hasFills {
            out += Self.shadowed("<g class=\"fills\">\(fills)</g>", filters: filters)
            out += strokes(nil)
        } else {
            out += "<g class=\"fills\">\(fills)</g>"
            out += Self.shadowed(strokes(nil), filters: filters)
        }
        return out + "</g>"
    }

    // MARK: Fills

    private struct Paint {
        var style: String = ""
        var defs: String = ""
        var styleAttribute: String { style.isEmpty ? "" : " style=\"\(style)\"" }
    }

    private func fillPaint(_ shape: JSON, rid: String, box: CGRect, patternTransform: String?) -> Paint {
        let fills = shape.objects("fills")
        let type = shape.string("type") ?? ""
        let svgAttrs = shape.object("svgAttrs")
        if fills.isEmpty {
            if type == "svg-raw" || (type == "group" && svgAttrs != nil) { return Paint(style: "fill:#000000") }
            if let fill = svgAttrs?.object("style")?.string("fill") ?? svgAttrs?.string("fill") {
                return Paint(style: "fill:\(fill)")
            }
            return Paint()
        }
        let isURLFill = fills.count > 1
            || fills.contains { $0.object("fillColorGradient") != nil || $0.object("fillImage") != nil }
        if !isURLFill {
            let fill = fills[0]
            let color = fill.string("fillColor") ?? svgAttrs?.string("fill") ?? "#000000"
            return Paint(style: "fill:\(color);fill-opacity:\(num(fill.number("fillOpacity") ?? 1))")
        }
        var defs = ""
        var layers = ""
        for (index, fill) in fills.enumerated().reversed() {
            let opacity = fill.number("fillOpacity") ?? 1
            if let image = fill.object("fillImage"), let imageID = image.string("id") {
                let keep = image.flag("keepAspectRatio")
                layers += "<image href=\"\(base)/assets/by-file-media-id/\(imageID)\" x=\"0\" y=\"0\" width=\"\(num(box.width))\" height=\"\(num(box.height))\" opacity=\"\(num(opacity))\" preserveAspectRatio=\"\(keep ? "xMidYMid slice" : "none")\"/>"
            } else if let gradient = fill.object("fillColorGradient") {
                let gradientID = "fill-color-gradient-\(rid)-\(index)"
                defs += Self.gradient(gradient, id: gradientID)
                layers += "<rect width=\"\(num(box.width))\" height=\"\(num(box.height))\" style=\"fill:url(#\(gradientID));fill-opacity:\(num(opacity))\"/>"
            } else {
                layers += "<rect width=\"\(num(box.width))\" height=\"\(num(box.height))\" style=\"fill:\(fill.string("fillColor") ?? "none");fill-opacity:\(num(opacity))\"/>"
            }
        }
        let patternID = "fill-0-\(rid)"
        let transform = patternTransform.map { " patternTransform=\"\($0)\"" } ?? ""
        defs += "<pattern id=\"\(patternID)\" patternUnits=\"userSpaceOnUse\" x=\"\(num(box.minX))\" y=\"\(num(box.minY))\" width=\"\(num(box.width))\" height=\"\(num(box.height))\"\(transform)><g>\(layers)</g></pattern>"
        return Paint(style: "fill:url(#\(patternID))", defs: defs)
    }

    /// A Penpot gradient (`type`, `startX`…`endY` in 0…1 of the box, `width`, `stops`).
    private static func gradient(_ gradient: JSON, id: String) -> String {
        let stops = gradient.objects("stops")
        let sx = gradient.number("startX") ?? 0, sy = gradient.number("startY") ?? 0
        let ex = gradient.number("endX") ?? 1, ey = gradient.number("endY") ?? 1
        func stopElements(_ stops: [JSON]) -> String {
            stops.map { stop in
                "<stop offset=\"\(num(stop.number("offset") ?? 0))\" stop-color=\"\(stop.string("color") ?? "#000000")\" stop-opacity=\"\(num(stop.number("opacity") ?? 1))\"/>"
            }.joined()
        }
        if gradient.string("type") == "radial" {
            let dx = ex - sx, dy = ey - sy
            let radius = (dx * dx + dy * dy).squareRoot()
            let angle = atan2(dy, dx) * 180 / .pi + 90
            let width = gradient.number("width") ?? 1
            let transform = "translate(\(num(sx)),\(num(sy))) rotate(\(num(angle))) scale(\(num(width)),1) translate(\(num(-sx)),\(num(-sy)))"
            return "<radialGradient id=\"\(id)\" cx=\"\(num(sx))\" cy=\"\(num(sy))\" r=\"\(num(radius))\" gradientTransform=\"\(transform)\">\(stopElements(stops))</radialGradient>"
        }
        let sorted = stops.sorted { ($0.number("offset") ?? 0) < ($1.number("offset") ?? 0) }
        return "<linearGradient id=\"\(id)\" x1=\"\(num(sx))\" y1=\"\(num(sy))\" x2=\"\(num(ex))\" y2=\"\(num(ey))\">\(stopElements(sorted))</linearGradient>"
    }

    // MARK: Strokes

    /// Penpot's strokes over the fills: center, inner (clipped to the shape, double width)
    /// or outer (masked outside the shape, double width), last array entry drawn first.
    private func strokes(_ shape: JSON, rid: String, filter: String?,
                         element: (String, Bool) -> String) -> String {
        let strokes = shape.objects("strokes")
        guard !strokes.isEmpty, let id = shape.string("id") else { return "" }
        let type = shape.string("type") ?? ""
        let closed = type != "path" || !Self.hasOpenSubpath(shape.string("content") ?? "")
        var out = ""
        for (index, stroke) in strokes.enumerated().reversed() where !stroke.flag("hidden") {
            let style = stroke.string("strokeStyle")
            if style == "none" { continue }
            let width = stroke.number("strokeWidth") ?? 1
            var defs = ""
            var paint = stroke.string("strokeColor") ?? "#000000"
            if let gradient = stroke.object("strokeColorGradient") {
                let gradientID = "stroke-color-gradient-\(rid)-\(index)"
                defs += Self.gradient(gradient, id: gradientID)
                paint = "url(#\(gradientID))"
            }
            var css = "fill:none;stroke:\(paint);stroke-opacity:\(num(stroke.number("strokeOpacity") ?? 1));"
            switch style {
            case "mixed": css += "stroke-dasharray:\(num(width + 5)),\(num(width + 5)),\(num(width + 1)),\(num(width + 5));"
            case "dotted": css += "stroke-dasharray:0,\(num(width + 5));stroke-linecap:round;"
            case "dashed": css += "stroke-dasharray:\(num(stroke.number("strokeDash") ?? width + 10)),\(num(stroke.number("strokeGap") ?? width + 10));"
            default: break
            }
            if style != "dotted", let cap = stroke.string("strokeCapStart"), cap == stroke.string("strokeCapEnd"),
               cap == "round" || cap == "square" {
                css += "stroke-linecap:\(cap);"
            }
            let alignment = (width > 0 && style != nil && closed) ? (stroke.string("strokeAlignment") ?? "center") : "center"
            let elementID = "stroke-shape-\(rid)-\(index)"
            switch alignment {
            case "inner":
                let clipID = "inner-stroke-\(rid)-\(index)"
                let transform = type == "path" || type == "bool" ? "" : Self.transformAttribute(shape)
                out += "<g class=\"inner-stroke-shape\"\(transform)><defs>\(defs)<clipPath id=\"\(clipID)\"><use href=\"#\(elementID)\"/></clipPath>"
                out += element(" id=\"\(elementID)\" style=\"\(css)stroke-width:\(num(width * 2))\"", false)
                out += "</defs><use href=\"#\(elementID)\" clip-path=\"url(#\(clipID))\"/></g>"
            case "outer":
                let maskID = "outer-stroke-\(rid)-\(index)"
                let margin = (type == "path" ? width : 0) + width * 2.0.squareRoot()
                let box = (Self.pointsBox(shape) ?? Self.selrect(shape)).insetBy(dx: -margin, dy: -margin)
                out += "<g class=\"outer-stroke-shape\"><defs>\(defs)<mask id=\"\(maskID)\" maskUnits=\"userSpaceOnUse\" x=\"\(num(box.minX))\" y=\"\(num(box.minY))\" width=\"\(num(box.width))\" height=\"\(num(box.height))\">"
                out += "<use href=\"#\(elementID)\" style=\"fill:none;stroke:white;stroke-width:\(num(width * 2))\"/><use href=\"#\(elementID)\" style=\"fill:black;stroke:none\"/></mask>"
                out += element(" id=\"\(elementID)\"", true)
                out += "</defs><use href=\"#\(elementID)\" mask=\"url(#\(maskID))\" style=\"\(css)stroke-width:\(num(width * 2))\"/></g>"
            default:
                out += "<g class=\"stroke-shape\"><defs>\(defs)</defs>"
                out += element(" style=\"\(css)stroke-width:\(num(width))\"", true) + "</g>"
            }
        }
        guard !out.isEmpty else { return "" }
        let filterAttribute = filter.map { " filter=\"url(#\($0))\"" } ?? ""
        return "<g id=\"strokes-\(id)\" class=\"strokes\"\(Self.svgAttributes(shape))\(filterAttribute)>\(out)</g>"
    }

    /// Whether any subpath of `d` is left open (no `z`/`Z` before the next `M`).
    private static func hasOpenSubpath(_ d: String) -> Bool {
        var started = false
        var closed = true
        for character in d {
            switch character {
            case "M", "m":
                if started && !closed { return true }
                started = true
                closed = false
            case "Z", "z":
                closed = true
            default:
                break
            }
        }
        return started && !closed
    }

    // MARK: Background blur

    static func visibleBackgroundBlur(_ shape: JSON) -> Double? {
        guard let blur = shape.object("backgroundBlur"), !blur.flag("hidden"),
              let value = blur.number("value"), value > 0 else { return nil }
        return value
    }

    /// Penpot's background blur (a WebGL-renderer feature): what lies under the shape,
    /// blurred and cut to the shape's outline, drawn before the shape and outside its
    /// opacity. Penpot's own SVG export uses CSS `backdrop-filter`, which WebKit never
    /// draws into a PDF, so the backdrop is a blurred copy of what was written before.
    /// Text is left out: Penpot blurs only behind its glyphs.
    private func backgroundBlur(_ shape: JSON) -> String {
        guard tracksBackdrop, !backdrop.isEmpty, let value = Self.visibleBackgroundBlur(shape),
              shape.string("type") != "text" else { return "" }
        let rid = nextRID()
        // render-wasm's `radius_to_sigma` (Skia's radius → standard deviation).
        let sigma = 0.57735 * value + 0.5
        let rect = Self.selrect(shape)
        let outline = shape.string("type") == "group"
            ? "<rect x=\"\(num(rect.minX))\" y=\"\(num(rect.minY))\" width=\"\(num(rect.width))\" height=\"\(num(rect.height))\"/>"
            : geometry(shape, attributes: "")
        // Only the area around the shape is blurred (and turned into a bitmap).
        let region = (Self.pointsBox(shape) ?? rect).insetBy(dx: -3 * sigma, dy: -3 * sigma)
        var out = "<g class=\"background-blur\"><defs><clipPath id=\"background-blur-clip-\(rid)\">\(outline)</clipPath>"
        out += "<filter id=\"background-blur-\(rid)\" filterUnits=\"userSpaceOnUse\" x=\"\(num(region.minX))\" y=\"\(num(region.minY))\" width=\"\(num(region.width))\" height=\"\(num(region.height))\" color-interpolation-filters=\"sRGB\">"
        out += "<feGaussianBlur stdDeviation=\"\(num(sigma))\"/></filter></defs>"
        return out + "<g clip-path=\"url(#background-blur-clip-\(rid))\"><g filter=\"url(#background-blur-\(rid))\">\(backdrop)</g></g></g>"
    }

    // MARK: Filters

    /// A shape's effects as SVG filters. `createPDF` draws a filtered element as a bitmap,
    /// so shadows are drawn from copies of the shape (``shadowed(_:filters:source:)``) and
    /// the shape itself stays vector, text included. A shape with a layer blur keeps one
    /// filter: blurred, it loses nothing as a bitmap.
    private struct Filters {
        var defs = ""
        /// Shadows and blur together; only made when there is a blur.
        var all: String?
        var blur: String?
        /// The drop shadows alone, drawn under the shape.
        var drops: String?
        /// The inner shadows alone, drawn over it.
        var inners: String?
        /// Hard shadows (no blur) as vector paths, under and over the shape (``hardShadow``).
        var hardDrops = ""
        var hardInners = ""
    }

    private func filters(_ shape: JSON, rid: String, withDrops: Bool = true) -> Filters {
        let shadows = shape.objects("shadow").filter {
            !$0.flag("hidden") && (withDrops || $0.string("style") == "inner-shadow")
        }
        let blur = shape.object("blur").flatMap { blur -> JSON? in
            blur.flag("hidden") || (blur.number("value") ?? 0) <= 0 ? nil : blur
        }
        guard !shadows.isEmpty || blur != nil else { return Filters() }
        // Without blur, a shadow of a filled rect, board or ellipse is exact as a path: no
        // bitmap at all. Carbon draws its table rules as 1 px inner shadows, hundreds per
        // board, which as filters took 19 s on a Mac and overran an iPhone's memory.
        let vector = blur == nil && alphaIsOutline(shape)
        let isHard = { (shadow: JSON) in vector && (shadow.number("blur") ?? 0) <= 0 }
        let drops = shadows.filter { $0.string("style") != "inner-shadow" && !isHard($0) }
        let inners = shadows.filter { $0.string("style") == "inner-shadow" && !isHard($0) }
        var result = Filters()
        for (index, shadow) in shadows.enumerated().reversed() where isHard(shadow) {
            if shadow.string("style") == "inner-shadow" {
                result.hardInners += hardShadow(shadow, of: shape, inner: true, id: "inner-shadow-\(rid)-\(index)")
            } else {
                result.hardDrops += hardShadow(shadow, of: shape, inner: false, id: "")
            }
        }
        func make(_ id: String, drops: [JSON], inners: [JSON], includesShape: Bool, blur: JSON?) -> String? {
            guard let graph = Self.filterGraph(drops: drops, inners: inners, includesShape: includesShape,
                                               blur: blur) else { return nil }
            result.defs += "<filter id=\"\(id)\"\(Self.filterRegion(shape, shadows: drops, blur: blur)) color-interpolation-filters=\"sRGB\">\(graph)</filter>"
            return id
        }
        if blur != nil {
            result.all = make("filter-\(rid)", drops: drops, inners: inners, includesShape: true, blur: blur)
            result.blur = make("filter-blur-\(rid)", drops: [], inners: [], includesShape: true, blur: blur)
        }
        result.drops = make("filter-drops-\(rid)", drops: drops, inners: [], includesShape: false, blur: nil)
        result.inners = make("filter-inners-\(rid)", drops: [], inners: inners, includesShape: false, blur: nil)
        return result
    }

    /// `content` with its shadows: `source` (the content unless given) under it through the
    /// drop-shadow filter and over it through the inner-shadow filter. Only those copies
    /// turn into bitmaps in the PDF.
    private static func shadowed(_ content: String, filters: Filters, source: String? = nil) -> String {
        let source = source ?? content
        var out = filters.drops.map { "<g filter=\"url(#\($0))\">\(source)</g>" } ?? ""
        out += filters.hardDrops + content + filters.hardInners
        if let inners = filters.inners { out += "<g filter=\"url(#\(inners))\">\(source)</g>" }
        return out
    }

    /// Whether the alpha Penpot's shadow filters read, made hard (`SourceAlpha` × 127), is
    /// exactly the outline: an untransformed rect, board or ellipse with a fill. A board's
    /// content must stay inside it unless it clips; a board without a fill counts when
    /// filled children cover it (a table row of cells).
    private func alphaIsOutline(_ shape: JSON) -> Bool {
        let type = shape.string("type") ?? ""
        guard ["rect", "frame", "circle"].contains(type), Self.transform(shape) == nil else { return false }
        let filled = shape.objects("fills").contains {
            $0.object("fillImage") == nil && ($0.number("fillOpacity") ?? 1) > 0
        }
        guard type == "frame" else { return filled }
        let rect = Self.selrect(shape)
        let children = (shape.array("shapes") as? [String] ?? []).compactMap { objects[$0] }
            .filter { !$0.flag("hidden") && Self.isValid($0) }
        if shape["showContent"] as? Bool == true {
            let room = rect.insetBy(dx: -1.5, dy: -1.5)
            guard children.allSatisfy({ room.contains(Self.visualBounds($0, objects: objects)) }) else { return false }
        }
        if filled { return true }
        guard children.count <= 32 else { return false }
        let parts = children.filter { $0.string("type") != "circle" && alphaIsOutline($0) }.map(Self.selrect)
        return Self.covers(rect, parts)
    }

    /// Whether the union of `parts` covers `rect` (edges closer than 0.01 count as touching).
    private static func covers(_ rect: CGRect, _ parts: [CGRect]) -> Bool {
        let parts = parts.map { $0.intersection(rect) }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        guard !parts.isEmpty else { return false }
        let xs = Set([rect.minX, rect.maxX] + parts.flatMap { [$0.minX, $0.maxX] }).sorted()
        let ys = Set([rect.minY, rect.maxY] + parts.flatMap { [$0.minY, $0.maxY] }).sorted()
        for (x0, x1) in zip(xs, xs.dropFirst()) where x1 - x0 >= 0.01 {
            for (y0, y1) in zip(ys, ys.dropFirst()) where y1 - y0 >= 0.01 {
                let center = CGPoint(x: (x0 + x1) / 2, y: (y0 + y1) / 2)
                if !parts.contains(where: { $0.contains(center) }) { return false }
            }
        }
        return true
    }

    /// A shadow without blur as a path. A drop shadow is the outline moved by the offset and
    /// grown by the spread; an inner shadow is the outline minus that (shrunk by the spread),
    /// cut to the outline — what Penpot's graph gives with no blur in it.
    private func hardShadow(_ shadow: JSON, of shape: JSON, inner: Bool, id: String) -> String {
        let rect = Self.selrect(shape)
        let dx = shadow.number("offsetX") ?? 0, dy = shadow.number("offsetY") ?? 0
        let spread = shadow.number("spread") ?? 0
        let grow = inner ? -max(spread, 0) : spread
        let moved = Self.outlinePath(shape, rect.offsetBy(dx: dx, dy: dy).insetBy(dx: -grow, dy: -grow), grow: grow)
        let color = shadow.object("color")
        let paint = " fill=\"\(escape(color?.string("color") ?? "#000000"))\" fill-opacity=\"\(num(color?.number("opacity") ?? 1))\""
        guard inner else { return "<path d=\"\(moved)\"\(paint)/>" }
        let outer = rect.insetBy(dx: -abs(dx) - abs(spread) - 1, dy: -abs(dy) - abs(spread) - 1)
        let frame = "M\(num(outer.minX)),\(num(outer.minY)) H\(num(outer.maxX)) V\(num(outer.maxY)) H\(num(outer.minX)) Z "
        return "<defs><clipPath id=\"\(id)\">\(geometry(shape, attributes: ""))</clipPath></defs>"
            + "<g clip-path=\"url(#\(id))\"><path fill-rule=\"evenodd\" d=\"\(frame)\(moved)\"\(paint)/></g>"
    }

    /// The outline of a rect, board or ellipse placed at `rect`, its corner radii grown by `grow`.
    private static func outlinePath(_ shape: JSON, _ rect: CGRect, grow: Double) -> String {
        if shape.string("type") == "circle" {
            let rx = rect.width / 2, ry = rect.height / 2
            return "M\(num(rect.minX)),\(num(rect.midY)) a\(num(rx)),\(num(ry)) 0 1 0 \(num(rect.width)),0 "
                + "a\(num(rx)),\(num(ry)) 0 1 0 \(num(-rect.width)),0 Z"
        }
        let radii = ["r1", "r2", "r3", "r4"].map { radius -> Double in
            let r = shape.number(radius) ?? 0
            return r > 0 ? max(0, r + grow) : 0
        }
        return cornerPath(rect, radii)
    }

    /// Penpot's filter graph (`filters.cljs`): drop shadows, the shape over them, inner
    /// shadows, blur. Without `includesShape` it yields the shadows alone.
    private static func filterGraph(drops: [JSON], inners: [JSON], includesShape: Bool, blur: JSON?) -> String? {
        guard !drops.isEmpty || !inners.isEmpty || blur != nil else { return nil }
        var graph = "<feFlood flood-opacity=\"0\" result=\"BackgroundImageFix\"/>"
        var previous = "BackgroundImageFix"
        func colorMatrix(_ shadow: JSON) -> String {
            let color = shadow.object("color")
            let hex = (color?.string("color") ?? "#000000").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let value = UInt32(hex.prefix(6), radix: 16) ?? 0
            let r = Double(value >> 16 & 0xff) / 255, g = Double(value >> 8 & 0xff) / 255, b = Double(value & 0xff) / 255
            let a = color?.number("opacity") ?? 1
            return "<feColorMatrix type=\"matrix\" values=\"0 0 0 0 \(num(r)) 0 0 0 0 \(num(g)) 0 0 0 0 \(num(b)) 0 0 0 \(num(a)) 0\"/>"
        }
        for (index, shadow) in drops.reversed().enumerated() {
            let id = "drop-\(index)"
            let spread = shadow.number("spread") ?? 0
            graph += "<feColorMatrix in=\"SourceAlpha\" type=\"matrix\" values=\"0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0\"/>"
            if spread > 0 {
                graph += "<feMorphology radius=\"\(num(spread))\" operator=\"dilate\" in=\"SourceAlpha\"/>"
            } else if spread < 0 {
                graph += "<feMorphology radius=\"\(num(-spread))\" operator=\"erode\" in=\"SourceAlpha\"/>"
            }
            graph += "<feOffset dx=\"\(num(shadow.number("offsetX") ?? 0))\" dy=\"\(num(shadow.number("offsetY") ?? 0))\"/>"
            graph += "<feGaussianBlur stdDeviation=\"\(num((shadow.number("blur") ?? 0) / 2))\"/>"
            graph += colorMatrix(shadow)
            graph += "<feBlend mode=\"normal\" in2=\"\(previous)\" result=\"\(id)\"/>"
            previous = id
        }
        if includesShape {
            graph += "<feBlend mode=\"normal\" in=\"SourceGraphic\" in2=\"\(previous)\" result=\"shape\"/>"
            previous = "shape"
        }
        for (index, shadow) in inners.reversed().enumerated() {
            let id = "inner-\(index)"
            let spread = shadow.number("spread") ?? 0
            graph += "<feColorMatrix in=\"SourceAlpha\" type=\"matrix\" values=\"0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0\" result=\"hardAlpha\"/>"
            if spread > 0 {
                graph += "<feMorphology radius=\"\(num(spread))\" operator=\"erode\" in=\"SourceAlpha\"/>"
            }
            graph += "<feOffset dx=\"\(num(shadow.number("offsetX") ?? 0))\" dy=\"\(num(shadow.number("offsetY") ?? 0))\"/>"
            graph += "<feGaussianBlur stdDeviation=\"\(num((shadow.number("blur") ?? 0) / 2))\"/>"
            graph += "<feComposite in2=\"hardAlpha\" operator=\"arithmetic\" k2=\"-1\" k3=\"1\"/>"
            graph += colorMatrix(shadow)
            graph += "<feBlend mode=\"normal\" in2=\"\(previous)\" result=\"\(id)\"/>"
            previous = id
        }
        if let blur {
            graph += "<feGaussianBlur stdDeviation=\"\(num(blur.number("value") ?? 0))\" result=\"blur\"/>"
        }
        return graph
    }

    private static func filterRegion(_ shape: JSON, shadows: [JSON], blur: JSON?) -> String {
        let sel = selrect(shape)
        var box = sel
        var padX = 0.0, padY = 0.0
        for shadow in shadows where shadow.string("style") != "inner-shadow" {
            let ox = shadow.number("offsetX") ?? 0, oy = shadow.number("offsetY") ?? 0
            let spread = shadow.number("spread") ?? 0, blur = shadow.number("blur") ?? 0
            box = box.union(CGRect(x: min(sel.minX, sel.minX + ox - spread - blur - 5),
                                   y: min(sel.minY, sel.minY + oy - spread - blur - 5),
                                   width: sel.width + abs(ox) + 2 * spread + 2 * blur + 10,
                                   height: sel.height + abs(oy) + 2 * spread + 2 * blur + 10))
            padX = max(padX, abs(ox) + 2 * spread + 2 * blur + 10)
            padY = max(padY, abs(oy) + 2 * spread + 2 * blur + 10)
        }
        let strokeMargin = shape.objects("strokes").map { stroke -> Double in
            let width = stroke.number("strokeWidth") ?? 1
            switch stroke.string("strokeAlignment") {
            case "outer": return width
            case "inner": return 0
            default: return width / 2
            }
        }.max() ?? 0
        padX = (padX + strokeMargin).rounded(.up)
        padY = (padY + strokeMargin).rounded(.up)
        if let value = blur?.number("value") { box = box.insetBy(dx: -2 * value, dy: -2 * value) }
        let region = CGRect(x: box.minX - padX, y: box.minY - padY,
                            width: box.width + 2 * padX, height: box.height + 2 * padY)
        if sel.width < 0.01 || sel.height < 0.01 {
            return " filterUnits=\"userSpaceOnUse\" x=\"\(num(region.minX))\" y=\"\(num(region.minY))\" width=\"\(num(region.width))\" height=\"\(num(region.height))\""
        }
        return " filterUnits=\"objectBoundingBox\" x=\"\(num((region.minX - sel.minX) / sel.width))\" y=\"\(num((region.minY - sel.minY) / sel.height))\" width=\"\(num(region.width / sel.width))\" height=\"\(num(region.height / sel.height))\""
    }

    // MARK: Groups and masks

    private func group(_ shape: JSON, stripEffects: Bool) -> String {
        guard let id = shape.string("id") else { return "" }
        let rid = nextRID()
        let filters = stripEffects ? Filters() : self.filters(shape, rid: rid)
        var ids = children(of: shape)
        let out = "<g id=\"shape-\(id)\"\(Self.wrapperStyle(shape))><defs>\(filters.defs)\(svgDefs(shape))</defs>"
        var body = ""
        if shape.flag("maskedGroup"), let maskID = ids.first, let mask = objects[maskID], Self.masksLikeAClip(mask) {
            ids.removeFirst()
            let svgAttrs = mask.object("svgAttrs")
            let evenOdd = (svgAttrs?.string("fillRule") ?? svgAttrs?.string("fill-rule")) == "evenodd"
            body += "<g clip-path=\"url(#\(rid)-mask)\"><defs><clipPath id=\"\(rid)-mask\">"
            body += geometry(mask, attributes: evenOdd ? " clip-rule=\"evenodd\"" : "")
            body += "</clipPath></defs>\(renderChildren(ids))</g>"
        } else if shape.flag("maskedGroup"), let maskID = ids.first, let mask = objects[maskID] {
            ids.removeFirst()
            let box = Self.pointsBox(mask) ?? Self.selrect(mask)
            let points = mask.objects("points").compactMap { point -> String? in
                guard let x = point.number("x"), let y = point.number("y") else { return nil }
                return "\(num(x)),\(num(y))"
            }.joined(separator: " ")
            let isTextMask = mask.string("type") == "text"
            body += "<g clip-path=\"url(#\(rid)-clip)\"><g mask=\"url(#\(rid)-mask)\"><defs>"
            body += "<filter id=\"\(rid)-mask-filter\"><feFlood flood-color=\"white\" result=\"FloodResult\"/><feComposite in=\"FloodResult\" in2=\"SourceGraphic\" operator=\"in\" result=\"comp\"/></filter>"
            body += "<clipPath id=\"\(rid)-clip\"><polyline points=\"\(points)\"/></clipPath>"
            body += "<mask id=\"\(rid)-mask\" maskUnits=\"userSpaceOnUse\" x=\"\(num(box.minX))\" y=\"\(num(box.minY))\" width=\"\(num(box.width))\" height=\"\(num(box.height))\">"
            body += "<g\(isTextMask ? "" : " filter=\"url(#\(rid)-mask-filter)\"")>\(render(maskID, stripEffects: true))</g></mask></defs>"
            body += renderChildren(ids)
            body += "</g></g>"
        } else {
            body = renderChildren(ids)
        }
        if let all = filters.all { return out + "<g filter=\"url(#\(all))\">\(body)</g></g>" }
        return out + Self.shadowed(body, filters: filters) + "</g>"
    }

    /// A mask that is one plain shape filled opaquely cuts exactly along its outline. As a
    /// clip path it stays vector in the PDF; a `<mask>` turns into a bitmap with stepped
    /// edges (an image cropped to a circle, a card's rounded corners).
    private static func masksLikeAClip(_ mask: JSON) -> Bool {
        guard ["rect", "circle", "path", "bool"].contains(mask.string("type") ?? ""),
              !mask.flag("hidden"), (mask.number("opacity") ?? 1) >= 1 else { return false }
        let strokesStayInside = mask.objects("strokes").allSatisfy { stroke in
            stroke.string("strokeAlignment") == "inner" || (stroke.number("strokeWidth") ?? 1) <= 0
                || (stroke.number("strokeOpacity") ?? 1) <= 0
        }
        return strokesStayInside && mask.objects("fills").contains {
            $0.string("fillColor") != nil && ($0.number("fillOpacity") ?? 1) >= 1
        }
    }

    // MARK: Frames

    private func frame(_ shape: JSON, stripEffects: Bool) -> String {
        guard let id = shape.string("id") else { return "" }
        let rid = nextRID()
        let rect = Self.selrect(shape)
        let fill = fillPaint(shape, rid: rid, box: rect, patternTransform: nil)
        let clips = shape["showContent"] as? Bool != true
        let clipID = "frame-clip-\(rid)"
        // An opaque fill covers all the board holds, so its outline alone casts the shadows
        // (a typical card): no copy of the children to lay out again.
        let isOpaque = clips && shape.objects("fills").contains {
            $0.string("fillColor") != nil && ($0.number("fillOpacity") ?? 1) >= 1
        }
        let shadowSource = isOpaque ? geometry(shape, attributes: " style=\"fill:#000000\"") : nil
        // The board a document shows ends at its edges, where its drop shadows begin.
        let filters = stripEffects ? Filters()
            : self.filters(shape, rid: rid, withDrops: !(id == documentBoard && isOpaque))

        var out = "<g id=\"shape-\(id)\"\(Self.wrapperStyle(shape, withOpacity: false))><defs>\(svgDefs(shape))"
        if clips { out += "<clipPath id=\"\(clipID)\">\(geometry(shape, attributes: ""))</clipPath>" }
        out += fill.defs + "</defs>"
        let opacity = shape.number("opacity").map { $0 < 1 ? " opacity=\"\(num($0))\"" : "" } ?? ""
        out += "<g class=\"frame-container-wrapper\"\(opacity)>"
        out += "<g class=\"frame-container-blur\"\(filters.blur.map { " filter=\"url(#\($0))\"" } ?? "")><defs>\(filters.defs)</defs>"
        var body = "<g\(clips ? " clip-path=\"url(#\(clipID))\"" : "") fill=\"none\">"
        let fills = "<g class=\"fills\">\(geometry(shape, attributes: fill.styleAttribute))</g>"
        body += fills
        body += "<g class=\"frame-children\">\(renderChildren(children(of: shape), over: fills))</g>"
        body += "</g>"
        out += "<g class=\"frame-container-shadows\">\(Self.shadowed(body, filters: filters, source: shadowSource))</g>"
        out += strokes(shape, rid: rid, filter: nil) { attributes, withTransform in
            self.geometry(shape, attributes: attributes, withTransform: withTransform)
        }
        return out + "</g></g></g>"
    }

    // MARK: Text

    /// Text from its content tree as HTML in a `foreignObject`, like Penpot's editor
    /// (`fo_text.cljs`, `text/styles.cljs`), so WebKit lays it out with the real fonts.
    private func text(_ shape: JSON, stripEffects: Bool) -> String {
        guard let id = shape.string("id"), let content = shape.object("content") else { return "" }
        let rid = nextRID()
        let rect = Self.selrect(shape)
        let filters = stripEffects ? Filters() : self.filters(shape, rid: rid)
        let growType = shape.string("growType")
        let html = "<div xmlns=\"http://www.w3.org/1999/xhtml\" style=\"width:\(num(rect.width))px;height:\(num(rect.height))px;display:flex;white-space:break-spaces;align-items:\(Self.verticalAlign(content))\">"
            + paragraphs(content, growType: growType) + "</div>"
        let filterAttribute = filters.all.map { " filter=\"url(#\($0))\"" } ?? ""
        let object = "<foreignObject x=\"\(num(rect.minX))\" y=\"\(num(rect.minY))\" width=\"\(num(rect.width))\" height=\"\(num(rect.height))\" style=\"overflow:visible\">\(html)</foreignObject>"
        return "<g id=\"shape-\(id)\"\(Self.wrapperStyle(shape))><defs>\(filters.defs)</defs>"
            + "<g class=\"text-container\"\(Self.transformAttribute(shape))\(filterAttribute)>"
            + (filters.all == nil ? Self.shadowed(object, filters: filters) : object)
            + "</g></g>"
    }

    /// The content tree's paragraph sets as HTML (registering the fonts they use).
    private func paragraphs(_ content: JSON, growType: String?) -> String {
        var html = ""
        for set in content.objects("children") {
            let minWidth = growType == "auto-width" ? "" : "min-width:100%;"
            html += "<div style=\"display:inline-flex;flex-direction:column;justify-content:inherit;\(minWidth)margin-right:1px;vertical-align:top\">"
            for paragraph in set.objects("children") {
                let lineHeight = paragraph.string("lineHeight") ?? paragraph.number("lineHeight").map(num) ?? "1.2"
                let textAlign = paragraph.string("textAlign") ?? "start"
                let direction = paragraph.string("textDirection") ?? "auto"
                html += "<p dir=\"\(escape(direction))\" style=\"font-size:0;line-height:\(escape(lineHeight));margin:0;text-align:\(escape(textAlign))\">"
                for leaf in paragraph.objects("children") {
                    html += span(leaf, paragraph: paragraph, growType: growType)
                }
                html += "</p>"
            }
            html += "</div>"
        }
        return html
    }

    private static func verticalAlign(_ content: JSON) -> String {
        switch content.string("verticalAlign") {
        case "center": return "center"
        case "bottom": return "flex-end"
        default: return "flex-start"
        }
    }

    private func span(_ leaf: JSON, paragraph: JSON, growType: String?) -> String {
        func value(_ key: String) -> String? {
            leaf.string(key) ?? leaf.number(key).map(num) ?? paragraph.string(key) ?? paragraph.number(key).map(num)
        }
        let family = value("fontFamily") ?? "sourcesanspro"
        let weight = value("fontWeight") ?? "400"
        let style = value("fontStyle") ?? "normal"
        registerFont(fontID: value("fontId") ?? "sourcesanspro", family: family,
                     variantID: value("fontVariantId") ?? "regular", weight: weight, style: style)
        var css = "font-family:&quot;\(escape(family))&quot;;font-weight:\(escape(weight));font-style:\(escape(style));"
        css += "font-size:\(Self.px(value("fontSize") ?? "14"));"
        if let spacing = value("letterSpacing") { css += "letter-spacing:\(Self.px(spacing));" }
        if let decoration = value("textDecoration") { css += "text-decoration:\(escape(decoration));" }
        if let transform = value("textTransform") { css += "text-transform:\(escape(transform));" }
        let fills = leaf.objects("fills").isEmpty ? paragraph.objects("fills") : leaf.objects("fills")
        if let fill = fills.first {
            if let color = fill.string("fillColor") {
                css += "color:\(rgba(color, fill.number("fillOpacity") ?? 1));"
            } else if let stop = fill.object("fillColorGradient")?.objects("stops").first,
                      let color = stop.string("color") {
                css += "color:\(rgba(color, stop.number("opacity") ?? 1));"
            }
        } else if let color = leaf.string("fillColor") {
            css += "color:\(rgba(color, leaf.number("fillOpacity") ?? 1));"
        } else {
            css += "color:transparent;"
        }
        css += "white-space:\(growType == "auto-width" ? "pre" : "break-spaces");"
        css += "overflow-wrap:initial;line-break:auto;text-rendering:geometricPrecision"
        let text = leaf.string("text") ?? ""
        return "<span class=\"text-node\" style=\"\(css)\">\(text.isEmpty ? " " : escape(text))</span>"
    }

    private static func px(_ value: String) -> String {
        Double(value) != nil ? "\(value)px" : escape(value)
    }

    /// Records the `@font-face` (or Google fonts link) a text run needs (`fonts.cljs`).
    private func registerFont(fontID: String, family: String, variantID: String, weight: String, style: String) {
        if fontID.hasPrefix("gfont-") {
            googleFonts[family, default: []].insert(variantID)
        } else if fontID.hasPrefix("custom-") {
            let variant = customFonts.first {
                $0.fontId == fontID && String($0.fontWeight ?? 400) == weight && ($0.fontStyle ?? "normal") == style
            } ?? customFonts.first { $0.fontId == fontID }
            guard let variant, let file = variant.woff1FileId ?? variant.woff2FileId
                    ?? variant.ttfFileId ?? variant.otfFileId else { return }
            fontFaces.insert(Self.fontFace(family: variant.fontFamily, weight: weight, style: style,
                                           url: "\(base)/assets/by-id/\(file)", format: nil))
        } else if fontID == "sourcesanspro" {
            let suffixes = ["200": "extralight", "200italic": "extralightitalic", "300": "light",
                            "300italic": "lightitalic", "600": "semibold", "600italic": "semibolditalic"]
            let suffix = suffixes[variantID] ?? variantID
            fontFaces.insert(Self.fontFace(family: family, weight: weight, style: style,
                                           url: "\(base)/fonts/sourcesanspro-\(suffix).woff", format: "woff"))
        }
    }

    private static func fontFace(family: String, weight: String, style: String, url: String, format: String?) -> String {
        let formatPart = format.map { " format('\($0)')" } ?? ""
        return "@font-face{font-family:'\(family.replacingOccurrences(of: "'", with: ""))';font-style:\(style);font-weight:\(weight);font-display:block;src:url(\(url))\(formatPart);}"
    }

    // MARK: Layout

    /// The board as nested HTML boxes for WebKit to lay out (``PenpotSVG/Page/layoutProbe(board:)``),
    /// after Penpot's flex layout (`common/geom/shapes/flex_layout`) and its CSS export
    /// (`util/code_gen/style_css*`): children in reverse `shapes` order, `fix` sizes in
    /// pixels, `auto` (hug) from the content, `fill` growing. Under `stretch`, an item that
    /// isn't `fill` across sits at the start, as in Penpot.
    ///
    /// Only what Penpot's editor would lay out again is laid out: texts it never measured
    /// and the flex boards around them (``markStale(_:)``). Everything else keeps its
    /// stored size and its stored offset from its parent, since in Penpot a layout only
    /// reflows when something in it changes.
    func layoutProbe(board: JSON) -> String {
        stale = []
        markStale(board)
        let body = probe(board, parent: nil, parentRect: Self.selrect(board))
        return "<!doctype html><html><head>\(head())<style>[data-id]{box-sizing:border-box}</style></head><body>\(body)</body></html>"
    }

    /// Shapes to lay out again: texts without `positionData` and everything holding one.
    private var stale: Set<String> = []

    @discardableResult
    private func markStale(_ shape: JSON) -> Bool {
        guard let id = shape.string("id"), !shape.flag("hidden") else { return false }
        var isStale = shape.string("type") == "text" && shape.objects("positionData").isEmpty
        for child in (shape.array("shapes") as? [String] ?? []).compactMap({ objects[$0] }) {
            isStale = markStale(child) || isStale
        }
        if isStale { stale.insert(id) }
        return isStale
    }

    private func probe(_ shape: JSON, parent: JSON?, parentRect: CGRect) -> String {
        guard let id = shape.string("id"), !shape.flag("hidden"), Self.isValid(shape) else { return "" }
        let type = shape.string("type") ?? ""
        let rect = Self.layoutRect(shape)
        let isStale = stale.contains(id)
        let flexParent = stale.contains(parent?.string("id") ?? "") && parent?.string("layout") == "flex" ? parent : nil
        let inFlow = flexParent != nil && !shape.flag("layoutItemAbsolute")
        let parentRow = (flexParent?.string("layoutFlexDir") ?? "row").hasPrefix("row")
        let content = type == "text" ? shape.object("content") : nil
        let growType = content == nil || !isStale ? nil : shape.string("growType")
        let isFlex = isStale && type == "frame" && shape.string("layout") == "flex"
        // The board itself keeps its size: its document is that rect.
        let hSizing = parent == nil ? "fix" : shape.string("layoutItemHSizing") ?? "fix"
        let vSizing = parent == nil ? "fix" : shape.string("layoutItemVSizing") ?? "fix"

        var css = ""
        if inFlow, let flexParent {
            css += "position:relative;flex-shrink:0;"
            if let margin = shape.object("layoutItemMargin") { css += "margin:\(Self.px4(margin, "m"));" }
            switch shape.string("layoutItemAlignSelf") {
            case "start": css += "align-self:flex-start;"
            case "center": css += "align-self:center;"
            case "end": css += "align-self:flex-end;"
            default:
                if (parentRow ? vSizing : hSizing) == "fill" {
                    css += "align-self:stretch;"
                } else if flexParent.string("layoutAlignItems") == "stretch" {
                    css += "align-self:flex-start;"
                }
            }
        } else {
            css += "position:absolute;left:\(num(rect.minX - parentRect.minX))px;top:\(num(rect.minY - parentRect.minY))px;"
        }
        func size(horizontal: Bool) -> String {
            let dimension = horizontal ? "width" : "height"
            let length = horizontal ? rect.width : rect.height
            let sizing = horizontal ? hSizing : vSizing
            if inFlow, sizing == "fill" { return horizontal == parentRow ? "flex:1 1 0;min-\(dimension):0;" : "" }
            if let growType {
                if horizontal { return growType == "auto-width" ? "width:max-content;" : "width:\(num(length))px;" }
                return growType == "fixed" ? "height:\(num(length))px;" : ""
            }
            return isFlex && sizing == "auto" ? "" : "\(dimension):\(num(length))px;"
        }
        css += size(horizontal: true) + size(horizontal: false)
        for (key, property) in [("layoutItemMinW", "min-width"), ("layoutItemMaxW", "max-width"),
                                ("layoutItemMinH", "min-height"), ("layoutItemMaxH", "max-height")] {
            if let value = shape.number(key) { css += "\(property):\(num(value))px;" }
        }

        var inner = ""
        if let content, isStale {
            css += "display:flex;white-space:break-spaces;align-items:\(Self.verticalAlign(content));"
            inner = paragraphs(content, growType: growType)
        } else if type == "frame" || type == "group" {
            var ids = shape.array("shapes") as? [String] ?? []
            if isFlex {
                css += Self.flexContainerCSS(shape)
                ids.reverse()
            }
            inner = ids.compactMap { objects[$0] }.map { probe($0, parent: shape, parentRect: rect) }.joined()
        }
        return "<div data-id=\"\(escape(id))\" style=\"\(css)\">\(inner)</div>"
    }

    private static func flexContainerCSS(_ shape: JSON) -> String {
        let direction = shape.string("layoutFlexDir") ?? "row"
        var css = "display:flex;flex-direction:\(["row-reverse", "column", "column-reverse"].contains(direction) ? direction : "row");"
        css += "flex-wrap:\(shape.string("layoutWrapType") == "wrap" ? "wrap" : "nowrap");"
        let gap = shape.object("layoutGap")
        css += "row-gap:\(num(gap?.number("rowGap") ?? 0))px;column-gap:\(num(gap?.number("columnGap") ?? 0))px;"
        if let padding = shape.object("layoutPadding") { css += "padding:\(px4(padding, "p"));" }
        css += "justify-content:\(flexValue(shape.string("layoutJustifyContent")));"
        css += "align-items:\(flexValue(shape.string("layoutAlignItems")));"
        css += "align-content:\(flexValue(shape.string("layoutAlignContent")));"
        return css
    }

    /// Penpot's `start`/`end`/`center`/`space-*`/`stretch` as a CSS flex value.
    private static func flexValue(_ value: String?) -> String {
        switch value {
        case "end": return "flex-end"
        case "center", "space-between", "space-around", "space-evenly", "stretch": return value ?? ""
        default: return "flex-start"
        }
    }

    /// `{p1…p4}` or `{m1…m4}` (top, right, bottom, left) as a CSS shorthand.
    private static func px4(_ box: JSON, _ prefix: String) -> String {
        (1...4).map { "\(num(box.number("\(prefix)\($0)") ?? 0))px" }.joined(separator: " ")
    }

    // MARK: Imported SVG

    private func svgRaw(_ shape: JSON) -> String {
        guard let id = shape.string("id") else { return "" }
        if let text = shape.string("content") { return escape(text) }
        guard let content = shape.object("content"), let tag = content.string("tag") else { return "" }
        let attrs = shape.object("svgAttrs") ?? content.object("attrs") ?? [:]

        if tag == "style" {
            let css = (content.array("content") as? [String] ?? []).joined(separator: "\n")
            let scope = svgRootStack.last.map { "#shape-\($0)" } ?? ""
            return "<style>\(scope.isEmpty ? css : "\(scope){ \(css) }")</style>"
        }
        guard svgTags.contains(tag) else { return "" }
        let rid = nextRID()
        let fill = fillPaint(shape, rid: rid, box: Self.selrect(shape), patternTransform: nil)

        var element: String
        if tag == "svg" {
            svgRootStack.append(id)
            let rect = Self.selrect(shape)
            let attributes = Self.attributeString(attrs, skipping: ["x", "y", "width", "height", "transform", "id", "style"])
            let inner = children(of: shape).map { render($0) }.joined()
            svgRootStack.removeLast()
            element = "<g class=\"svg-raw\"\(Self.transformAttribute(shape))><svg x=\"\(num(rect.minX))\" y=\"\(num(rect.minY))\" width=\"\(num(rect.width))\" height=\"\(num(rect.height))\" preserveAspectRatio=\"none\"\(attributes)\(fill.styleAttribute)>\(inner)</svg></g>"
        } else {
            var attributes = Self.attributeString(attrs, skipping: ["id", "transform", "style"])
            if graphicTags.contains(tag), let transform = attrs.string("transform"), !transform.isEmpty {
                attributes += " transform=\"\(escape(transform))\""
            }
            let style = Self.styleString(attrs.object("style"), extra: fill.style)
            let inner = children(of: shape).map { render($0) }.joined()
            element = "<\(tag)\(attributes)\(style.isEmpty ? "" : " style=\"\(style)\"")>\(inner)</\(tag)>"
        }
        let defs = fill.defs.isEmpty ? "" : "<defs>\(fill.defs)</defs>"
        if tag == "svg" || shape["svgAttrs"] != nil {
            return "<g id=\"shape-\(id)\"\(Self.wrapperStyle(shape))>\(defs)\(element)</g>"
        }
        return defs + element
    }

    /// `svgAttrs` (or imported `attrs`) as SVG attributes, camelCase undone.
    private static func attributeString(_ attrs: JSON, skipping: Set<String>) -> String {
        var out = ""
        for (key, value) in attrs.sorted(by: { $0.key < $1.key }) where !skipping.contains(key) {
            if value is JSON || value is [Any] || value is NSNull { continue }
            out += " \(svgName(key))=\"\(escape(String(describing: value)))\""
        }
        return out
    }

    private static func styleString(_ style: JSON?, extra: String) -> String {
        var parts: [String] = []
        for (key, value) in (style ?? [:]).sorted(by: { $0.key < $1.key }) {
            if key == "fill" || key == "fillOpacity", !extra.isEmpty { continue }
            parts.append("\(svgName(key)):\(escape(String(describing: value)))")
        }
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: ";")
    }

    /// The shape's own `svgAttrs` as attributes on its fill element and strokes group
    /// (e.g. `fill-rule`), without the ones the renderer sets itself.
    ///
    /// A clip path, mask or filter of an imported SVG is left out, as Penpot's WebGL
    /// renderer does (its `SvgAttrs` keep only fill rule, line cap and join). Their
    /// definitions are in the imported file's own coordinates, which the classic renderer
    /// maps per shape (`svg-transform-matrix`) and this writer doesn't, so the clip landed
    /// beside the shape and cut it away: the ring of the "#1 Community" sticker vanished.
    private static func svgAttributes(_ shape: JSON) -> String {
        guard let attrs = shape.object("svgAttrs") else { return "" }
        return attributeString(attrs, skipping: ["id", "transform", "style", "fill", "fillOpacity",
                                                 "stroke", "strokeWidth", "x", "y", "width", "height",
                                                 "clipPath", "mask", "filter"])
    }

    /// Imported SVG definitions (gradients, clip paths, patterns) kept on groups and boards.
    private func svgDefs(_ shape: JSON) -> String {
        guard let defs = shape.object("svgDefs") else { return "" }
        return defs.sorted(by: { $0.key < $1.key }).compactMap { id, node -> String? in
            guard let node = node as? JSON else { return nil }
            return Self.defNode(node, id: id)
        }.joined()
    }

    private static func defNode(_ node: JSON, id: String?) -> String? {
        if let text = node["content"] as? String, node["tag"] == nil { return escape(text) }
        guard let tag = node.string("tag"), svgTags.contains(tag) else { return nil }
        var attrs = node.object("attrs") ?? [:]
        if let id { attrs["id"] = id }
        let attributes = attributeString(attrs, skipping: ["style"])
        let style = styleString(attrs.object("style"), extra: "")
        let children = (node.array("content") ?? []).compactMap { child -> String? in
            if let text = child as? String { return escape(text) }
            return (child as? JSON).flatMap { defNode($0, id: nil) }
        }.joined()
        return "<\(tag)\(attributes)\(style.isEmpty ? "" : " style=\"\(style)\"")>\(children)</\(tag)>"
    }
}
