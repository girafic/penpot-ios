import CoreGraphics
import Foundation

/// Pure functions mapping between Penpot canvas coordinates and the displayed board image.
///
/// A comment thread's `position` and a board's `selrect` live in the same canvas
/// coordinate space, so a pin's position relative to the board image is the normalized
/// offset of the thread position within the board's selrect.
enum PinMath {
    /// Normalized (0...1) position of `position` inside `selrect`. Values may fall
    /// outside 0...1 if the comment sits outside the board.
    static func normalized(position: Point, in selrect: Selrect) -> CGPoint {
        guard selrect.width > 0, selrect.height > 0 else { return .zero }
        return CGPoint(x: (position.x - selrect.x) / selrect.width,
                       y: (position.y - selrect.y) / selrect.height)
    }

    /// Inverse of ``normalized(position:in:)`` — maps a normalized point back to canvas
    /// coordinates. Used when creating a new comment from a tap on the board image.
    static func canvasPosition(normalized point: CGPoint, in selrect: Selrect) -> Point {
        Point(x: selrect.x + Double(point.x) * selrect.width,
              y: selrect.y + Double(point.y) * selrect.height)
    }

    /// Aspect-fits a board's selrect into `available`, returning the displayed image size.
    static func fittedSize(selrect: Selrect, in available: CGSize) -> CGSize {
        guard selrect.width > 0, selrect.height > 0,
              available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / selrect.width, available.height / selrect.height)
        return CGSize(width: selrect.width * scale, height: selrect.height * scale)
    }
}
