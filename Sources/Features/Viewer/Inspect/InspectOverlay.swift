import SwiftUI

/// Penpot's inspect selection feedback (`ui/inspect/selection_feedback.cljs`,
/// `ui/measurements.cljs`): the selection's box in `--color-accent-tertiary`, its size
/// on a white pill at its bottom, and its distances to the board's edges in
/// `--color-accent-quaternary`. Penpot measures against the shape under the pointer, the
/// board when there is none; touch has no pointer, so it is always the board.
///
/// Drawn in screen space, not inside the zoomed board, so lines and labels keep their
/// size under zoom, as Penpot divides them by its zoom.
struct InspectOverlay: View {
    let board: InspectBoard
    let selectedID: String
    /// Canvas coordinates to this view's.
    let transform: CGAffineTransform

    @Environment(\.colorScheme) private var colorScheme

    /// `$pink-400`, the same on light and dark.
    static let distanceColor = Color(red: 0xFF / 255, green: 0x6F / 255, blue: 0xE0 / 255)
    private static let fontSize: CGFloat = 11
    private static let pillHeight: CGFloat = 16
    private static let pillWidth: CGFloat = 50

    var body: some View {
        Canvas { context, size in
            let box = board.bounds(selectedID)
            guard !box.isNull else { return }
            let screen = box.applying(transform)
            if selectedID != board.boardID {
                drawDistances(from: box, in: &context, bounds: CGRect(origin: .zero, size: size))
            }
            context.stroke(Path(screen), with: .color(.penpotAccentTertiary), lineWidth: 1)
            drawSize(of: box, at: screen, in: &context)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// `size-display*`: "W x H" on a white pill, 70 % opaque, inside the box's bottom edge.
    private func drawSize(of box: CGRect, at screen: CGRect, in context: inout GraphicsContext) {
        let label = "\(InspectBoard.trim(box.width)) x \(InspectBoard.trim(box.height))"
        let width: CGFloat = label.count <= 9 ? 50 : 75
        let pill = CGRect(x: screen.midX - width / 2, y: screen.maxY - Self.pillHeight,
                          width: width, height: Self.pillHeight)
        context.fill(Path(pill), with: .color(.white.opacity(0.7)))
        context.draw(Text(verbatim: label).font(.system(size: Self.fontSize)).foregroundColor(.black),
                     at: CGPoint(x: pill.midX, y: pill.midY))
    }

    /// `measurement*` for a hovered shape that contains the selection: a line from the
    /// middle of each of the selection's edges to the board's, with its length.
    private func drawDistances(from box: CGRect, in context: inout GraphicsContext, bounds: CGRect) {
        let frame = board.rect
        let lines: [(from: CGPoint, to: CGPoint, length: CGFloat)] = [
            (CGPoint(x: box.minX, y: box.midY), CGPoint(x: frame.minX, y: box.midY), box.minX - frame.minX),
            (CGPoint(x: box.maxX, y: box.midY), CGPoint(x: frame.maxX, y: box.midY), frame.maxX - box.maxX),
            (CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.midX, y: frame.minY), box.minY - frame.minY),
            (CGPoint(x: box.midX, y: box.maxY), CGPoint(x: box.midX, y: frame.maxY), frame.maxY - box.maxY),
        ]
        for line in lines where line.length > 0.005 {
            let a = line.from.applying(transform), b = line.to.applying(transform)
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            context.stroke(path, with: .color(Self.distanceColor), lineWidth: 1)
            drawPill("\(InspectBoard.trim(line.length))px",
                     at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), bounds: bounds, in: &context)
        }
    }

    /// `distance-pill*`: kept inside the view, as Penpot keeps it inside the board.
    private func drawPill(_ label: String, at center: CGPoint, bounds: CGRect, in context: inout GraphicsContext) {
        var pill = CGRect(x: center.x - Self.pillWidth / 2, y: center.y - Self.pillHeight / 2,
                          width: Self.pillWidth, height: Self.pillHeight)
        pill.origin.x = min(max(pill.minX, bounds.minX), bounds.maxX - pill.width)
        pill.origin.y = min(max(pill.minY, bounds.minY), bounds.maxY - pill.height)
        context.fill(Path(roundedRect: pill, cornerRadius: 2), with: .color(Self.distanceColor))
        context.draw(Text(verbatim: label).font(.system(size: Self.fontSize)).foregroundColor(.white),
                     at: CGPoint(x: pill.midX, y: pill.midY))
    }
}
