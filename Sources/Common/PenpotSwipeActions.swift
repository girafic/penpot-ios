import SwiftUI

/// One action revealed by swiping a row left.
struct PenpotSwipeAction: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let icon: AppIcon
    /// Destructive actions are inked on Penpot's error fill; everything else on the accent.
    var isDestructive = false
    let handler: () -> Void

    init(_ title: LocalizedStringKey,
         icon: AppIcon,
         isDestructive: Bool = false,
         handler: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.handler = handler
    }
}

/// Tracks which row currently shows its actions, so opening one closes the other — the
/// behaviour `List` gives for free. A single shared instance is correct: only one row in
/// the whole app should ever stand open, so no call site has to inject anything.
@Observable
final class PenpotSwipeCoordinator {
    var openRow: AnyHashable?
}

private struct PenpotSwipeCoordinatorKey: EnvironmentKey {
    static let defaultValue = PenpotSwipeCoordinator()
}

extension EnvironmentValues {
    var penpotSwipeCoordinator: PenpotSwipeCoordinator {
        get { self[PenpotSwipeCoordinatorKey.self] }
        set { self[PenpotSwipeCoordinatorKey.self] = newValue }
    }
}

/// Swipe-to-delete for rows that do not live in a `List`.
///
/// `.swipeActions` is a `List`-only modifier — outside one it fails silently, which is how
/// swiping disappeared when the screens moved from `List` to ``PenpotCard``. Rather than
/// hand-roll a `DragGesture` (which would have to fight the enclosing vertical `ScrollView`
/// for every touch), the row becomes a *nested horizontal `ScrollView`*: UIKit already
/// arbitrates perpendicular nested scrolling correctly, so vertical scrolling and
/// pull-to-refresh keep working untouched, and the reveal gets native rubber-banding.
private struct PenpotSwipeRowModifier: ViewModifier {
    let rowID: AnyHashable
    let actions: [PenpotSwipeAction]

    @Environment(\.penpotSwipeCoordinator) private var coordinator
    @State private var slot: Slot? = .row

    /// The two scroll targets: the row itself, and the strip of buttons behind it.
    private enum Slot: Hashable { case row, actions }

    /// Every button is the same width, sized so that two of them still leave most of the
    /// row visible: German's longest label here ("Einladung erneut senden") needs the
    /// wrap, and letting each button follow its own title would have cost 270pt for a
    /// two-action row.
    private static let labelWidth: CGFloat = 88

    /// Measured once the buttons have laid out. Until then the estimate keeps the snap
    /// behaviour sane; it only decides where a release settles, so being briefly off is
    /// harmless.
    @State private var measuredRevealWidth: CGFloat = 0

    private var revealWidth: CGFloat {
        // Estimate = label width plus the 8pt padding on each side.
        measuredRevealWidth > 0 ? measuredRevealWidth : CGFloat(actions.count) * (Self.labelWidth + 16)
    }

    func body(content: Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                content
                    // Exactly the viewport width, so the closed state shows only the row.
                    .containerRelativeFrame(.horizontal)
                    .id(Slot.row)
                buttons
                    .id(Slot.actions)
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(SwipeSnapBehavior(revealWidth: revealWidth))
        .scrollPosition(id: $slot)
        .onChange(of: slot) { _, new in
            if new == .actions {
                coordinator.openRow = rowID
            } else if coordinator.openRow == rowID {
                coordinator.openRow = nil
            }
        }
        .onChange(of: coordinator.openRow) { _, new in
            if new != rowID, slot == .actions { close() }
        }
        // Swiping is invisible to VoiceOver, so the same actions are offered through the
        // rotor. (The call sites keep their context menu as the third route.)
        .accessibilityActions {
            ForEach(actions) { action in
                Button(action.title) { action.handler() }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    close()
                    action.handler()
                } label: {
                    // Rows differ a lot in height — a font variant is one line tall, a
                    // file row carries a thumbnail. Rather than pick one stack and let it
                    // overflow the short rows (which pinned the icon to the top edge),
                    // offer three and let the row's own height decide.
                    ViewThatFits(in: .vertical) {
                        stack(action, icon: 18, size: 11, spacing: 4)
                        stack(action, icon: 15, size: 10, spacing: 2)
                        // Last resort on a genuinely short row: the glyph alone, still
                        // named for VoiceOver by the label below.
                        action.icon.image(size: 20)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    // Fills the row's height, however tall the content made it.
                    .frame(maxHeight: .infinity)
                    .background(action.isDestructive ? Color.penpotDanger : Color.penpotAccent)
                    .accessibilityLabel(Text(action.title))
                }
                .buttonStyle(.plain)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: RevealWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(RevealWidthKey.self) { width in
            measuredRevealWidth = width
        }
    }

    /// Icon over title. The title takes a *fixed* width, not a max: only a definite width
    /// gets proposed down to the `Text`, which is what makes it re-wrap instead of laying
    /// out on one long line and being clipped ("Variante löschen"). Two lines absorb the
    /// compound German labels; the scale factor catches the unbreakable ones
    /// ("Wiederherstellen"). The vertical padding keeps the glyph off the row's edge.
    private func stack(_ action: PenpotSwipeAction,
                       icon: CGFloat,
                       size: CGFloat,
                       spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            action.icon.image(size: icon)
            Text(action.title)
                .font(.workSans(size: size, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(width: Self.labelWidth)
        }
        .padding(.vertical, 6)
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) { slot = .row }
    }
}

/// Carries the buttons' laid-out width up to the row, so the snap point matches whatever
/// the longest localized title turned out to need.
private struct RevealWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Snaps to fully open or fully closed, never in between. A custom behaviour rather than
/// `.viewAligned`, whose target is the *next view's leading edge* — here that lies beyond
/// the scrollable range, so where it would settle is not something to leave to chance.
private struct SwipeSnapBehavior: ScrollTargetBehavior {
    let revealWidth: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = target.rect.origin.x > revealWidth / 2 ? revealWidth : 0
    }
}

extension View {
    /// Reveals `actions` when the row is swiped left, the way `.swipeActions` would inside
    /// a `List`.
    ///
    /// - Parameter id: stable identity of the row (its model's id). Used only to close the
    ///   previously open row when this one opens.
    ///
    /// Apply it *outside* any `.contextMenu`, and keep that menu: it stays the discoverable
    /// route, and the only one on a row that is also a `NavigationLink`.
    func penpotSwipeActions(id: some Hashable,
                            @PenpotSwipeActionBuilder actions: () -> [PenpotSwipeAction]) -> some View {
        let built = actions()
        return Group {
            if built.isEmpty {
                self
            } else {
                modifier(PenpotSwipeRowModifier(rowID: AnyHashable(id), actions: built))
            }
        }
    }
}

/// Lets call sites write the actions as statements, so a permission check can drop one
/// without building an array by hand.
@resultBuilder
enum PenpotSwipeActionBuilder {
    static func buildBlock(_ components: [PenpotSwipeAction]...) -> [PenpotSwipeAction] {
        components.flatMap { $0 }
    }
    static func buildExpression(_ expression: PenpotSwipeAction) -> [PenpotSwipeAction] {
        [expression]
    }
    static func buildExpression(_ expression: [PenpotSwipeAction]) -> [PenpotSwipeAction] {
        expression
    }
    static func buildOptional(_ component: [PenpotSwipeAction]?) -> [PenpotSwipeAction] {
        component ?? []
    }
    static func buildEither(first component: [PenpotSwipeAction]) -> [PenpotSwipeAction] {
        component
    }
    static func buildEither(second component: [PenpotSwipeAction]) -> [PenpotSwipeAction] {
        component
    }
    static func buildArray(_ components: [[PenpotSwipeAction]]) -> [PenpotSwipeAction] {
        components.flatMap { $0 }
    }
}
