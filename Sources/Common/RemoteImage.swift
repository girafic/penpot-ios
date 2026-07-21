import SwiftUI
import UIKit

/// Loads an image over the network via ``RemoteImageLoader`` and displays it, showing a
/// placeholder while loading or when unavailable.
///
/// Addressed by URL. Most Penpot imagery is served by media id under `/assets/by-id/<id>` —
/// use the `mediaID:baseURL:` convenience for those. A few assets are plain static files
/// (built-in template previews), which is why the underlying storage is a URL.
struct RemoteImage<Placeholder: View>: View {
    /// The image to load; `nil` renders the placeholder without a request.
    let url: URL?
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
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        image = nil
        didFail = false
        guard let url else { didFail = true; return }
        let loaded = await RemoteImageLoader.shared.image(at: url)
        if loaded == nil { didFail = true }
        image = loaded
    }
}

extension RemoteImage {
    /// Penpot media id served at `/assets/by-id/<id>`.
    init(mediaID: String?, baseURL: URL, contentMode: ContentMode = .fit,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.init(url: mediaID.map { RemoteImageLoader.shared.assetURL(mediaID: $0, baseURL: baseURL) },
                  contentMode: contentMode,
                  placeholder: placeholder)
    }
}

/// Default placeholder: a neutral fill with an image glyph.
extension RemoteImage where Placeholder == AnyView {
    private static var defaultPlaceholder: AnyView {
        AnyView(
            ZStack {
                Rectangle().fill(.quaternary)
                AppIcon.image.image
                    .foregroundStyle(.secondary)
            }
        )
    }

    init(mediaID: String?, baseURL: URL, contentMode: ContentMode = .fit) {
        self.init(mediaID: mediaID, baseURL: baseURL, contentMode: contentMode) {
            Self.defaultPlaceholder
        }
    }

    init(url: URL?, contentMode: ContentMode = .fit) {
        self.init(url: url, contentMode: contentMode) { Self.defaultPlaceholder }
    }
}
