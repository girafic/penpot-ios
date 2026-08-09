package app.penpot.android.features.viewer

import android.annotation.SuppressLint
import android.util.Log
import android.view.View
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.navigation.NavController
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import app.penpot.android.AppGraph
import app.penpot.android.R
import app.penpot.android.common.AppIcons
import app.penpot.android.common.ErrorState
import app.penpot.android.common.LoadingState
import app.penpot.android.common.PenpotScreen
import app.penpot.core.network.AuthCookie

/**
 * Full-screen live canvas: Penpot's web **workspace** rendered in a WebView,
 * authenticated by handing the session's `auth-token` cookie to the CookieManager
 * before the first load, with panels/chrome hidden via injected CSS so only the
 * design canvas shows. Strictly view-only — an injected guard swallows every trusted
 * input event; only the touch events driving the wheel-event pan/zoom synthesis stay
 * live. Comments stay native. (Port of the iOS PenpotCanvasView; the four injected
 * scripts live in assets/canvas/ and are shared nearly verbatim.)
 */
@Composable
fun PenpotCanvasScreen(graph: AppGraph, nav: NavController, route: app.penpot.android.nav.CanvasRoute) {
    val context = LocalContext.current
    val client = graph.appState.client ?: return
    val settings = graph.settings

    var pages by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) } // id → name
    var selectedPageId by remember { mutableStateOf(route.pageId) }
    var isLoading by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    var reloadKey by remember { mutableStateOf(0) }

    // Page names for the switcher; the canvas itself needs only ids.
    LaunchedEffect(Unit) {
        runCatching { client.file(route.fileId) }.getOrNull()?.let { file ->
            pages = file.pages.map { it.id to it.name }
        }
    }

    val currentPageName = pages.firstOrNull { it.first == selectedPageId }?.second
        ?: stringResource(R.string.page)

    // Penpot's authenticated workspace route for the selected page. `wasm` mirrors the
    // "WebGL rendering" setting (the route override trumps profile and team flags).
    val url = buildString {
        append(client.baseUrl.toString().trimEnd('/'))
        append("/#/workspace?")
        append("team-id=").append(route.teamId).append('&')
        append("file-id=").append(route.fileId)
        append("&page-id=").append(selectedPageId)
        append("&wasm=").append(settings.webGLRendering)
    }

    PenpotScreen(
        title = currentPageName,
        nav = nav,
        actions = {
            if (pages.size > 1) {
                var switcherOpen by remember { mutableStateOf(false) }
                Box {
                    androidx.compose.material3.IconButton(onClick = { switcherOpen = true }) {
                        Icon(
                            AppIcons.chevronDown,
                            contentDescription = stringResource(R.string.switch_page_current_s, currentPageName),
                        )
                    }
                    DropdownMenu(expanded = switcherOpen, onDismissRequest = { switcherOpen = false }) {
                        for ((id, name) in pages) {
                            DropdownMenuItem(
                                text = {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        if (id == selectedPageId) {
                                            Icon(
                                                AppIcons.tick, null,
                                                modifier = Modifier.padding(start = 8.dp).size(16.dp),
                                            )
                                        }
                                    }
                                },
                                onClick = {
                                    switcherOpen = false
                                    // Penpot doesn't re-route on an in-app page-id change,
                                    // so switching reloads the web view.
                                    selectedPageId = id
                                },
                            )
                        }
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            if (!failed) {
                PenpotWebView(
                    url = url,
                    serverOrigin = client.baseUrl.toString(),
                    authToken = graph.sessions.authToken,
                    isSecureServer = client.baseUrl.isHttps,
                    reloadKey = reloadKey,
                    onLoading = { isLoading = it },
                    onFailed = {
                        isLoading = false
                        failed = true
                    },
                )
            }
            if (isLoading && !failed) {
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    tonalElevation = 4.dp,
                    modifier = Modifier.align(Alignment.Center),
                ) {
                    LoadingState(
                        stringResource(R.string.loading_s, currentPageName),
                        Modifier.padding(8.dp),
                    )
                }
            }
            if (failed) {
                ErrorState(stringResource(R.string.couldn_t_load_the_canvas)) {
                    failed = false
                    isLoading = true
                    reloadKey += 1
                }
            }
        }
    }
}

private class PenpotLogBridge {
    @JavascriptInterface
    fun log(message: String) {
        Log.w("PenpotCanvas", "JS — $message")
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun PenpotWebView(
    url: String,
    serverOrigin: String,
    authToken: String?,
    isSecureServer: Boolean,
    reloadKey: Int,
    onLoading: (Boolean) -> Unit,
    onFailed: () -> Unit,
) {
    val context = LocalContext.current

    // Scripts load once; the CSS is wrapped in the same style-appender IIFE as on iOS.
    val scripts = remember {
        val assets = context.assets
        fun read(name: String) = assets.open("canvas/$name").bufferedReader().use { it.readText() }
        val css = read("hide_chrome.css")
        val cssJs = """
        (function () {
          var s = document.createElement('style');
          s.textContent = `$css`;
          (document.head || document.documentElement).appendChild(s);
        })();
        """.trimIndent()
        // Registration order matters: css → touch_pan → read_only_guard → error_bridge.
        listOf(cssJs, read("touch_pan.js"), read("read_only_guard.js"), read("error_bridge.js"))
    }

    AndroidView(
        factory = { ctx ->
            WebView(ctx).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.setSupportZoom(false)
                settings.builtInZoomControls = false
                overScrollMode = View.OVER_SCROLL_NEVER
                isHorizontalScrollBarEnabled = false
                isVerticalScrollBarEnabled = false
                addJavascriptInterface(PenpotLogBridge(), "PenpotBridge")

                val documentStart = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
                if (documentStart) {
                    for (script in scripts) {
                        WebViewCompat.addDocumentStartJavaScript(this, script, setOf("*"))
                    }
                }

                webViewClient = object : WebViewClientCompat() {
                    override fun onPageStarted(view: WebView?, startedUrl: String?, favicon: android.graphics.Bitmap?) {
                        super.onPageStarted(view, startedUrl, favicon)
                        onLoading(true)
                        if (!documentStart && view != null) {
                            // Fallback: Penpot is an SPA whose handlers attach well after
                            // document start, so injecting here is early enough.
                            for (script in scripts) view.evaluateJavascript(script, null)
                        }
                    }

                    override fun onPageFinished(view: WebView?, finishedUrl: String?) {
                        super.onPageFinished(view, finishedUrl)
                        onLoading(false)
                    }

                    override fun onReceivedError(
                        view: WebView,
                        request: WebResourceRequest,
                        error: WebResourceError,
                    ) {
                        super.onReceivedError(view, request, error)
                        if (request.isForMainFrame) onFailed()
                    }
                }

                // Cookie before the first load — otherwise the workspace bounces to login.
                val cookies = CookieManager.getInstance()
                cookies.setAcceptCookie(true)
                cookies.setAcceptThirdPartyCookies(this, true)
                if (authToken != null) {
                    val header = buildString {
                        append(AuthCookie.NAME).append('=').append(authToken).append("; Path=/")
                        if (isSecureServer) append("; Secure")
                    }
                    cookies.setCookie(serverOrigin, header)
                    cookies.flush()
                }
            }
        },
        update = { webView ->
            val stamp = "$url#$reloadKey"
            if (webView.tag != stamp) {
                webView.tag = stamp
                webView.loadUrl(url)
            }
        },
        modifier = Modifier.fillMaxSize(),
    )
}
