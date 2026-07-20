import SwiftUI

/// A file's preview thumbnail (the first available board) in a rounded, bordered box.
/// Shared by the card (grid) and row (list) presentations.
private struct FileThumbnailView: View {
    let file: FileListItem
    let baseURL: URL?

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
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard !didLoad, let client = appState.client else { return }
        didLoad = true
        let map = try? await client.objectThumbnails(fileID: file.id)
        thumbnailMediaID = map?.values.first
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

                let modified = PenpotDate.namedRelative(from: file.modifiedAt, locale: locale)
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

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnailView(file: file, baseURL: baseURL)
                .frame(width: 72, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.workSans(.subheadline))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                let modified = PenpotDate.namedRelative(from: file.modifiedAt, locale: locale)
                if !modified.isEmpty {
                    Text(modified)
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
