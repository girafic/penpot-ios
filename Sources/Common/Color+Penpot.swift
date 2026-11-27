import SwiftUI

extension UIColor {
    /// Penpot's brand accent, taken verbatim from the web client's
    /// `--color-accent-primary` design token: deep purple `#6911D4` on light, pale cyan
    /// `#7EFFF5` on dark.
    ///
    /// The earlier light value (`#7B61FF`) only reached 4.21:1 against white — below
    /// WCAG AA for normal-size text, which made every filled button's label
    /// borderline. Penpot's own purple reaches 7.97:1.
    ///
    /// Defined here (not only as the `AccentColor` asset) because the app drives its
    /// tint explicitly — the asset's global accent doesn't flow into SwiftUI's tint,
    /// and the UIKit navigation bar needs a `tintColor` for its bar-button icons.
    static let penpotAccent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x7E / 255, green: 0xFF / 255, blue: 0xF5 / 255, alpha: 1)
            : UIColor(red: 0x69 / 255, green: 0x11 / 255, blue: 0xD4 / 255, alpha: 1)
    }

    /// Penpot's neutral icon/foreground gray — the *resting* color for glyphs (toolbar
    /// ＋/⋮, list-row icons). The accent (purple/cyan) is reserved for hover/press/active
    /// states, so default icons use this instead of the tint.
    static let penpotIconGray = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xB1 / 255, green: 0xB2 / 255, blue: 0xB5 / 255, alpha: 1)
            : UIColor(red: 0x52 / 255, green: 0x5A / 255, blue: 0x6B / 255, alpha: 1)
    }

    /// `--color-background-primary`, for UIKit: see `Color.penpotPage`.
    static let penpotPage = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1A / 255, alpha: 1)
            : .white
    }

    /// `--color-background-tertiary`, for UIKit: see `Color.penpotSurface`.
    static let penpotSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x21 / 255, green: 0x24 / 255, blue: 0x26 / 255, alpha: 1)
            : UIColor(red: 0xF3 / 255, green: 0xF4 / 255, blue: 0xF6 / 255, alpha: 1)
    }

    /// `--color-foreground-secondary`, for UIKit: see `Color.penpotForegroundSecondary`.
    static let penpotForegroundSecondary = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x8F / 255, green: 0x9D / 255, blue: 0xA3 / 255, alpha: 1)
            : UIColor(red: 0x49 / 255, green: 0x5E / 255, blue: 0x74 / 255, alpha: 1)
    }
}

extension Color {
    /// Penpot's brand accent (purple on light, cyan on dark) — see `UIColor.penpotAccent`.
    /// Reserve for active/selected/pressed states, not resting icons.
    static let penpotAccent = Color(uiColor: .penpotAccent)

    /// Penpot's resting icon/foreground gray — see `UIColor.penpotIconGray`.
    static let penpotIconGray = Color(uiColor: .penpotIconGray)

    /// Foreground for content sitting *on* an accent-filled surface (badges, the
    /// comment pin, the photo camera badge). White reads on the deep light-mode
    /// purple; the bright dark-mode cyan needs dark ink — so this flips per appearance.
    static let penpotOnAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x17 / 255, green: 0x1B / 255, blue: 0x19 / 255, alpha: 1)
            : .white
    })

    // MARK: Surfaces & status (Penpot design tokens)
    //
    // Penpot deliberately has no border token family — borders reuse background
    // tokens, so `penpotSurfacePressed` doubles as the hairline color.

    /// `--color-background-tertiary`: resting fill of a secondary button and of an
    /// input box.
    static let penpotSurface = Color(uiColor: .penpotSurface)

    /// `--color-background-quaternary`: pressed/active surface, and hairlines.
    static let penpotSurfacePressed = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2E / 255, green: 0x34 / 255, blue: 0x34 / 255, alpha: 1)
            : UIColor(red: 0xEE / 255, green: 0xF0 / 255, blue: 0xF2 / 255, alpha: 1)
    })

    /// `--color-background-primary`: the page itself — white on light, near-black on
    /// dark. Penpot inverts iOS's convention: a flat page carrying tonal cards, rather
    /// than a gray page carrying white cards.
    static let penpotPage = Color(uiColor: .penpotPage)

    /// `--color-accent-error` (`#C80857`, both themes): fill of a destructive button.
    /// Carries **white** ink, not Penpot's black — the web's own combination is 3.63:1
    /// and fails WCAG AA; white reaches 5.78:1.
    static let penpotDanger = Color(red: 0xC8 / 255, green: 0x08 / 255, blue: 0x57 / 255)

    /// `--color-foreground-error` (`#FF3277`, both themes): error ring + message text.
    static let penpotDangerText = Color(red: 0xFF / 255, green: 0x32 / 255, blue: 0x77 / 255)

    // MARK: Switch (Penpot `ds/controls/switch.scss`)

    /// `--color-accent-tertiary`: the track of a switch that is on — purple `#8C33EB` on
    /// light, mint `#00D1B8` on dark.
    static let penpotAccentTertiary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x00 / 255, green: 0xD1 / 255, blue: 0xB8 / 255, alpha: 1)
            : UIColor(red: 0x8C / 255, green: 0x33 / 255, blue: 0xEB / 255, alpha: 1)
    })

    /// `--color-foreground-secondary`: the track of a switch that is off.
    static let penpotForegroundSecondary = Color(uiColor: .penpotForegroundSecondary)

    /// `--color-accent-off` (`#F3F4F6`, both themes): a switch's thumb.
    static let penpotAccentOff = Color(red: 0xF3 / 255, green: 0xF4 / 255, blue: 0xF6 / 255)

    /// `--color-background-disabled`: a disabled switch's track (on) or thumb and ring (off).
    static let penpotBackgroundDisabled = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2E / 255, green: 0x34 / 255, blue: 0x34 / 255, alpha: 1)
            : UIColor(red: 0xE8 / 255, green: 0xEA / 255, blue: 0xEE / 255, alpha: 1)
    })
}

extension UIColor {
    /// A color Penpot stores as hex (`#RRGGBB` or `#RGB`), or `nil` for anything else.
    convenience init?(penpotHex hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// Whether white text contrasts more with it than black does (WCAG relative luminance).
    var isDark: Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolvedColor(with: .current).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        // Contrast with white (1.05 / (L + 0.05)) beats contrast with black ((L + 0.05) / 0.05).
        return luminance < 0.179
    }
}
