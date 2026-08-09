package app.penpot.android.common

import android.icu.text.RelativeDateTimeFormatter
import android.icu.text.RelativeDateTimeFormatter.Direction
import android.icu.text.RelativeDateTimeFormatter.RelativeUnit
import app.penpot.core.model.PenpotDate
import java.time.Duration
import java.time.Instant

/**
 * Relative timestamps for the dashboard and comments.
 *
 * The unit ladder deliberately **skips weeks** — seconds → minutes → hours → days →
 * months (30 d) → years (365 d) — so 26 days reads "26 days ago", matching Penpot's
 * web UI rather than "3 weeks ago". (Ported from the iOS DateFormatting.)
 */
object DateFormatting {

    fun relative(raw: String?, now: Instant = Instant.now()): String? {
        val instant = PenpotDate.parse(raw) ?: return null
        val seconds = Duration.between(instant, now).seconds
        val future = seconds < 0
        val magnitude = if (future) -seconds else seconds

        val (quantity, unit) = when {
            magnitude < 60 -> magnitude to RelativeUnit.SECONDS
            magnitude < 3_600 -> magnitude / 60 to RelativeUnit.MINUTES
            magnitude < 86_400 -> magnitude / 3_600 to RelativeUnit.HOURS
            magnitude < 2_592_000 -> magnitude / 86_400 to RelativeUnit.DAYS
            magnitude < 31_536_000 -> magnitude / 2_592_000 to RelativeUnit.MONTHS
            else -> magnitude / 31_536_000 to RelativeUnit.YEARS
        }
        val formatter = RelativeDateTimeFormatter.getInstance()
        return formatter.format(
            quantity.toDouble(),
            if (future) Direction.NEXT else Direction.LAST,
            unit,
        )
    }
}
