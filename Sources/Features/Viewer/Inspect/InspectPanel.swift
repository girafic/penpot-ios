import SwiftUI
import UIKit

/// Penpot's inspect sidebar (`ui/inspect/right_sidebar.cljs`) for one shape: its "Info"
/// tab, the attribute panels in Penpot's order for its type (`attributes.cljs`
/// `type->options`), and its "Code" tab, the shape's CSS (``InspectCSS``).
///
/// Every row copies what Penpot's copy button beside it copies (`property: value;`), a
/// section's title copies the whole section. Penpot leaves CSS property names and a few
/// titles ("Visibility", "Layout", "Font Family", …) untranslated; so does this panel.
///
/// Touch has no hover and no layers sidebar, so the path above the tabs selects a
/// shape's parents: the only way to a group, which is never under a finger by itself.
struct InspectPanel: View {
    let board: InspectBoard
    @Binding var selectedID: String
    let onClose: () -> Void

    @State private var tab: Tab = .info
    /// Penpot's "Select color space".
    @State private var colorFormat: InspectCSS.ColorFormat = .hex
    @State private var showsCopied = false
    @State private var copiedTask: Task<Void, Never>?

    enum Tab: Hashable { case info, code }

    private var shape: InspectBoard.Object { board.shape(selectedID) ?? [:] }
    private var objects: [String: InspectBoard.Object] { board.objects }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 12) {
                PenpotSegmentedPicker(selection: $tab, segments: [(.info, Text("Info")), (.code, Text("Code"))])
                if tab == .info {
                    Menu {
                        PenpotMenuChoices(selection: $colorFormat, options: InspectCSS.ColorFormat.allCases.map {
                            ($0, Text(verbatim: $0.rawValue.uppercased()))
                        })
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: colorFormat.rawValue.uppercased())
                                .font(.workSans(.caption, weight: .semibold))
                            AppIcon.chevronDown.image(size: 12)
                        }
                        .foregroundStyle(Color.penpotIconGray)
                    }
                    .accessibilityLabel("Select color space")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            ScrollView {
                Group {
                    switch tab {
                    case .info: info
                    case .code: code
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            // Another tab or shape starts at its top.
            .id("\(tab)|\(selectedID)")
        }
        .background(Color.penpotPage)
        .overlay(alignment: .bottom) {
            if showsCopied {
                Text("Copied to clipboard")
                    .font(.workSans(.footnote, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.penpotSurface))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(verbatim: board.name(selectedID))
                    .font(.workSans(.headline, weight: .semibold))
                    .lineLimit(1)
                typeName(selectedID)
                    .font(.workSans(.caption, weight: .medium))
                    .foregroundStyle(Color.penpotIconGray)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onClose) { AppIcon.closeFilled.image(size: 16) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.penpotIconGray)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Close")
            }
            breadcrumb
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    /// The board down to the shape's parent, each a tap away.
    @ViewBuilder
    private var breadcrumb: some View {
        let path = board.path(to: selectedID)
        if path.count > 1 {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(path.enumerated()), id: \.element) { index, id in
                            if index > 0 {
                                AppIcon.chevronRight.image(size: 10)
                                    .foregroundStyle(.tertiary)
                            }
                            Button { selectedID = id } label: {
                                Text(verbatim: board.name(id))
                                    .font(.workSans(.caption, weight: id == selectedID ? .semibold : .regular))
                                    .foregroundStyle(id == selectedID ? Color.primary : Color.penpotAccent)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .disabled(id == selectedID)
                            .id(id)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(selectedID, anchor: .trailing) }
                .onChange(of: selectedID) { _, id in proxy.scrollTo(id, anchor: .trailing) }
            }
        }
    }

    /// Penpot's names for what is selected (`inspect.tabs.code.selected.*`).
    private func typeName(_ id: String) -> Text {
        let shape = board.shape(id) ?? [:]
        switch board.type(id) {
        case "frame":
            return shape["mainInstance"] as? Bool == true ? Text("Component") : Text("Board")
        case "group": return shape["maskedGroup"] as? Bool == true ? Text("Mask") : Text("Group")
        case "rect": return Text("Rectangle")
        case "circle": return Text("Circle")
        case "text": return Text("Text")
        case "image": return Text("Image")
        case "svg-raw", "svgRaw": return Text(verbatim: "SVG")
        default: return Text("Path")
        }
    }

    // MARK: - Info

    private var type: String { board.type(selectedID) }

    /// Penpot's panels for the shape's type, in its order (``InspectCSS/panels(forType:)``).
    /// Penpot shows none for images, boolean groups and imported SVG, only their exports,
    /// which the app doesn't have: they get their size and position.
    @ViewBuilder
    private var info: some View {
        let panels = InspectCSS.panels(forType: type)
        VStack(spacing: 16) {
            // Penpot's empty state, while the board itself is selected.
            if selectedID == board.boardID {
                Text("Select a shape, board or group to inspect their properties and code")
                    .font(.workSans(.footnote))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(panels.isEmpty ? ["geometry"] : panels, id: \.self) { panel in
                switch panel {
                case "visibility": cssSection(Text(verbatim: "Visibility"), InspectCSS.visibilityProperties)
                case "geometry": cssSection(Text("Size and position"), InspectCSS.geometryProperties)
                case "fill": fills
                case "stroke": strokes
                case "shadow": shadows
                case "blur": blurs
                case "layout": cssSection(Text(verbatim: "Layout"), InspectCSS.layoutProperties)
                case "layout-element":
                    if let parentLayout {
                        cssSection(Text(verbatim: parentLayout == "grid" ? "Grid element" : "Flex element"),
                                   InspectCSS.layoutElementProperties)
                    }
                case "text": typography
                default: EmptyView()
                }
            }
        }
    }

    /// The layout of the shape's parent board, if it has one: the shape is its element.
    private var parentLayout: String? {
        guard let parent = shape["parentId"] as? String, parent != selectedID,
              shape["layoutItemAbsolute"] as? Bool != true,
              let layout = objects[parent]?["layout"] as? String, !layout.isEmpty else { return nil }
        return layout
    }

    /// A panel of CSS rows, left out when the shape has none of its properties.
    @ViewBuilder
    private func cssSection(_ title: Text, _ properties: [String]) -> some View {
        let rows = properties.compactMap { property -> (String, String)? in
            InspectCSS.value(property, shape: shape, objects: objects, format: colorFormat).map { (property, $0) }
        }
        if !rows.isEmpty {
            section(title, copy: InspectCSS.declarations(properties, shape: shape, objects: objects, format: colorFormat)) {
                ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                    if index > 0 { PenpotCardDivider() }
                    valueRow(Text(verbatim: InspectCSS.humanized(row.0)), row.1,
                             copy: InspectCSS.declaration(row.0, shape: shape, objects: objects, format: colorFormat) ?? row.1)
                }
            }
        }
    }

    @ViewBuilder
    private var fills: some View {
        let fills = board.fills(selectedID)
        if !fills.isEmpty {
            section(Text("Fill"), copy: InspectCSS.declarations(["background"], shape: shape, objects: objects,
                                                                 format: colorFormat)) {
                ForEach(Array(fills.enumerated()), id: \.offset) { index, fill in
                    if index > 0 { PenpotCardDivider() }
                    // `fill-block`: a "Background" row copying the fill as CSS.
                    paintRows(fill.paint, copy: InspectCSS.declarations(
                        ["background", "background-color", "background-image"],
                        shape: ["fills": [fill.raw]], objects: objects, format: colorFormat))
                }
            }
        }
    }

    @ViewBuilder
    private var strokes: some View {
        let strokes = board.strokes(selectedID)
        if !strokes.isEmpty {
            section(Text("Stroke"), copy: InspectCSS.declarations(["border"], shape: shape, objects: objects,
                                                                   format: colorFormat)) {
                ForEach(Array(strokes.enumerated()), id: \.offset) { index, stroke in
                    if index > 0 { PenpotCardDivider() }
                    paintRows(stroke.paint, copy: InspectCSS.declaration("border-color", shape: stroke.raw,
                                                                         objects: objects, format: colorFormat))
                    // `stroke-block`: style and width, or each side's width where they differ.
                    ForEach(InspectCSS.strokeProperties(stroke.raw), id: \.self) { property in
                        if let value = InspectCSS.value(property, shape: stroke.raw, objects: objects) {
                            PenpotCardDivider()
                            valueRow(Text(verbatim: InspectCSS.humanized(property)), value,
                                     copy: InspectCSS.declaration(property, shape: stroke.raw, objects: objects) ?? value)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var shadows: some View {
        let shadows = board.shadows(selectedID)
        if !shadows.isEmpty {
            section(Text("Shadow"), copy: InspectCSS.declarations(["box-shadow"], shape: shape, objects: objects,
                                                                   format: colorFormat)) {
                ForEach(Array(shadows.enumerated()), id: \.offset) { index, shadow in
                    if index > 0 { PenpotCardDivider() }
                    let values = [shadow.offsetX, shadow.offsetY, shadow.blur, shadow.spread]
                        .map { "\(InspectBoard.trim($0))px" }.joined(separator: " ")
                    valueRow(shadow.inner ? Text("Inner shadow") : Text("Drop shadow"), values,
                             copy: InspectCSS.declarations(["box-shadow"], shape: shape, objects: objects,
                                                           format: colorFormat))
                    PenpotCardDivider()
                    paintRows(shadow.paint)
                }
            }
        }
    }

    @ViewBuilder
    private var blurs: some View {
        let blurs = board.blurs(selectedID)
        if blurs.layer != nil || blurs.background != nil {
            section(Text("Blur"), copy: InspectCSS.declarations(["filter", "backdrop-filter"], shape: shape, objects: objects)) {
                if let layer = blurs.layer {
                    valueRow(Text("Layer blur"), "\(InspectBoard.trim(layer))px", copy: "filter: blur(\(InspectBoard.trim(layer))px);")
                }
                if let background = blurs.background {
                    if blurs.layer != nil { PenpotCardDivider() }
                    valueRow(Text("Background blur"), "\(InspectBoard.trim(background))px",
                             copy: "backdrop-filter: blur(\(InspectBoard.trim(background))px);")
                }
            }
        }
    }

    /// `text-block`: one card per stretch of the text in one style, then its text.
    @ViewBuilder
    private var typography: some View {
        let runs = board.textRuns(selectedID)
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(Text("Typography"))
                ForEach(runs) { run in
                    PenpotCard { typographyRows(run) }
                }
            }
        }
    }

    @ViewBuilder
    private func typographyRows(_ run: InspectBoard.TextRun) -> some View {
        valueRow(Text(verbatim: "Font Family"), run.fontName, copy: "font-family: \"\(run.fontFamily)\";")
        PenpotCardDivider()
        valueRow(Text(verbatim: "Font Style"), run.fontStyle, copy: "font-style: \(run.fontStyle);")
        PenpotCardDivider()
        valueRow(Text(verbatim: "Font Size"), "\(InspectBoard.trim(run.fontSize))px",
                 copy: "font-size: \(InspectBoard.trim(run.fontSize))px;")
        PenpotCardDivider()
        valueRow(Text(verbatim: "Font Weight"), run.fontWeight, copy: "font-weight: \(run.fontWeight);")
        PenpotCardDivider()
        valueRow(Text(verbatim: "Line Height"), InspectBoard.trim(run.lineHeight),
                 copy: "line-height: \(InspectBoard.trim(run.lineHeight));")
        PenpotCardDivider()
        valueRow(Text(verbatim: "Letter Spacing"), "\(InspectBoard.trim(run.letterSpacing))px",
                 copy: "letter-spacing: \(InspectBoard.trim(run.letterSpacing))px;")
        if run.textDecoration != "none" {
            PenpotCardDivider()
            valueRow(Text(verbatim: "Text Decoration"), decorationName(run.textDecoration),
                     copy: "text-decoration: \(run.textDecoration);")
        }
        if run.textTransform != "none" {
            PenpotCardDivider()
            valueRow(Text(verbatim: "Text Transform"), transformName(run.textTransform),
                     copy: "text-transform: \(run.textTransform);")
        }
        ForEach(Array(run.fills.enumerated()), id: \.offset) { _, paint in
            PenpotCardDivider()
            paintRows(paint)
        }
        PenpotCardDivider()
        Button { copy(run.text) } label: {
            Text(verbatim: run.text)
                .font(.workSans(.footnote))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Copy to clipboard"))
    }

    private func decorationName(_ value: String) -> LocalizedStringKey {
        switch value {
        case "underline": "Underline"
        case "line-through": "Strikethrough"
        default: "None"
        }
    }

    private func transformName(_ value: String) -> LocalizedStringKey {
        switch value {
        case "uppercase": "Upper Case"
        case "lowercase": "Lower Case"
        case "capitalize": "Capitalize"
        default: "None"
        }
    }

    // MARK: - Code

    private var code: some View {
        let css = InspectCSS.stylesheet([selectedID], objects: objects, prelude: false)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(Text(verbatim: "CSS"))
                Button { copy(css) } label: { AppIcon.copy.image }
                    .buttonStyle(.penpot(.ghost, size: .compact))
                    .accessibilityLabel("Copy to clipboard")
            }
            Text(verbatim: css)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.penpotSurface))
        }
    }

    // MARK: - Rows

    private func section<Rows: View>(_ title: Text, copy declarations: String,
                                     @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(title)
                if !declarations.isEmpty {
                    Button { copy(declarations) } label: { AppIcon.copy.image(size: 14) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.penpotIconGray)
                        .accessibilityLabel("Copy to clipboard")
                }
            }
            PenpotCard { rows() }
        }
    }

    private func sectionTitle(_ title: Text) -> some View {
        title
            .font(.workSans(.caption, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Color.penpotIconGray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueRow(_ label: Text, _ value: String, copy text: String) -> some View {
        valueRow(label, Text(verbatim: value), copy: text)
    }

    private func valueRow(_ label: Text, _ value: LocalizedStringKey, copy text: String) -> some View {
        valueRow(label, Text(value), copy: text)
    }

    private func valueRow(_ label: Text, _ value: Text, swatch: InspectBoard.Paint? = nil,
                          copy text: String) -> some View {
        Button { copy(text) } label: {
            PenpotCardRow(showsChevron: false) {
                label.font(.workSans(.footnote))
                    .foregroundStyle(.secondary)
            } trailing: {
                HStack(spacing: 6) {
                    if let swatch { Swatch(paint: swatch) }
                    value.font(.workSans(.footnote))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Copy to clipboard"))
    }

    /// Penpot's `color-row`: a swatch and the color in the chosen color space (the hex with
    /// the opacity beside it), a gradient's stops. `copy` is what its copy button copies.
    @ViewBuilder
    private func paintRows(_ paint: InspectBoard.Paint, copy: String? = nil) -> some View {
        switch paint.kind {
        case .color(let hex):
            valueRow(Text("Color"), Text(verbatim: colorText(hex, opacity: paint.opacity)),
                     swatch: paint, copy: copy ?? InspectCSS.color(hex, opacity: paint.opacity, format: colorFormat))
        case .linearGradient(let stops), .radialGradient(let stops):
            let isLinear = if case .linearGradient = paint.kind { true } else { false }
            valueRow(isLinear ? Text("Linear gradient") : Text("Radial gradient"), Text(verbatim: ""),
                     swatch: paint, copy: copy ?? "")
            ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                PenpotCardDivider()
                valueRow(Text(verbatim: "\(InspectBoard.trim(stop.offset * 100))%"),
                         Text(verbatim: colorText(stop.color, opacity: stop.opacity)),
                         swatch: .init(kind: .color(stop.color), opacity: stop.opacity),
                         copy: InspectCSS.color(stop.color, opacity: stop.opacity, format: colorFormat))
            }
        case .image(let name, let width, let height):
            valueRow(Text("Image"), Text(verbatim: "\(name) \(InspectBoard.trim(width)) x \(InspectBoard.trim(height))"),
                     copy: copy ?? name)
        }
    }

    /// HEX: the color and its opacity apart, as Penpot shows them; RGBA, HSLA: the CSS value.
    private func colorText(_ hex: String, opacity: Double) -> String {
        colorFormat == .hex
            ? "\(hex.uppercased())  \(InspectBoard.trim(opacity * 100))%"
            : InspectCSS.color(hex, opacity: opacity, format: colorFormat)
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.2)) { showsCopied = true }
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { showsCopied = false }
        }
    }
}

/// A fill's color as a small rounded square; a gradient as itself.
private struct Swatch: View {
    let paint: InspectBoard.Paint

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fill)
            .frame(width: 16, height: 16)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(.separator)))
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        switch paint.kind {
        case .color(let hex):
            AnyShapeStyle(Color(uiColor: UIColor(penpotHex: hex) ?? .clear).opacity(paint.opacity))
        case .linearGradient(let stops), .radialGradient(let stops):
            AnyShapeStyle(LinearGradient(stops: stops.map {
                .init(color: Color(uiColor: UIColor(penpotHex: $0.color) ?? .clear).opacity($0.opacity),
                      location: $0.offset)
            }, startPoint: .leading, endPoint: .trailing))
        case .image:
            AnyShapeStyle(Color.penpotIconGray)
        }
    }
}
