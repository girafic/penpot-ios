import XCTest
@testable import PenpotiOS

final class PinGeometryTests: XCTestCase {
    private let board = Selrect(x: 100, y: 50, width: 400, height: 200)

    func testNormalizedPosition() {
        let point = Point(x: 300, y: 150)
        let norm = PinMath.normalized(position: point, in: board)
        XCTAssertEqual(norm.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(norm.y, 0.5, accuracy: 0.0001)
    }

    func testNormalizedRoundTrip() {
        let original = Point(x: 220, y: 90)
        let norm = PinMath.normalized(position: original, in: board)
        let back = PinMath.canvasPosition(normalized: norm, in: board)
        XCTAssertEqual(back.x, original.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, original.y, accuracy: 0.0001)
    }

    func testZeroSizeIsSafe() {
        let degenerate = Selrect(x: 0, y: 0, width: 0, height: 0)
        let norm = PinMath.normalized(position: Point(x: 5, y: 5), in: degenerate)
        XCTAssertEqual(norm, .zero)
    }

    func testFittedSizePreservesAspectRatio() {
        let fitted = PinMath.fittedSize(selrect: board, in: CGSize(width: 200, height: 200))
        // 400x200 fit into 200x200 → width-constrained → 200x100.
        XCTAssertEqual(fitted.width, 200, accuracy: 0.0001)
        XCTAssertEqual(fitted.height, 100, accuracy: 0.0001)
    }
}
