package app.penpot.core.model

/**
 * Geometry shared by the comment-pin overlay and the board view.
 *
 * A comment thread's `position` and a board's `selrect` live in the same canvas
 * coordinate space, so a pin's board-relative location is a straight normalization
 * against the selrect. Values may fall outside 0…1 when a comment sits outside its
 * board — callers clamp if they need to.
 */
object PinMath {

    data class NormPoint(val x: Double, val y: Double) {
        companion object { val ZERO = NormPoint(0.0, 0.0) }
    }

    data class Size2(val width: Double, val height: Double) {
        companion object { val ZERO = Size2(0.0, 0.0) }
    }

    /** Canvas position → 0…1 coordinates relative to the board. Zero-size boards yield (0,0). */
    fun normalized(position: Point, selrect: Selrect): NormPoint {
        if (selrect.width <= 0 || selrect.height <= 0) return NormPoint.ZERO
        return NormPoint(
            x = (position.x - selrect.x) / selrect.width,
            y = (position.y - selrect.y) / selrect.height,
        )
    }

    /** Inverse of [normalized] — used when tapping the board to create a comment. */
    fun canvasPosition(normalized: NormPoint, selrect: Selrect): Point = Point(
        x = selrect.x + normalized.x * selrect.width,
        y = selrect.y + normalized.y * selrect.height,
    )

    /** Aspect-fit size of the board inside the available space. Degenerate inputs yield zero. */
    fun fittedSize(selrect: Selrect, availableWidth: Double, availableHeight: Double): Size2 {
        if (selrect.width <= 0 || selrect.height <= 0 || availableWidth <= 0 || availableHeight <= 0) {
            return Size2.ZERO
        }
        val scale = minOf(availableWidth / selrect.width, availableHeight / selrect.height)
        return Size2(width = selrect.width * scale, height = selrect.height * scale)
    }
}
