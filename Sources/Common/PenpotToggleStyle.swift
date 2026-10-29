import SwiftUI

extension ToggleStyle where Self == PenpotToggleStyle {
    /// Penpot's switch — use on every `Toggle` outside a `Menu`.
    static var penpot: PenpotToggleStyle { PenpotToggleStyle() }
}

/// Penpot's switch (`ds/controls/switch.scss`) in place of the iOS one, which iOS 26 made
/// about twice Penpot's size: a 30×18 pill track with a 14pt thumb and 2pt padding,
/// scaled by 1.2 here for touch. As in Penpot, the whole row — label and track — toggles.
struct PenpotToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        // An inner view: a style's `makeBody` can't read `@Environment(\.isEnabled)`.
        PenpotSwitch(configuration: configuration)
    }
}

private struct PenpotSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    private static let thumbSide: CGFloat = 17
    private static let padding: CGFloat = 2.5
    private static let trackSize = CGSize(width: 36, height: thumbSide + 2 * padding)

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 8) {
                configuration.label
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                track
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver keeps reading it as a native switch.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    private var track: some View {
        Capsule()
            .fill(trackColor.shadow(.inner(color: .black.opacity(isEnabled ? 0.3 : 0), radius: 1, y: 1)))
            .overlay {
                // Only a disabled switch that is off draws a ring.
                if !isEnabled && !configuration.isOn {
                    Capsule().strokeBorder(Color.penpotBackgroundDisabled, lineWidth: 1)
                }
            }
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(thumbColor)
                    .shadow(color: .black.opacity(isEnabled ? 0.3 : 0), radius: 1, y: 1)
                    .frame(width: Self.thumbSide, height: Self.thumbSide)
                    .padding(Self.padding)
            }
            .frame(width: Self.trackSize.width, height: Self.trackSize.height)
    }

    private var trackColor: Color {
        switch (isEnabled, configuration.isOn) {
        case (true, true): .penpotAccentTertiary
        case (true, false): .penpotForegroundSecondary
        case (false, true): .penpotBackgroundDisabled
        case (false, false): .penpotPage
        }
    }

    private var thumbColor: Color {
        switch (isEnabled, configuration.isOn) {
        case (true, _): .penpotAccentOff
        case (false, true): .penpotPage
        case (false, false): .penpotBackgroundDisabled
        }
    }
}
