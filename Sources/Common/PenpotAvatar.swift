import SwiftUI

/// A circular Penpot avatar (profile or team — both are served as media ids),
/// falling back to an SF Symbol glyph when there's no image or no server.
struct PenpotAvatar: View {
    let photoID: String?
    let baseURL: URL?
    var fallbackSymbol: String = "person.fill"
    var size: CGFloat = 44

    var body: some View {
        let fallback = Circle().fill(.quaternary).overlay(
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.45))
                .foregroundStyle(.secondary))

        if let photoID, let baseURL {
            RemoteImage(mediaID: photoID, baseURL: baseURL, contentMode: .fill) { fallback }
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            fallback.frame(width: size, height: size)
        }
    }
}
