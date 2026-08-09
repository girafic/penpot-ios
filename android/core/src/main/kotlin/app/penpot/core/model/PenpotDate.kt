package app.penpot.core.model

import java.time.Instant
import java.time.OffsetDateTime

/**
 * Timestamp handling for Penpot's API strings (ISO-8601, with or without fractional
 * seconds). Timestamps stay `String` in the models and are parsed only where needed —
 * matching the iOS app, whose decoder applies no date strategy.
 */
object PenpotDate {

    /** Parses an API timestamp, or null when it is absent or malformed. */
    fun parse(raw: String?): Instant? {
        if (raw.isNullOrBlank()) return null
        runCatching { return Instant.parse(raw) }
        return runCatching { OffsetDateTime.parse(raw).toInstant() }.getOrNull()
    }

    /**
     * Sort key for ordering by recency; unparseable/missing timestamps sort last
     * (the iOS `distantPast` behavior).
     */
    fun sortKey(raw: String?): Instant = parse(raw) ?: Instant.MIN
}
