package app.penpot.android

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader

class PenpotApplication : Application(), SingletonImageLoader.Factory {

    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }

    /** Coil resolves its singleton loader here — the one sharing the session's OkHttp client. */
    override fun newImageLoader(context: PlatformContext): ImageLoader = graph.imageLoader
}
