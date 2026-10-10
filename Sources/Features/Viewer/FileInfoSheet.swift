import SwiftUI

/// A file's metrics from `get-file-stats`: pages, layers (by type), assets, library links
/// and the last change. Counts only, so it's cheap even for huge files. Degrades to an
/// "unsupported" state on servers older than Penpot 2.17.
struct FileInfoSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let fileID: String
    let fileName: String

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case ready(FileStats)
        case failed(String)
        /// The server predates `get-file-stats` (< Penpot 2.17).
        case unsupported
    }

    var body: some View {
        NavigationStack {
            content
                .penpotPageBackground()
                .navigationTitle("File info")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            LoadingView(message: "Loading…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .unsupported:
            EmptyStateView(title: "File info unavailable", icon: .info,
                           description: "This Penpot server doesn't support file statistics (requires Penpot 2.17 or later).")
        case .ready(let stats):
            details(stats)
        }
    }

    private func details(_ stats: FileStats) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(fileName)
                    .font(.workSans(.title3, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                section("Contents") {
                    countRow("Pages", stats.pageCount)
                    PenpotCardDivider()
                    countRow("Layers", stats.shapeCounts?.total)
                    PenpotCardDivider()
                    countRow("Components", stats.componentCount)
                    PenpotCardDivider()
                    countRow("Colors", stats.colorCount)
                    PenpotCardDivider()
                    countRow("Typographies", stats.typographyCount)
                }

                let layerTypes = stats.layerTypes
                if !layerTypes.isEmpty {
                    section("Layers by type") {
                        ForEach(Array(layerTypes.enumerated()), id: \.element.type) { index, entry in
                            PenpotCardRow(showsChevron: false) {
                                layerTypeName(entry.type)
                            } trailing: {
                                Text(entry.count, format: .number)
                            }
                            if index < layerTypes.count - 1 {
                                PenpotCardDivider()
                            }
                        }
                    }
                }

                section("Libraries") {
                    countRow("Connected libraries", stats.libraryCount)
                    // Only meaningful for a shared library; zero for every other file.
                    if let referencedBy = stats.referencedByCount, referencedBy > 0 {
                        PenpotCardDivider()
                        countRow("Files using this library", referencedBy)
                    }
                }

                section("Details") {
                    PenpotCardRow(showsChevron: false) {
                        Text("Last modified")
                    } trailing: {
                        Text(PenpotDate.relative(from: stats.updatedAt, locale: locale))
                    }
                    if let revn = stats.revn {
                        PenpotCardDivider()
                        PenpotCardRow(showsChevron: false) {
                            Text("Revision")
                        } trailing: {
                            Text(revn, format: .number)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable { await load(showsSpinner: false) }
    }

    // MARK: Rows

    private func section<Rows: View>(_ title: LocalizedStringKey,
                                     @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.workSans(.caption, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(Color.penpotIconGray)
                .frame(maxWidth: .infinity, alignment: .leading)
            PenpotCard { rows() }
        }
    }

    private func countRow(_ title: LocalizedStringKey, _ count: Int?) -> some View {
        PenpotCardRow(showsChevron: false) {
            Text(title)
        } trailing: {
            Text(count ?? 0, format: .number)
        }
    }

    /// Penpot's own names for its shape types (a board is a `frame` internally).
    private func layerTypeName(_ type: String) -> Text {
        switch type {
        case "frame": Text("Boards")
        case "rect": Text("Rectangles")
        case "circle": Text("Ellipses")
        case "text": Text("Texts")
        case "path": Text("Paths")
        case "group": Text("Groups")
        case "bool": Text("Boolean groups")
        case "image": Text("Images")
        case "svgRaw", "svg-raw": Text("SVGs")
        default: Text(verbatim: type)
        }
    }

    // MARK: Loading

    private func load(showsSpinner: Bool = true) async {
        guard let client = appState.client else { return }
        if showsSpinner { phase = .loading }
        do {
            phase = .ready(try await client.fileStats(fileID: fileID))
        } catch let error as PenpotError where error.isUnknownCommand {
            phase = .unsupported
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
