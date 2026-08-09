package app.penpot.android.features.viewer

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import app.penpot.android.common.AppIcons
import app.penpot.android.ui.theme.LocalPenpotColors
import app.penpot.core.model.CommentThread

/**
 * The native comment pin: 28 dp accent circle (gray when resolved) with a white ring,
 * a tick (resolved) or comment glyph, and a red unread dot. Port of CommentPinView.
 */
@Composable
fun CommentPin(thread: CommentThread, modifier: Modifier = Modifier) {
    val colors = LocalPenpotColors.current
    val resolved = thread.isResolved == true
    Box(modifier = modifier.size(28.dp)) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .background(if (resolved) Color.Gray else colors.accent, CircleShape)
                .border(2.dp, Color.White, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = if (resolved) AppIcons.tick else AppIcons.comments,
                contentDescription = null,
                tint = if (resolved) Color.White else colors.onAccent,
                modifier = Modifier.size(14.dp),
            )
        }
        if (thread.unreadCount > 0) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = 2.dp, y = (-2).dp)
                    .size(9.dp)
                    .background(Color.Red, CircleShape)
                    .border(1.dp, Color.White, CircleShape),
            )
        }
    }
}
