package app.penpot.android

import android.content.Context
import app.penpot.android.app.AppSettings
import app.penpot.android.app.AppState
import app.penpot.android.app.SessionStore
import app.penpot.core.network.SessionCookieJar
import coil3.ImageLoader
import coil3.disk.DiskCache
import coil3.disk.directory
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/**
 * Manual dependency graph (the app deliberately avoids a DI framework, mirroring the
 * zero-dependency spirit of the iOS client). Created once in [PenpotApplication].
 */
class AppGraph(context: Context) {

    val sessions = SessionStore(context)
    val settings = AppSettings(context)

    /**
     * The one OkHttp client. Its [SessionCookieJar] carries the `auth-token` cookie for
     * RPC calls *and* for image loads (`/assets/by-id/…` is cookie-authenticated), which
     * is why Coil must share it.
     */
    val http: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(SessionCookieJar(sessions))
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    val imageLoader: ImageLoader = ImageLoader.Builder(context)
        .components {
            add(OkHttpNetworkFetcherFactory(callFactory = { http }))
        }
        .memoryCache {
            MemoryCache.Builder().maxSizePercent(context, 0.20).build()
        }
        .diskCache {
            DiskCache.Builder()
                .directory(context.cacheDir.resolve("penpot_images"))
                .maxSizeBytes(128L * 1024 * 1024)
                .build()
        }
        .build()

    val appState = AppState(sessions, settings, http)

    /** Settings › About › "Clear image cache". */
    fun clearImageCaches() {
        imageLoader.memoryCache?.clear()
        imageLoader.diskCache?.clear()
    }
}
