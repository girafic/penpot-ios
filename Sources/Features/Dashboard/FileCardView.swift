import SwiftUI

/// A file's preview thumbnail (the first available board) in a rounded, bordered box.
/// Shared by the card (grid) and row (list) presentations.
private struct FileThumbnailView: View {
    let file: FileListItem
    let baseURL: URL?
    var badgeSize: CGFloat = 28

    @Environment(AppState.self) private var appState
    @State private var thumbnailMediaID: String? = nil
    @State private var didLoad = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
            if let baseURL {
                RemoteImage(mediaID: thumbnailMediaID, baseURL: baseURL, contentMode: .fit)
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
        .overlay(alignment: .topTrailing) {
            if file.isShared == true {
                SharedLibraryBadge(size: badgeSize).padding(6)
            }
        }
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard !didLoad, let client = appState.client else { return }
        didLoad = true
        // The file-level cover (what the web dashboard shows) needs no extra request.
        if let cover = file.thumbnailId {
            thumbnailMediaID = cover
            return
        }
        // Fallback for files without one: a board thumbnail, picked deterministically —
        // Dictionary.values.first varies per launch and made covers appear to shuffle.
        let map = try? await client.objectThumbnails(fileID: file.id)
        thumbnailMediaID = map?.sorted(by: { $0.key < $1.key }).first?.value
    }
}

/// Toolbar button flipping file listings between the grid and list presentations.
/// Shows the layout it switches *to*; the choice persists via ``AppSettings``.
struct FilesLayoutToggle: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button {
            withAnimation { settings.filesLayout = settings.filesLayout.toggled }
        } label: {
            (settings.filesLayout == .grid ? AppIcon.listLayout : AppIcon.gridLayout).image
        }
        .accessibilityLabel(settings.filesLayout == .grid ? "View as List" : "View as Grid")
    }
}

/// A file card showing a preview thumbnail and the file name — the grid presentation.
struct FileCardView: View {
    let file: FileListItem
    let baseURL: URL?

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FileThumbnailView(file: file, baseURL: baseURL)
                .frame(height: 110)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.workSans(.subheadline))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                let modified = PenpotDate.relative(from: file.modifiedAt, locale: locale)
                if !modified.isEmpty {
                    Text(modified)
                        .font(.workSans(.caption))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A compact file row with a small thumbnail — the list presentation.
struct FileRowView: View {
    let file: FileListItem
    let baseURL: URL?
    /// Optional context shown before the modified date (e.g. the containing project in
    /// search results).
    var subtitle: String? = nil

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnailView(file: file, baseURL: baseURL, badgeSize: 18)
                .frame(width: 72, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.workSans(.subheadline))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                let modified = PenpotDate.relative(from: file.modifiedAt, locale: locale)
                let caption = [subtitle, modified.isEmpty ? nil : modified]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                if !caption.isEmpty {
                    Text(caption)
                        .font(.workSans(.caption))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Penpot's "published as a shared library" badge — the `library` book glyph on the brand mint
/// (design-system `$mint-150`, `#7efff5`), matching the web dashboard. Shown on the thumbnail of
/// files whose `isShared` is true.
private struct SharedLibraryBadge: View {
    var size: CGFloat = 28

    var body: some View {
        AppIcon.library.image(size: size * 0.5)
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(Color.penpotMint, in: RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityLabel("Shared Library")
    }
}

private extension Color {
    /// Penpot brand mint (design-system `$mint-150`).
    static let penpotMint = Color(red: 126 / 255, green: 255 / 255, blue: 245 / 255)
}
