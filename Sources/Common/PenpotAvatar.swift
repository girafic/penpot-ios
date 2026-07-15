import SwiftUI

/// A circular Penpot avatar (profile or team — both are served as media ids).
/// When there's no image, it falls back to an initial letter on a dark circle
/// (matching Penpot's web look), or to an SF Symbol glyph when no `initials`
/// are supplied (e.g. the personal "Your Penpot" team or a profile).
struct PenpotAvatar: View {
    let photoID: String?
    let baseURL: URL?
    var fallbackSymbol: String = "person.fill"
    /// Name of an asset-catalog image shown when there's no photo. Takes
    /// precedence over `initials` and `fallbackSymbol` (e.g. the Penpot mark
    /// for the personal "Your Penpot" team).
    var fallbackAsset: String? = nil
    /// Source text for the initial shown when there's no image. Used when no
    /// `fallbackAsset` is set; takes precedence over `fallbackSymbol`.
    var initials: String? = nil
    var size: CGFloat = 44

    var body: some View {
        if let photoID, let baseURL {
            RemoteImage(mediaID: photoID, baseURL: baseURL, contentMode: .fill) { fallback }
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            fallback.frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if let fallbackAsset {
            Image(fallbackAsset)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.primary)
                .padding(size * 0.08)
        } else if let letters {
            // Matches Penpot's web default avatar: near-black circle, white initials.
            // The hairline ring keeps the circle visible on dark backgrounds.
            Circle()
                .fill(Color(white: 0.1))
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                .overlay(
                    Text(letters)
                        .font(.workSans(size: size * (letters.count > 1 ? 0.38 : 0.45), weight: .semibold))
                        .foregroundStyle(.white))
        } else {
            Circle().fill(.quaternary).overlay(
                Image(systemName: fallbackSymbol)
                    .font(.workSans(size: size * 0.45))
                    .foregroundStyle(.secondary))
        }
    }

    /// Up to two uppercase initials from `initials`: first letter of the first and last
    /// name words (e.g. "Stas Haas" → "SH"), or just the first character for a single word
    /// or an email address (e.g. "stas@girafic.de" → "S"). Matches Penpot's web avatar.
    private var letters: String? {
        let words = (initials ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { $0.first(where: { $0.isLetter || $0.isNumber }) }
        guard let first = words.first else { return nil }
        if words.count > 1, let last = words.last {
            return (String(first) + String(last)).uppercased()
        }
        return String(first).uppercased()
    }
}
