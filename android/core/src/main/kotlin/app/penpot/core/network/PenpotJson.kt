package app.penpot.core.network

import kotlinx.serialization.json.Json

/**
 * The one JSON configuration for Penpot API responses.
 *
 * Penpot returns camelCase keys that match the model property names, and several
 * responses are maps keyed by UUIDs (`pagesIndex`, `objects`, the object-thumbnail
 * map) whose keys must survive verbatim — so a naming strategy must **never** be
 * configured here.
 */
val PenpotJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    coerceInputValues = true
}
