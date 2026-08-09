package app.penpot.core

import app.penpot.core.model.PinMath
import app.penpot.core.model.Point
import app.penpot.core.model.Selrect
import org.junit.Assert.assertEquals
import org.junit.Test

/** Port of the iOS PinGeometryTests. */
class PinMathTest {

    private val board = Selrect(x = 100.0, y = 50.0, width = 400.0, height = 200.0)

    @Test
    fun normalizedPosition() {
        val norm = PinMath.normalized(Point(300.0, 150.0), board)
        assertEquals(0.5, norm.x, 1e-4)
        assertEquals(0.5, norm.y, 1e-4)
    }

    @Test
    fun normalizedRoundTrip() {
        val original = Point(220.0, 90.0)
        val norm = PinMath.normalized(original, board)
        val back = PinMath.canvasPosition(norm, board)
        assertEquals(original.x, back.x, 1e-4)
        assertEquals(original.y, back.y, 1e-4)
    }

    @Test
    fun zeroSizeIsSafe() {
        val degenerate = Selrect(0.0, 0.0, 0.0, 0.0)
        val norm = PinMath.normalized(Point(5.0, 5.0), degenerate)
        assertEquals(PinMath.NormPoint.ZERO, norm)
    }

    @Test
    fun outsideBoardFallsOutsideUnitRange() {
        val norm = PinMath.normalized(Point(0.0, 0.0), board)
        assertEquals(-0.25, norm.x, 1e-4)
        assertEquals(-0.25, norm.y, 1e-4)
    }

    @Test
    fun fittedSizePreservesAspectRatio() {
        val fitted = PinMath.fittedSize(board, availableWidth = 200.0, availableHeight = 200.0)
        // 400x200 fit into 200x200 → width-constrained → 200x100.
        assertEquals(200.0, fitted.width, 1e-4)
        assertEquals(100.0, fitted.height, 1e-4)
    }

    @Test
    fun fittedSizeDegenerateInputsYieldZero() {
        assertEquals(PinMath.Size2.ZERO, PinMath.fittedSize(Selrect(0.0, 0.0, 0.0, 100.0), 200.0, 200.0))
        assertEquals(PinMath.Size2.ZERO, PinMath.fittedSize(board, 0.0, 200.0))
    }
}
