import SwiftUI

/// Which visual weight a button carries, mirroring Penpot's four web variants.
enum PenpotButtonRole {
    /// The affirmative action of a screen — accent fill, uppercase label.
    case primary
    /// A supporting action — tonal fill.
    case secondary
    /// A link-weight action — no fill until pressed.
    case ghost
    /// A bare text link, carrying no box at all — Penpot's `forgot-pass-link` /
    /// `register-link` / `demo-account-link`, which all share one rule in
    /// `ui/auth/common.scss`: 14px Work Sans at weight 400, `--color-accent-primary`,
    /// `background: transparent`, `border: none`, no padding, sentence case, and an
    /// underline only on `:hover`.
    case link
    /// An irreversible action — error fill, uppercase label.
    case destructive
}

enum PenpotButtonSize {
    case regular
    case compact

    /// Visual box height. Both keep a ≥44pt tap target via `contentShape` below.
    var minHeight: CGFloat { self == .regular ? 48 : 40 }
    var horizontalPadding: CGFloat { self == .regular ? 20 : 14 }
}

/// Penpot's button language as a `ButtonStyle`, so it applies to any label — `Text`,
/// `Label`, `AppIcon.label(…)`, a `ProgressView` — while the call site keeps using
/// `Button("…") { }` with a `LocalizedStringKey` (no localization surface added).
///
/// Metrics come from Penpot's design system: 8pt corner radius (`$br-8`), 4pt icon gap
/// (`--sp-xs`), and a pressed state that ports the web's
/// `:active { box-shadow: inset 0 0 10px 2px rgba(0,0,0,.2) }`.
///
/// Filled roles uppercase their label the way Penpot does — but only at the display
/// layer (`.textCase`), never in the string catalog, since casing rules differ per
/// language. Ghost/secondary labels stay as written: they are often whole sentences,
/// which read as shouting in caps at phone width.
struct PenpotButtonStyle: ButtonStyle {
    var role: PenpotButtonRole = .primary
    var size: PenpotButtonSize = .regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        // A ButtonStyle can't read @Environment(\.isEnabled) directly — without this
        // inner view every .disabled() call site would silently render as enabled.
        StyleBody(configuration: configuration, role: role, size: size, fullWidth: fullWidth)
    }

    private struct StyleBody: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let role: PenpotButtonRole
        let size: PenpotButtonSize
        let fullWidth: Bool

        private var isUppercase: Bool { role == .primary || role == .destructive }

        private var font: Font {
            switch role {
            case .primary, .destructive: .workSans(.subheadline, weight: .semibold)
            case .secondary: .workSans(.footnote, weight: .medium)
            case .ghost: .workSans(.subheadline)
            // Regular weight, one step under the primary label — the same subordination
            // Penpot's 14px links have to its 16px button labels.
            case .link: .workSans(.footnote)
            }
        }

        private var foreground: Color {
            guard isEnabled else { return .secondary }
            switch role {
            case .primary: return .penpotOnAccent
            case .destructive: return .white
            case .secondary, .ghost: return configuration.isPressed ? .penpotAccent : .penpotIconGray
            case .link: return .penpotAccent
            }
        }

        private var fill: Color {
            switch role {
            case .primary:
                return isEnabled ? .penpotAccent : Color(.tertiarySystemFill)
            case .destructive:
                return isEnabled ? .penpotDanger : Color(.tertiarySystemFill)
            case .secondary:
                guard isEnabled else { return .clear }
                return configuration.isPressed ? .penpotSurfacePressed : .penpotSurface
            case .ghost:
                return configuration.isPressed && isEnabled ? .penpotSurface : .clear
            case .link:
                return .clear
            }
        }

        /// A link carries no box, so it drops the button padding entirely (Penpot's rule
        /// declares none) — the 44pt tap target below still holds it touchable.
        private var horizontalPadding: CGFloat { role == .link ? 2 : size.horizontalPadding }
        private var verticalPadding: CGFloat { role == .link ? 4 : 12 }
        private var boxHeight: CGFloat { role == .link ? 0 : size.minHeight }

        /// Touch has no hover, so the web's `:hover { text-decoration: underline }` lands
        /// on the pressed state — the only feedback a fill-less control can give.
        private var isUnderlined: Bool { role == .link && configuration.isPressed && isEnabled }

        /// Filled roles darken on press, like the web's inset shadow.
        private var pressOverlay: Color {
            let isFilled = role == .primary || role == .destructive
            return isFilled && configuration.isPressed && isEnabled ? .black.opacity(0.2) : .clear
        }

        var body: some View {
            configuration.label
                .font(font)
                .textCase(isUppercase ? .uppercase : nil)
                // Never a fixed height: uppercase German at accessibility sizes needs
                // room to grow.
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
                .tint(foreground)
                .underline(isUnderlined)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: boxHeight)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fill)
                        .overlay(RoundedRectangle(cornerRadius: 8).fill(pressOverlay))
                }
                // Keeps the tap target at iOS's 44pt minimum even for .compact.
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 44)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PenpotButtonStyle {
    /// Penpot's button language. `.penpot(.primary)` for the affirmative action,
    /// `.secondary` for supporting ones, `.ghost` for link-weight, `.link` for a bare
    /// text link with no box at all, `.destructive` for irreversible ones.
    static func penpot(_ role: PenpotButtonRole = .primary,
                       size: PenpotButtonSize = .regular,
                       fullWidth: Bool = false) -> PenpotButtonStyle {
        PenpotButtonStyle(role: role, size: size, fullWidth: fullWidth)
    }
}

#Preview("Roles") {
    VStack(spacing: 16) {
        ForEach([false, true], id: \.self) { disabled in
            VStack(spacing: 8) {
                Button("Log In") {}.buttonStyle(.penpot(.primary, fullWidth: true))
                Button("Log in as demo user") {}
                    .buttonStyle(.penpot(.secondary, size: .compact, fullWidth: true))
                Button("Forgot password?") {}.buttonStyle(.penpot(.ghost, size: .compact))
                Button("Log in as demo user") {}.buttonStyle(.penpot(.link, fullWidth: true))
                Button("Create account") {}.buttonStyle(.penpot(.link))
                Button("Delete Account") {}.buttonStyle(.penpot(.destructive, fullWidth: true))
            }
            .disabled(disabled)
        }
    }
    .padding()
}
