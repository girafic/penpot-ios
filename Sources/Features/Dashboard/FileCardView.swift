import SwiftUI

/// A file card showing a preview thumbnail (the first available board) and the file name.
struct FileCardView: View {
    let file: FileListItem
    let baseURL: URL?

    @Environment(AppState.self) private var appState
    @State private var thumbnailMediaID: String? = nil
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                if let baseURL {
                    RemoteImage(mediaID: thumbnailMediaID, baseURL: baseURL, contentMode: .fit)
                        .padding(6)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))

            Text(file.name)
                .font(.workSans(.subheadline))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard !didLoad, let client = appState.client else { return }
        didLoad = true
        let map = try? await client.objectThumbnails(fileID: file.id)
        thumbnailMediaID = map?.values.first
    }
}
