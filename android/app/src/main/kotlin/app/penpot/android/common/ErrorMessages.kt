package app.penpot.android.common

import android.content.Context
import app.penpot.core.network.PenpotError
import app.penpot.android.R

/**
 * User-facing message for any failure — the Android port of `PenpotError.errorDescription`.
 * Resolved through app resources so errors follow the in-app language.
 */
fun Throwable.userMessage(context: Context): String = when (this) {
    is PenpotError.InvalidUrl -> context.getString(R.string.invalid_server_url)
    is PenpotError.InvalidResponse -> context.getString(R.string.the_server_returned_an_unexpected_response)
    is PenpotError.Unauthorized -> context.getString(R.string.your_session_has_expired_please_log_in_again)
    is PenpotError.Forbidden -> context.getString(R.string.the_server_blocked_this_request_403)
    is PenpotError.Server -> {
        val summary = serverMessage
        if (summary != null) {
            context.getString(R.string.request_failed_d_s, status, summary)
        } else {
            context.getString(R.string.request_failed_with_status_d, status)
        }
    }
    is PenpotError.Decoding ->
        context.getString(R.string.could_not_read_the_server_response_s, cause?.message ?: "")
    else -> message ?: context.getString(R.string.something_went_wrong)
}
