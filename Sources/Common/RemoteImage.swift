import SwiftUI
import UIKit

/// Loads an image from a Penpot media id via ``RemoteImageLoader`` and displays it,
/// showing a placeholder while loading or when unavailable.
struct RemoteImage<Placeholder: View>: View {
    let mediaID: String?
    let baseURL: URL
    var contentMode: ContentMode = .fit
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage? = nil
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: mediaID) {
            await load()
        }
    }

    private func load() async {
        image = nil
        didFail = false
        guard let mediaID else { didFail = true; return }
        let loaded = await RemoteImageLoader.shared.image(mediaID: mediaID, baseURL: baseURL)
        if loaded == nil { didFail = true }
        image = loaded
    }
}

extension RemoteImage where Placeholder == AnyView {
    init(mediaID: String?, baseURL: URL, contentMode: ContentMode = .fit) {
        self.init(mediaID: mediaID, baseURL: baseURL, contentMode: contentMode) {
            AnyView(
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            )
        }
    }
}
