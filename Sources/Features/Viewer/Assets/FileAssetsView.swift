import SwiftUI

/// A file's library, read only, as Penpot's workspace shows it: the Assets tab
/// (`sidebar/assets/*`: components, graphics, colors, typographies, in groups by path)
/// and the Tokens tab (`tokens/management.cljs`: one set's tokens by type, resolved
/// against the active sets). A tap copies what a developer needs: a color's hex, a
/// typography's CSS, a token's value; a component opens like a board, Inspect included.
struct FileAssetsView: View {
    @Environment(AppState.self) private var appState
    @Environment(LiveFile.self) private var live: LiveFile?
    let fileID: String
    let teamID: String?
    let revision: Int?
    let assets: FileAssets
    let pages: [CanvasPage]

    enum Tab: Hashable { case assets, tokens }

    enum Kind: Hashable { case components, graphics, colors, typographies }

    @State private var tab: Tab = .assets
    @State private var query = ""
    @State private var collapsed: Set<Kind> = []
    /// Main copy id → Penpot's thumbnail of the component, where the editor made one.
    @State private var componentThumbnails: [String: String] = [:]
    @State private var customFonts: [FontVariant]?
    @State private var selectedSetName: String?
    @State private var showsCopied = false
    @State private var copiedTask: Task<Void, Never>?

    private var renders: BoardRenders? {
        guard let client = appState.client else { return nil }
        return BoardRenders(client: client, fileID: fileID, revision: revision,
                            profileID: appState.profile?.id ?? UUID().uuidString.lowercased(), teamID: teamID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if assets.tokens != nil {
                    PenpotSegmentedPicker(selection: $tab, segments: [
                        (.assets, Text("Assets")),
                        (.tokens, Text("Tokens")),
                    ])
                }
                switch tab {
                case .assets: assetsContent
                case .tokens: tokensContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .penpotPageBackground()
        .searchable(text: $query)
        .navigationTitle("Assets")
        .navigationBarTitleDisplayMode(.inline)
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
            }
        }
        .task { await loadExtras() }
    }

    // MARK: Assets

    @ViewBuilder
    private var assetsContent: some View {
        let components = assets.components.matching(query)
        let media = assets.media.matching(query)
        let colors = assets.colors.matching(query)
        let typographies = assets.typographies.matching(query)
        if components.isEmpty && media.isEmpty && colors.isEmpty && typographies.isEmpty {
            noResults
        }
        if !components.isEmpty {
            section(.components, title: Text("Components"), icon: .component, count: components.count) {
                ForEach(components.grouped, id: \.path) { group in
                    groupHeader(group.path)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                        ForEach(group.assets) { component in componentTile(component) }
                    }
                }
            }
        }
        if !media.isEmpty {
            section(.graphics, title: Text("Graphics"), icon: .image, count: media.count) {
                ForEach(media.grouped, id: \.path) { group in
                    groupHeader(group.path)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                        ForEach(group.assets) { item in mediaTile(item) }
                    }
                }
            }
        }
        if !colors.isEmpty {
            section(.colors, title: Text("Colors"), icon: .swatches, count: colors.count) {
                ForEach(colors.grouped, id: \.path) { group in
                    groupHeader(group.path)
                    PenpotCard {
                        ForEach(Array(group.assets.enumerated()), id: \.element.id) { index, color in
                            if index > 0 { PenpotCardDivider() }
                            colorRow(color)
                        }
                    }
                }
            }
        }
        if !typographies.isEmpty {
            section(.typographies, title: Text("Typographies"), icon: .typography, count: typographies.count) {
                ForEach(typographies.grouped, id: \.path) { group in
                    groupHeader(group.path)
                    PenpotCard {
                        ForEach(Array(group.assets.enumerated()), id: \.element.id) { index, typography in
                            if index > 0 { PenpotCardDivider() }
                            typographyRow(typography)
                        }
                    }
                }
            }
        }
    }

    private var noResults: some View {
        Text(query.isEmpty ? "No assets" : "No results")
            .font(.workSans(.callout))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    /// A collapsible section, like Penpot's: title, count, chevron.
    private func section<Content: View>(_ kind: Kind, title: Text, icon: AppIcon, count: Int,
                                        @ViewBuilder content: () -> Content) -> some View {
        let isOpen = !collapsed.contains(kind)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen { collapsed.insert(kind) } else { collapsed.remove(kind) }
                }
            } label: {
                HStack(spacing: 8) {
                    AppIcon.chevronRight.image(size: 12)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(.secondary)
                    icon.image(size: 16)
                    title.font(.workSans(.headline, weight: .semibold))
                    Text(verbatim: count.formatted())
                        .font(.workSans(.subheadline))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
            if isOpen { content() }
        }
    }

    @ViewBuilder
    private func groupHeader(_ path: String) -> some View {
        if !path.isEmpty {
            Text(verbatim: path)
                .font(.workSans(.footnote, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func componentTile(_ component: LibraryComponent) -> some View {
        if let board = component.mainInstance, let baseURL = appState.client?.baseURL {
            NavigationLink {
                BoardDetailView(fileID: fileID, board: board, mediaID: componentThumbnails[board.id],
                                baseURL: baseURL, revision: revision, teamID: teamID, pages: pages)
                    .environment(live)
            } label: {
                AssetTile(name: component.name, detail: component.variantSummary) {
                    AssetPicture(id: board.id) { await renders?.picture(of: board, mediaID: componentThumbnails[board.id]) }
                }
            }
            .buttonStyle(.plain)
        } else {
            // A component of a file from before components v2: its shapes aren't on a page.
            AssetTile(name: component.name, detail: component.variantSummary) {
                AppIcon.component.image(size: 28).foregroundStyle(.secondary)
            }
        }
    }

    private func mediaTile(_ media: LibraryMedia) -> some View {
        AssetTile(name: media.name, detail: dimensions(media), inset: 24) {
            AssetPicture(id: "media-\(media.id)") {
                guard let client = appState.client else { return nil }
                if !media.isSVG, let image = await RemoteImageLoader.shared.image(at: media.url(server: client.baseURL)) {
                    return image
                }
                return await renders?.picture(of: PenpotSVG.mediaDrawing(media, server: client.baseURL),
                                              id: "media-\(media.id)", name: media.name, pixels: 400)
            }
        }
    }

    private func dimensions(_ media: LibraryMedia) -> String? {
        guard let width = media.width, let height = media.height else { return nil }
        return "\(LibraryTypography.format(width)) × \(LibraryTypography.format(height))"
    }

    private func colorRow(_ color: LibraryColor) -> some View {
        Button { copy(color.color.map { $0.uppercased() } ?? color.valueText) } label: {
            PenpotCardRow(showsChevron: false) {
                HStack(spacing: 12) {
                    AssetSwatch(color: color, baseURL: appState.client?.baseURL)
                    Text(verbatim: color.name).lineLimit(1)
                }
            } trailing: {
                Text(verbatim: color.valueText)
                    .font(.workSans(.footnote))
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Copy to clipboard"))
    }

    private func typographyRow(_ typography: LibraryTypography) -> some View {
        Button { copy(typography.css) } label: {
            PenpotCardRow(showsChevron: false) {
                HStack(spacing: 12) {
                    AssetPicture(id: "typography-\(typography.id)", template: true) {
                        guard let client = appState.client else { return nil }
                        let fonts = await fontsFor(typography)
                        return await renders?.picture(
                            of: PenpotSVG.typographySample(typography, server: client.baseURL, customFonts: fonts),
                            id: "typography-\(typography.id)", name: typography.name, pixels: 192)
                    }
                    .frame(width: 48, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: typography.name).lineLimit(1)
                        Text(verbatim: typography.fontDescription)
                            .font(.workSans(.footnote))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(verbatim: typography.metricsDescription)
                            .font(.workSans(.footnote))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Copy to clipboard"))
    }

    // MARK: Tokens

    @ViewBuilder
    private var tokensContent: some View {
        if let tokens = assets.tokens, let set = selectedSet(in: tokens) {
            let resolver = tokens.resolver(selecting: set)
            PenpotCard {
                PenpotCardRow(showsChevron: false) {
                    Text("Set")
                } trailing: {
                    PenpotMenuPicker(title: "Set", selection: Binding(
                        get: { set.name },
                        set: { selectedSetName = $0 }
                    ), options: tokens.sets.map { ($0.name, Text(verbatim: $0.name)) })
                }
                if !tokens.activeThemes.isEmpty {
                    PenpotCardDivider()
                    PenpotCardRow(showsChevron: false) {
                        Text("Themes")
                    } trailing: {
                        Text(verbatim: tokens.activeThemes.map { $0.split(separator: "/").last.map(String.init) ?? $0 }
                                .joined(separator: ", "))
                            .font(.workSans(.footnote))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            if !tokens.isActive(set) {
                // Penpot marks a set no active theme turns on; its tokens apply to nothing.
                Text("Inactive")
                    .font(.workSans(.footnote))
                    .foregroundStyle(.secondary)
            }
            let shown = set.tokens.filter {
                query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                    || $0.value.localizedCaseInsensitiveContains(query)
            }
            if shown.isEmpty {
                noResults
            }
            ForEach(TokenLibrary.groups(shown), id: \.type) { group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        // Penpot's type names, English in Penpot too.
                        Text(verbatim: group.type.title).font(.workSans(.headline, weight: .semibold))
                        Text(verbatim: group.tokens.count.formatted())
                            .font(.workSans(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    PenpotCard {
                        ForEach(Array(group.tokens.enumerated()), id: \.element.id) { index, token in
                            if index > 0 { PenpotCardDivider() }
                            tokenRow(token, type: group.type, resolved: resolver.resolve(token))
                        }
                    }
                }
            }
        }
    }

    /// The picked set, else the first active one, else the first.
    private func selectedSet(in tokens: TokenLibrary) -> TokenLibrary.TokenSet? {
        tokens.sets.first { $0.name == selectedSetName }
            ?? tokens.sets.first(where: tokens.isActive)
            ?? tokens.sets.first
    }

    private func tokenRow(_ token: TokenLibrary.Token, type: TokenType, resolved: String?) -> some View {
        let shown = resolved ?? token.value
        return Button { copy(shown) } label: {
            HStack(alignment: .top, spacing: 12) {
                if type.isColor {
                    TokenSwatch(color: ParsedColor(shown))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: token.name)
                        .font(.workSans(.callout, weight: .medium))
                        .lineLimit(2)
                    // The value, and what it is written as when that is a reference or a
                    // formula.
                    (Text(verbatim: shown)
                        .foregroundStyle(resolved == nil ? Color.penpotDangerText : .primary)
                     + Text(verbatim: resolved != token.value ? "  \(token.value)" : "")
                        .foregroundStyle(.secondary))
                        .font(.system(.footnote, design: .monospaced))
                    if let description = token.description, !description.isEmpty {
                        Text(verbatim: description)
                            .font(.workSans(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Copy to clipboard"))
    }

    // MARK: Loading

    /// Penpot's component thumbnails, where its editor made them (`<file>/<page>/<id>/component`).
    private func loadExtras() async {
        guard let client = appState.client, !assets.components.isEmpty else { return }
        if let raw = try? await client.objectThumbnailKeys(fileID: fileID) {
            componentThumbnails = PenpotClient.componentThumbnails(from: raw)
        }
    }

    /// Team fonts, fetched once, for typographies in one.
    private func fontsFor(_ typography: LibraryTypography) async -> [FontVariant] {
        guard typography.fontId.hasPrefix("custom-"), let teamID, let client = appState.client else { return [] }
        if let customFonts { return customFonts }
        let fonts = (try? await client.fontVariants(teamID: teamID)) ?? []
        customFonts = fonts
        return fonts
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

/// A component or graphic in the grid: its picture on Penpot's canvas color (what the
/// assets panel draws them on, `--assets-component-background-color`), the name below.
private struct AssetTile<Picture: View>: View {
    let name: String
    let detail: String?
    /// Room around the picture: graphics are mostly icons drawn to their edges.
    var inset: CGFloat = 10
    @ViewBuilder let picture: Picture

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0xE8 / 255, green: 0xE9 / 255, blue: 0xEA / 255))
                .aspectRatio(1, contentMode: .fit)
                .overlay { picture.padding(inset) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(verbatim: name)
                .font(.workSans(.footnote))
                .lineLimit(1)
            if let detail {
                Text(verbatim: detail)
                    .font(.workSans(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A picture drawn on demand, the pencil while it comes. `template` draws it in the text
/// color (a typography's black sample in dark mode too).
private struct AssetPicture: View {
    let id: String
    var template = false
    let load: () async -> UIImage?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: template ? image.withRenderingMode(.alwaysTemplate) : image)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
            } else if failed {
                AppIcon.image.image(size: 22).foregroundStyle(.secondary)
            } else {
                PencilLoaderView().frame(width: 28)
            }
        }
        .task(id: id) {
            image = await load()
            failed = image == nil
        }
    }
}

/// A library color as Penpot's swatch: solid, a gradient, or an image fill.
private struct AssetSwatch: View {
    let color: LibraryColor
    let baseURL: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay {
                if let image = color.image, let baseURL {
                    RemoteImage(url: RemoteImageLoader.shared.assetURL(mediaID: image.id, baseURL: baseURL),
                                contentMode: .fill) { Color.clear }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator)))
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        if let hex = color.color, let parsed = ParsedColor(hex) {
            return AnyShapeStyle(Color(parsed, opacity: color.opacity ?? 1))
        }
        if let gradient = color.gradient, !gradient.stops.isEmpty {
            let stops = gradient.stops.compactMap { stop in
                ParsedColor(stop.color).map { Gradient.Stop(color: Color($0, opacity: stop.opacity ?? 1), location: stop.offset) }
            }
            if gradient.type == "radial" {
                return AnyShapeStyle(RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: 14))
            }
            let start = UnitPoint(x: gradient.startX ?? 0.5, y: gradient.startY ?? 0)
            let end = UnitPoint(x: gradient.endX ?? 0.5, y: gradient.endY ?? 1)
            return AnyShapeStyle(LinearGradient(stops: stops, startPoint: start, endPoint: end))
        }
        return AnyShapeStyle(Color.clear)
    }
}

/// A color token's swatch; one that doesn't resolve to a color shows empty.
private struct TokenSwatch: View {
    let color: ParsedColor?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color.map { Color($0, opacity: 1) } ?? Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator)))
            .frame(width: 24, height: 24)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }
}

extension Color {
    init(_ parsed: ParsedColor, opacity: Double) {
        self.init(.sRGB, red: parsed.red, green: parsed.green, blue: parsed.blue, opacity: parsed.alpha * opacity)
    }
}
