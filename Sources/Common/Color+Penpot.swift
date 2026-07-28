import SwiftUI

extension UIColor {
    /// Penpot's brand accent, matched to the web client per theme: the brand purple
    /// (`#7B61FF`, as on the light dashboard) on light, the brand green (`#31EFB8`,
    /// Penpot's accent on dark UI) on dark. Both pair with white foreground on fills.
    ///
    /// Defined here (not only as the `AccentColor` asset) because the app drives its
    /// tint explicitly — the asset's global accent doesn't flow into SwiftUI's tint,
    /// and the UIKit navigation bar needs a `tintColor` for its bar-button icons.
    static let penpotAccent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x31 / 255, green: 0xEF / 255, blue: 0xB8 / 255, alpha: 1)
            : UIColor(red: 0x7B / 255, green: 0x61 / 255, blue: 0xFF / 255, alpha: 1)
    }

    /// Penpot's neutral icon/foreground gray — the *resting* color for glyphs (toolbar
    /// ＋/⋮, list-row icons). The accent (purple/green) is reserved for hover/press/active
    /// states, so default icons use this instead of the tint.
    static let penpotIconGray = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xB1 / 255, green: 0xB2 / 255, blue: 0xB5 / 255, alpha: 1)
            : UIColor(red: 0x52 / 255, green: 0x5A / 255, blue: 0x6B / 255, alpha: 1)
    }
}

extension Color {
    /// Penpot's brand accent (purple on light, green on dark) — see `UIColor.penpotAccent`.
    /// Reserve for active/selected/pressed states, not resting icons.
    static let penpotAccent = Color(uiColor: .penpotAccent)

    /// Penpot's resting icon/foreground gray — see `UIColor.penpotIconGray`.
    static let penpotIconGray = Color(uiColor: .penpotIconGray)

    /// Foreground for content sitting *on* an accent-filled surface (badges, the
    /// comment pin, the photo camera badge). White reads on the deep light-mode
    /// green; the bright dark-mode green needs dark ink — so this flips per appearance.
    static let penpotOnAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x17 / 255, green: 0x1B / 255, blue: 0x19 / 255, alpha: 1)
            : .white
    })
}
