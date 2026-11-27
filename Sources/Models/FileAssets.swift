import Foundation

/// A file's library, as Penpot's workspace shows it in its Assets tab (components,
/// graphics, colors, typographies) and its Tokens tab. Only `get-file` carries it, so it is
/// kept with the file's cached outline (``FileOutline``).
struct FileAssets: Codable {
    var components: [LibraryComponent] = []
    var colors: [LibraryColor] = []
    var typographies: [LibraryTypography] = []
    var media: [LibraryMedia] = []
    var tokens: TokenLibrary?

    var isEmpty: Bool {
        components.isEmpty && colors.isEmpty && typographies.isEmpty && media.isEmpty
            && (tokens?.isEmpty ?? true)
    }

    init(components: [LibraryComponent] = [], colors: [LibraryColor] = [],
         typographies: [LibraryTypography] = [], media: [LibraryMedia] = [], tokens: TokenLibrary? = nil) {
        self.components = components
        self.colors = colors
        self.typographies = typographies
        self.media = media
        self.tokens = tokens
    }

    /// From `get-file`'s `data`: the deleted components left out (Penpot keeps them for
    /// undo), and each main instance's rect looked up on its page, to draw it from there.
    init(data: FileData, pages: [String: PenpotPage]) {
        components = (data.components.map { Array($0.values) } ?? [])
            .filter { $0.deleted != true }
            .map { component in
                var component = component
                if let pageID = component.mainInstancePage, let id = component.mainInstanceId,
                   let shape = pages[pageID]?.objects[id] {
                    component.mainInstanceRect = shape.selrect
                }
                return component
            }
            .sorted(by: Self.order)
        colors = (data.colors.map { Array($0.values) } ?? []).sorted(by: Self.order)
        typographies = (data.typographies.map { Array($0.values) } ?? []).sorted(by: Self.order)
        media = (data.media.map { Array($0.values) } ?? []).sorted(by: Self.order)
        tokens = data.tokensLib.flatMap(TokenLibrary.init(dtcg:))
    }

    /// Penpot's order in the assets panel: by group, then by name, as people read numbers.
    private static func order<T: LibraryAsset>(_ lhs: T, _ rhs: T) -> Bool {
        let path = lhs.groupPath.localizedStandardCompare(rhs.groupPath)
        if path != .orderedSame { return path == .orderedAscending }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

/// What every asset has: a name, and a group path like "Buttons / Primary".
protocol LibraryAsset: Identifiable {
    var id: String { get }
    var name: String { get }
    var path: String? { get }
}

extension LibraryAsset {
    /// The group, its parts trimmed and joined the way Penpot shows them (" / ").
    var groupPath: String {
        (path ?? "").split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }
}

extension Array where Element: LibraryAsset {
    /// The assets by group, in order; the ungrouped ones first, under "".
    var grouped: [(path: String, assets: [Element])] {
        var groups: [(path: String, assets: [Element])] = []
        for asset in self {
            if let index = groups.firstIndex(where: { $0.path == asset.groupPath }) {
                groups[index].assets.append(asset)
            } else {
                groups.append((asset.groupPath, [asset]))
            }
        }
        return groups
    }

    /// The assets whose name or group contains `query`, all of them for an empty one.
    func matching(_ query: String) -> [Element] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return self }
        return filter { $0.name.localizedCaseInsensitiveContains(query) || $0.groupPath.localizedCaseInsensitiveContains(query) }
    }
}

struct LibraryComponent: LibraryAsset, Codable {
    let id: String
    let name: String
    let path: String?
    /// Components v2: the main copy, a shape on one of the file's pages.
    let mainInstanceId: String?
    let mainInstancePage: String?
    /// A variant: the board holding its siblings, and what tells it apart from them.
    let variantId: String?
    let variantProperties: [VariantProperty]?
    let deleted: Bool?
    /// The main copy's rect on its page, looked up when the file loads.
    var mainInstanceRect: Selrect?

    struct VariantProperty: Codable, Hashable {
        let name: String
        let value: String
    }

    /// The board the asset is drawn from: the main copy, on its page.
    var mainInstance: Board? {
        guard let id = mainInstanceId, let page = mainInstancePage, let rect = mainInstanceRect,
              rect.width > 0, rect.height > 0 else { return nil }
        return Board(id: id, pageID: page, name: name, selrect: rect)
    }

    /// "Size: Large, State: Hover", for a variant.
    var variantSummary: String? {
        guard let properties = variantProperties, !properties.isEmpty else { return nil }
        return properties.map { "\($0.name): \($0.value)" }.joined(separator: ", ")
    }
}

struct LibraryColor: LibraryAsset, Codable {
    let id: String
    let name: String
    let path: String?
    /// `#RRGGBB`, for a solid color.
    let color: String?
    let opacity: Double?
    let gradient: Gradient?
    let image: ImageFill?

    struct Gradient: Codable, Hashable {
        /// `linear` or `radial`.
        let type: String?
        let startX: Double?
        let startY: Double?
        let endX: Double?
        let endY: Double?
        let stops: [Stop]

        struct Stop: Codable, Hashable {
            let color: String
            let opacity: Double?
            let offset: Double
        }
    }

    struct ImageFill: Codable, Hashable {
        let id: String
        let width: Double?
        let height: Double?
    }

    /// What Penpot's color row shows after the name: the hex code (with the opacity
    /// when it isn't 100 %), or the kind of fill.
    var valueText: String {
        if let color {
            let alpha = opacity ?? 1
            return alpha < 1 ? "\(color.uppercased()) \(Int((alpha * 100).rounded())) %" : color.uppercased()
        }
        if gradient != nil {
            return gradient?.type == "radial" ? .appLocalized("Radial gradient") : .appLocalized("Linear gradient")
        }
        return image != nil ? .appLocalized("Image") : ""
    }
}

struct LibraryTypography: LibraryAsset, Codable {
    let id: String
    let name: String
    let path: String?
    let fontId: String
    let fontFamily: String
    let fontVariantId: String
    let fontSize: String
    let fontWeight: String
    let fontStyle: String
    let lineHeight: String
    let letterSpacing: String
    let textTransform: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, path, fontId, fontFamily, fontVariantId, fontSize, fontWeight, fontStyle,
             lineHeight, letterSpacing, textTransform
    }

    init(id: String, name: String, path: String?, fontId: String, fontFamily: String, fontVariantId: String,
         fontSize: String, fontWeight: String, fontStyle: String, lineHeight: String, letterSpacing: String,
         textTransform: String?) {
        self.id = id
        self.name = name
        self.path = path
        self.fontId = fontId
        self.fontFamily = fontFamily
        self.fontVariantId = fontVariantId
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontStyle = fontStyle
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.textTransform = textTransform
    }

    /// Penpot stores the numbers as strings, older files as numbers: either reads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys, _ fallback: String) -> String {
            if let string = try? c.decode(String.self, forKey: key) { return string }
            if let number = try? c.decode(Double.self, forKey: key) { return LibraryTypography.format(number) }
            return fallback
        }
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        path = try? c.decodeIfPresent(String.self, forKey: .path)
        fontId = text(.fontId, "sourcesanspro")
        fontFamily = text(.fontFamily, "sourcesanspro")
        fontVariantId = text(.fontVariantId, "regular")
        fontSize = text(.fontSize, "14")
        fontWeight = text(.fontWeight, "400")
        fontStyle = text(.fontStyle, "normal")
        lineHeight = text(.lineHeight, "1.2")
        letterSpacing = text(.letterSpacing, "0")
        textTransform = try? c.decodeIfPresent(String.self, forKey: .textTransform)
    }

    static func format(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(format: "%g", number)
    }

    /// The font as Penpot's typography row names it: family and variant.
    var fontDescription: String {
        let style = fontStyle == "italic" ? " Italic" : ""
        return "\(fontFamily) · \(fontWeight)\(style)"
    }

    /// Size, line height and letter spacing, as the row's second line.
    var metricsDescription: String {
        "\(fontSize) px · \(lineHeight) · \(letterSpacing) px"
    }

    /// The CSS the typography stands for, as Penpot's code export writes it.
    var css: String {
        var lines = [
            "font-family: \"\(fontFamily)\";",
            "font-size: \(fontSize)px;",
            "font-weight: \(fontWeight);",
        ]
        if fontStyle != "normal" { lines.append("font-style: \(fontStyle);") }
        lines.append("line-height: \(lineHeight);")
        lines.append("letter-spacing: \(letterSpacing)px;")
        if let textTransform, textTransform != "none" { lines.append("text-transform: \(textTransform);") }
        return lines.joined(separator: "\n")
    }
}

/// An image or SVG of the file's library (Penpot's "Graphics"; files migrated to
/// components v2 have turned theirs into components).
struct LibraryMedia: LibraryAsset, Codable {
    let id: String
    let name: String
    let path: String?
    let width: Double?
    let height: Double?
    let mtype: String?

    var isSVG: Bool { mtype == "image/svg+xml" }

    /// Penpot serves a file's media by its own id.
    func url(server: URL) -> URL {
        server.appendingPathComponent("assets/by-file-media-id/\(id)")
    }
}

// MARK: - Tokens

/// The file's design tokens (Penpot ≥ 2.4), as `get-file` sends them: the DTCG format of
/// Penpot's token export. Sets by name (their tokens nested in groups), `$themes`, and
/// `$metadata` with the order of the sets and the active themes and sets.
struct TokenLibrary: Codable, Equatable {
    struct Token: Codable, Hashable, Identifiable {
        /// The dotted path, e.g. `color.accent.700`.
        let name: String
        /// The DTCG type, e.g. `color`, `borderRadius`, `fontSizes`.
        let type: String
        /// The value as written: a reference like `{accent.700}`, a number, an expression,
        /// or for a composite token (typography, shadow) its parts.
        let value: String
        let description: String?

        var id: String { name }
    }

    struct TokenSet: Codable, Hashable, Identifiable {
        let name: String
        let tokens: [Token]

        var id: String { name }
    }

    struct Theme: Codable, Hashable, Identifiable {
        let name: String
        let group: String?
        /// The sets it turns on.
        let sets: [String]

        /// `group/name`, as `$metadata.activeThemes` names it.
        var id: String { [group, name].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "/") }
    }

    /// In Penpot's order (`tokenSetOrder`).
    var sets: [TokenSet]
    var themes: [Theme]
    var activeThemes: [String]
    var activeSets: [String]

    var isEmpty: Bool { sets.allSatisfy { $0.tokens.isEmpty } }

    /// Reads the DTCG JSON; `nil` without a single set.
    init?(dtcg value: JSONValue) {
        guard case let .object(root) = value else { return nil }
        let metadata = root["$metadata"]?.objectValue ?? [:]
        let order = metadata["tokenSetOrder"]?.arrayValue?.compactMap(\.stringValue) ?? []
        var parsed: [String: [Token]] = [:]
        for (key, node) in root where !key.hasPrefix("$") {
            var tokens: [Token] = []
            Self.collect(node, path: [], inheritedType: nil, into: &tokens)
            parsed[key] = tokens.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        guard !parsed.isEmpty else { return nil }
        let ordered = order.filter { parsed[$0] != nil } + parsed.keys.filter { !order.contains($0) }.sorted()
        sets = ordered.map { TokenSet(name: $0, tokens: parsed[$0] ?? []) }
        themes = (root["$themes"]?.arrayValue ?? []).compactMap { theme in
            guard let object = theme.objectValue, let name = object["name"]?.stringValue else { return nil }
            let selected = object["selectedTokenSets"]?.objectValue ?? [:]
            let sets = selected.filter { $0.value.stringValue == "enabled" }.map(\.key)
            return Theme(name: name, group: object["group"]?.stringValue, sets: sets.sorted())
        }
        activeThemes = metadata["activeThemes"]?.arrayValue?.compactMap(\.stringValue)
            .filter { $0 != "__PENPOT__HIDDEN__TOKEN__THEME__/__PENPOT__HIDDEN__TOKEN__THEME__" } ?? []
        if let explicit = metadata["activeSets"]?.arrayValue?.compactMap(\.stringValue) {
            activeSets = explicit
        } else {
            let active = Set(activeThemes)
            activeSets = Array(Set(themes.filter { active.contains($0.id) }.flatMap(\.sets)))
        }
    }

    init(sets: [TokenSet], themes: [Theme] = [], activeThemes: [String] = [], activeSets: [String]) {
        self.sets = sets
        self.themes = themes
        self.activeThemes = activeThemes
        self.activeSets = activeSets
    }

    private static func collect(_ node: JSONValue, path: [String], inheritedType: String?, into tokens: inout [Token]) {
        guard case let .object(object) = node else { return }
        let type = object["$type"]?.stringValue ?? inheritedType
        if let value = object["$value"] {
            tokens.append(Token(name: path.joined(separator: "."), type: type ?? "other",
                                value: value.tokenText(type: type), description: object["$description"]?.stringValue))
            return
        }
        for (key, child) in object where !key.hasPrefix("$") {
            collect(child, path: path + [key], inheritedType: type, into: &tokens)
        }
    }

    func isActive(_ set: TokenSet) -> Bool { activeSets.contains(set.name) }

    /// The tokens values resolve against: the active sets in order, later ones winning,
    /// then `set` itself (Penpot's tokens panel merges the selected set over them).
    func resolver(selecting set: TokenSet?) -> TokenResolver {
        var values: [String: Token] = [:]
        for active in sets where isActive(active) {
            for token in active.tokens { values[token.name] = token }
        }
        for token in set?.tokens ?? [] { values[token.name] = token }
        return TokenResolver(tokens: values)
    }

    /// The set's tokens by type, the types in Penpot's order (by their key).
    static func groups(_ tokens: [Token]) -> [(type: TokenType, tokens: [Token])] {
        Dictionary(grouping: tokens) { TokenType($0.type) }
            .sorted { $0.key.key < $1.key.key }
            .map { ($0.key, $0.value) }
    }
}

/// A token type with Penpot's title for it (`token-properties`, English in Penpot too).
struct TokenType: Hashable {
    /// Penpot's keyword, which orders the groups.
    let key: String
    let title: String

    init(_ dtcg: String) {
        let known: [String: (String, String)] = [
            "borderRadius": ("border-radius", "Border Radius"),
            "color": ("color", "Color"),
            "dimension": ("dimensions", "Dimensions"),
            "fontFamilies": ("font-family", "Font Family"), "fontFamily": ("font-family", "Font Family"),
            "fontSizes": ("font-size", "Font Size"), "fontSize": ("font-size", "Font Size"),
            "fontWeights": ("font-weight", "Font Weight"), "fontWeight": ("font-weight", "Font Weight"),
            "letterSpacing": ("letter-spacing", "Letter Spacing"),
            "number": ("number", "Number"),
            "opacity": ("opacity", "Opacity"),
            "rotation": ("rotation", "Rotation"),
            "shadow": ("shadow", "Shadow"), "boxShadow": ("shadow", "Shadow"),
            "sizing": ("sizing", "Sizing"),
            "spacing": ("spacing", "Spacing"),
            "borderWidth": ("stroke-width", "Stroke Width"),
            "textCase": ("text-case", "Text Case"),
            "textDecoration": ("text-decoration", "Text Decoration"),
            "typography": ("typography", "Typography"),
            "duration": ("duration", "Duration"),
            "cubicBezier": ("cubic-bezier", "Cubic Bezier"),
            "spring": ("spring", "Spring"),
        ]
        let entry = known[dtcg] ?? (dtcg, dtcg.prefix(1).uppercased() + dtcg.dropFirst())
        key = entry.0
        title = entry.1
    }

    var isColor: Bool { key == "color" }
}

/// Resolves token values the way Penpot shows them: references (`{accent.700}`) replaced
/// by what they resolve to, and arithmetic (`{base} * 3`) worked out, units kept.
struct TokenResolver {
    let tokens: [String: TokenLibrary.Token]

    /// The value with every reference resolved, or `nil` when one can't be (missing,
    /// circular).
    func resolve(_ token: TokenLibrary.Token) -> String? {
        resolve(token.value, depth: 0)
    }

    private func resolve(_ value: String, depth: Int) -> String? {
        guard depth < 32 else { return nil }
        var result = ""
        var rest = Substring(value)
        while let open = rest.firstIndex(of: "{") {
            guard let close = rest[open...].firstIndex(of: "}") else { break }
            result += rest[..<open]
            let name = String(rest[rest.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            guard let token = tokens[name], let resolved = resolve(token.value, depth: depth + 1) else { return nil }
            result += resolved
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return Self.evaluate(result) ?? result
    }

    /// Works out `result` when it is arithmetic on numbers that share one unit (or none),
    /// e.g. `4px * 3` → `12px`; `nil` when it isn't.
    static func evaluate(_ text: String) -> String? {
        var parser = Arithmetic(text)
        guard text.contains(where: { "+*/()".contains($0) }) || text.dropFirst().contains("-"),
              let value = parser.parse() else { return nil }
        return format(value.number) + (value.unit ?? "")
    }

    static func format(_ number: Double) -> String {
        let rounded = (number * 1000).rounded() / 1000
        return rounded.rounded() == rounded ? String(Int(rounded)) : String(rounded)
    }

    /// A tiny recursive-descent parser for `+ - * /` and parentheses.
    private struct Arithmetic {
        struct Value {
            var number: Double
            var unit: String?
        }

        private let characters: [Character]
        private var index = 0
        private var unit: String?
        private var failed = false

        init(_ text: String) { characters = Array(text) }

        mutating func parse() -> Value? {
            let value = expression()
            skipSpaces()
            guard !failed, index == characters.count, let value else { return nil }
            return Value(number: value, unit: unit)
        }

        private mutating func skipSpaces() {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
        }

        private mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while true {
                skipSpaces()
                guard index < characters.count, characters[index] == "+" || characters[index] == "-" else { return value }
                let op = characters[index]
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
        }

        private mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while true {
                skipSpaces()
                guard index < characters.count, characters[index] == "*" || characters[index] == "/" else { return value }
                let op = characters[index]
                index += 1
                guard let rhs = factor() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { failed = true; return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
        }

        private mutating func factor() -> Double? {
            skipSpaces()
            guard index < characters.count else { return nil }
            if characters[index] == "(" {
                index += 1
                let value = expression()
                skipSpaces()
                guard index < characters.count, characters[index] == ")" else { failed = true; return nil }
                index += 1
                return value
            }
            if characters[index] == "-" {
                index += 1
                return factor().map { -$0 }
            }
            let start = index
            while index < characters.count, characters[index].isNumber || characters[index] == "." { index += 1 }
            guard index > start, let number = Double(String(characters[start..<index])) else {
                failed = true
                return nil
            }
            let unitStart = index
            while index < characters.count, characters[index].isLetter || characters[index] == "%" { index += 1 }
            if index > unitStart {
                let found = String(characters[unitStart..<index])
                if let unit, unit != found { failed = true; return nil }
                unit = found
            }
            return number
        }
    }
}

/// A color as a token or a fill writes it: `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`/`rgba()`.
struct ParsedColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        if text == "transparent" {
            (red, green, blue, alpha) = (0, 0, 0, 0)
            return
        }
        if text.hasPrefix("#") {
            var hex = String(text.dropFirst())
            if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
            let hasAlpha = hex.count == 8
            let shift: UInt64 = hasAlpha ? 8 : 0
            red = Double((value >> (16 + shift)) & 0xFF) / 255
            green = Double((value >> (8 + shift)) & 0xFF) / 255
            blue = Double((value >> shift) & 0xFF) / 255
            alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
            return
        }
        guard text.hasPrefix("rgb"), let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") else { return nil }
        let parts = text[text.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")) }
        guard parts.count >= 3 else { return nil }
        red = parts[0] / 255
        green = parts[1] / 255
        blue = parts[2] / 255
        alpha = parts.count > 3 ? (parts[3] > 1 ? parts[3] / 100 : parts[3]) : 1
    }
}

// MARK: - Arbitrary JSON

/// Any JSON value, for parts of `get-file` whose shape varies (the tokens).
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? { if case let .string(value) = self { value } else { nil } }
    var objectValue: [String: JSONValue]? { if case let .object(value) = self { value } else { nil } }
    var arrayValue: [JSONValue]? { if case let .array(value) = self { value } else { nil } }

    /// A token's value as text: composite values (a typography, shadows) as Penpot's
    /// `format-token-value` lists them, one part per line.
    func tokenText(type: String?) -> String {
        switch self {
        case let .string(value): return value
        case let .number(value): return TokenResolver.format(value)
        case let .bool(value): return value ? "true" : "false"
        case .null: return ""
        case let .array(values):
            if values.allSatisfy({ $0.objectValue != nil }) {
                return values.map { $0.tokenText(type: type) }.joined(separator: "\n")
            }
            return values.map { $0.tokenText(type: type) }.joined(separator: ", ")
        case let .object(object):
            return object.sorted { $0.key < $1.key }
                .map { "\(Self.partTitle($0.key)): \($0.value.tokenText(type: nil))" }
                .joined(separator: "\n")
        }
    }

    /// Penpot's names for the parts of a composite token (`category-dictionary`).
    private static func partTitle(_ key: String) -> String {
        let titles = ["fontSize": "Font Size", "fontFamily": "Font Family", "fontFamilies": "Font Family",
                      "fontWeight": "Font Weight", "fontWeights": "Font Weight", "lineHeight": "Line Height",
                      "lineHeights": "Line Height", "letterSpacing": "Letter Spacing", "textCase": "Text Case",
                      "textDecoration": "Text Decoration", "offsetX": "X", "offsetY": "Y", "x": "X", "y": "Y",
                      "blur": "Blur", "spread": "Spread", "color": "Color", "inset": "Inner Shadow"]
        return titles[key] ?? key
    }
}
