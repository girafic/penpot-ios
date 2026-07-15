import SwiftUI

/// Work Sans — Penpot's UI typeface, bundled from `Sources/Resources/Fonts` and registered
/// via `UIAppFonts` (see `project.yml`). Use `Font.workSans(...)` everywhere instead of the
/// system font so the app matches Penpot's web UI.
///
/// Custom fonts don't synthesize weights the way `.system` does, so we select the real face
/// per weight rather than relying on `.bold()`/`.weight()`. Dynamic Type is preserved via
/// `Font.custom(_:size:relativeTo:)`.
enum WorkSans {
    /// PostScript name of the face for a given weight (verified against the bundled TTFs).
    static func faceName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "WorkSans-Bold"
        case .semibold:             "WorkSans-SemiBold"
        case .medium:               "WorkSans-Medium"
        default:                    "WorkSans-Regular"
        }
    }

    /// Default point size for each semantic text style (matches Apple's Large content size).
    static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title:      28
        case .title2:     22
        case .title3:     20
        case .headline:   17
        case .body:       17
        case .callout:    16
        case .subheadline: 15
        case .footnote:   13
        case .caption:    12
        case .caption2:   11
        @unknown default: 17
        }
    }

    /// The weight a semantic style renders at by default (`.headline` is semibold).
    static func defaultWeight(for style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }

    /// UIKit face for chrome that SwiftUI's environment font can't reach (nav-bar titles).
    static func uiFont(for weight: Font.Weight, size: CGFloat) -> UIFont {
        UIFont(name: faceName(for: weight), size: size)
            ?? .systemFont(ofSize: size, weight: weight.uiWeight)
    }
}

extension Font {
    /// Work Sans mapped to a semantic text style — scales with Dynamic Type.
    static func workSans(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let resolved = weight ?? WorkSans.defaultWeight(for: style)
        return .custom(WorkSans.faceName(for: resolved),
                       size: WorkSans.size(for: style),
                       relativeTo: style)
    }

    /// Work Sans at a fixed point size — for call sites that need an exact size
    /// (avatar initials, comment-pin badges) rather than a semantic style.
    static func workSans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(WorkSans.faceName(for: weight), fixedSize: size)
    }
}

private extension Font.Weight {
    /// Bridge SwiftUI's `Font.Weight` to UIKit's `UIFont.Weight` for the system fallback.
    var uiWeight: UIFont.Weight {
        switch self {
        case .black:    .black
        case .heavy:    .heavy
        case .bold:     .bold
        case .semibold: .semibold
        case .medium:   .medium
        case .light:    .light
        case .thin:     .thin
        case .ultraLight: .ultraLight
        default:        .regular
        }
    }
}
