import SwiftUI

/// Penpot's boxed text input: an uppercase label above a tonal box with an 8pt radius,
/// an accent ring while focused, and an error ring plus message when something is wrong.
///
/// Sits directly on the page, never inside a ``PenpotCard`` — a tonal box on a tonal
/// card would read as a box in a box, which is further from Penpot's look, not closer.
private struct PenpotFieldModifier: ViewModifier {
    let label: LocalizedStringKey?
    let error: Text?

    @FocusState private var isFocused: Bool

    /// No visible border at rest — the fill alone carries the box, exactly as on the web.
    /// Penpot does declare `border: 1px solid var(--input-border-color)`, but that token
    /// and `--input-background-color` both resolve to `--color-background-tertiary`, so
    /// the border is the fill color and invisible. The accent border is the focus signal.
    private var border: Color {
        if error != nil { return .penpotDangerText }
        return isFocused ? .penpotAccent : .clear
    }

    /// 1pt in every state: `--input-border-color-focus` and the error border are both a
    /// single pixel on the web (`$b-1` / `0.0625rem`), never a thicker ring.
    private let borderWidth: CGFloat = 1

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                // Penpot's `%input-label`: 12px uppercase Work Sans at weight 500, inked
                // in `--color-foreground-primary` — pure black on light, pure white on
                // dark, which is precisely what SwiftUI's `.primary` resolves to. It is
                // deliberately *not* a muted gray; the gray is the placeholder's job.
                Text(label)
                    .font(.workSans(.caption, weight: .medium))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(.primary)
            }
            box(content)
            if let error {
                error
                    .font(.workSans(.footnote))
                    .foregroundStyle(Color.penpotDangerText)
            }
        }
    }

    /// When a label is shown the call site drops the placeholder, so VoiceOver takes the
    /// label instead — but only then. Forcing an accessibility label on an unlabeled
    /// field would strip the placeholder-derived one from e.g. the comment composer.
    @ViewBuilder
    private func box(_ content: Content) -> some View {
        if let label {
            styled(content).accessibilityLabel(Text(label))
        } else {
            styled(content)
        }
    }

    private func styled(_ content: Content) -> some View {
        content
            .focused($isFocused)
            .font(.workSans(.body))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background {
                // The fill stays put while focused: `--input-background-color-focus` is
                // the same `--color-background-tertiary` as at rest, so on the web only
                // the border reacts. Swapping the fill too would double the signal.
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.penpotSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(border, lineWidth: borderWidth)
                    }
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    /// Penpot's boxed input treatment. Focus is handled internally, so no call site needs
    /// its own `FocusState`.
    ///
    /// - Parameters:
    ///   - label: shown above the box in Penpot's uppercase field-label style. Prefer it
    ///     over a placeholder: a placeholder disappears as soon as the field has content,
    ///     a label doesn't.
    ///   - error: switches the ring to the error color and shows the message underneath.
    ///     `Text` (not `String`) so both server messages and localized literals work
    ///     without `String(localized:)`.
    func penpotField(label: LocalizedStringKey? = nil, error: Text? = nil) -> some View {
        modifier(PenpotFieldModifier(label: label, error: error))
    }

    /// Penpot's page color: flat white, near-black on dark — the inverse of iOS's gray
    /// page with white cards.
    ///
    /// This is what makes Penpot's tonal surfaces work: ``PenpotCard``, the input box,
    /// the segmented track and the secondary button all use
    /// `--color-background-tertiary`, which only separates itself against a flat page.
    func penpotPageBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.penpotPage.ignoresSafeArea())
    }
}

/// Penpot's card: a tonal panel holding rows separated by dividers — the shape SwiftUI's
/// `List` can't produce, because a `Section` isn't a view you can put a background
/// behind (each row is its own cell, and the system owns the grouped card's shape).
struct PenpotCard<Content: View>: View {
    /// Penpot's one radius: `$br-8` / `--sp-s` (8px), what its own plan cards,
    /// template cards and panels use.
    var cornerRadius: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.penpotSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// One row inside a ``PenpotCard``: content, optional trailing detail, and the
/// navigation chevron a `List` would otherwise draw for us.
struct PenpotCardRow<Label: View, Trailing: View>: View {
    var showsChevron = true
    @ViewBuilder let label: Label
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            label
            Spacer(minLength: 8)
            trailing
                .foregroundStyle(.secondary)
            if showsChevron {
                AppIcon.chevronRight.image(size: 13)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

extension PenpotCardRow where Trailing == EmptyView {
    init(showsChevron: Bool = true, @ViewBuilder label: () -> Label) {
        self.init(showsChevron: showsChevron, label: label, trailing: { EmptyView() })
    }
}

/// A dropdown for a ``PenpotCardRow``'s trailing slot whose value always stays on one line.
///
/// `.pickerStyle(.menu)` sizes its label to fit the *longest* option and then wraps it when
/// the row is too narrow — "Only team members" broke across two lines in the share sheet,
/// and the longer German notification options would have done the same. SwiftUI offers no
/// way to pin the line count of a `Picker`'s own label, so this draws the label itself
/// (a `Menu` wrapping the `Picker`) and shrinks it to 85 % before truncating.
struct PenpotMenuPicker<Value: Hashable>: View {
    /// Also the VoiceOver label: with the picker drawn by hand there is no visible title.
    let title: LocalizedStringKey
    @Binding var selection: Value
    /// Options in menu order. `Text` (not `LocalizedStringKey`) so localized literals and
    /// runtime names like a language's `nativeName` can share the component.
    let options: [(value: Value, label: Text)]

    private var selectedLabel: Text {
        options.first { $0.value == selection }?.label ?? Text(verbatim: "")
    }

    var body: some View {
        Menu {
            PenpotMenuChoices(selection: $selection, options: options)
        } label: {
            HStack(spacing: 4) {
                selectedLabel
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.trailing)
                // Penpot's select arrow, the dropdown indicator of its web selects.
                AppIcon.chevronDown.image(size: 12)
            }
            // Applied inside the label so it beats the tint a `Menu` would otherwise put
            // on its own label, keeping the row's trailing gray.
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(title))
    }
}

/// Menu content for choosing one value. Drawn as buttons rather than a `Picker`, so the
/// chosen row carries Penpot's tick (trailing, like its web selects) instead of the system
/// checkmark.
struct PenpotMenuChoices<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: Text)]

    var body: some View {
        ForEach(options, id: \.value) { option in
            Button { selection = option.value } label: {
                PenpotMenuCheckLabel(label: option.label, isOn: option.value == selection)
            }
        }
    }
}

/// A menu row's label with Penpot's tick when `isOn` — the replacement for both a `Picker`'s
/// and a `Toggle`'s system checkmark inside a `Menu`.
struct PenpotMenuCheckLabel: View {
    let label: Text
    let isOn: Bool

    var body: some View {
        if isOn {
            Label { label } icon: { AppIcon.tick.image }
                .accessibilityAddTraits(.isSelected)
        } else {
            label
        }
    }
}

/// The hairline between two rows of a ``PenpotCard``, inset like Penpot's own dividers.
struct PenpotCardDivider: View {
    var body: some View {
        Divider()
            .overlay(Color(.separator))
            .padding(.leading, 14)
    }
}
