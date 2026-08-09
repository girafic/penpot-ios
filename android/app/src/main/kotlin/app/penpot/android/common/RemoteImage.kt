package app.penpot.android.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil3.compose.SubcomposeAsyncImage
import okhttp3.HttpUrl

/** `{server}/assets/by-id/<mediaId>` — where Penpot serves uploaded media. */
fun assetUrl(baseUrl: HttpUrl, mediaId: String): String =
    baseUrl.newBuilder().addPathSegments("assets/by-id/$mediaId").build().toString()

/**
 * Cookie-authenticated remote image (Coil shares the app's OkHttp client, so
 * `/assets/by-id/…` loads carry the session cookie). Any failure shows the
 * placeholder — same silent-degrade behavior as the iOS RemoteImage.
 */
@Composable
fun RemoteImage(
    url: String?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Fit,
    placeholder: @Composable () -> Unit = { DefaultImagePlaceholder() },
) {
    if (url == null) {
        Box(modifier) { placeholder() }
        return
    }
    SubcomposeAsyncImage(
        model = url,
        contentDescription = contentDescription,
        modifier = modifier,
        contentScale = contentScale,
        loading = { placeholder() },
        error = { placeholder() },
    )
}

@Composable
fun DefaultImagePlaceholder(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = AppIcons.image,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(24.dp),
        )
    }
}
