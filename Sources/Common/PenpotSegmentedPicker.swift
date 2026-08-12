import SwiftUI

/// Penpot's segmented control (the web's Design / Prototype / Inspect tabs): a tonal
/// track holding uppercase labels, with the selected one lifted onto a light card and
/// tinted with the brand accent.
///
/// Built in SwiftUI rather than restyling `.pickerStyle(.segmented)`, whose selected-
/// segment color is only reachable through a global `UISegmentedControl.appearance()`
/// mutation — that leaks into every system-presented UIKit surface and can't be scoped
/// to one screen.
struct PenpotSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    /// Segments in display order. `Text` (not `LocalizedStringKey`) so verbatim labels
    /// like "PNG" and localized ones can share the component.
    let segments: [(value: Value, label: Text)]

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments, id: \.value) { segment in
                let isSelected = segment.value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = segment.value }
                } label: {
                    segment.label
                        .font(.workSans(.caption, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(0.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected ? Color.penpotAccent : Color.penpotIconGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.penpotPage)
                                    .matchedGeometryEffect(id: "segment", in: indicator)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        // Track and segment share the 8pt radius, exactly as the web's tab switcher does.
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.penpotSurface))
        // Reads as one control to VoiceOver, like a native segmented picker.
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    struct Demo: View {
        @State private var theme = 0
        var body: some View {
            PenpotSegmentedPicker(selection: $theme,
                                  segments: [(0, Text(verbatim: "Design")),
                                             (1, Text(verbatim: "Prototype")),
                                             (2, Text(verbatim: "Inspect"))])
            .padding()
        }
    }
    return Demo()
}
