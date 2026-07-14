import SwiftUI
import WebKit

/// A page the canvas can display/switch between (id + display name).
struct CanvasPage: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Full-screen live canvas: Penpot's web **workspace** rendered in a `WKWebView`, authenticated
/// by injecting the session's `auth-token` cookie, with the left/right panels and top chrome
/// hidden via injected CSS so only the design canvas shows. A native page picker switches pages
/// (Penpot doesn't re-route on an in-app page-id change, so switching reloads the web view).
/// Comments stay handled natively via the RPC client.
///
/// The canvas is strictly view-only: the workspace is Penpot's real editor and its own
/// read-only state isn't reachable via URL, so an injected guard swallows every trusted
/// input event (pointer/mouse/click/keyboard) before the page sees it. Only the touch
/// events driving the pan/zoom translation stay live.
struct PenpotCanvasView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    let baseURL: URL
    let fileID: String
    let teamID: String?
    let pages: [CanvasPage]
    let title: String

    @State private var selectedPageID: String
    @State private var isLoading = true
    @State private var failed = false

    init(baseURL: URL, fileID: String, teamID: String?, pages: [CanvasPage],
         initialPageID: String, title: String) {
        self.baseURL = baseURL
        self.fileID = fileID
        self.teamID = teamID
        self.pages = pages
        self.title = title
        _selectedPageID = State(initialValue: initialPageID)
    }

    private var currentPageName: String {
        pages.first { $0.id == selectedPageID }?.name ?? title
    }

    /// Penpot's authenticated workspace route for the selected page.
    /// `wasm` mirrors the "WebGL rendering" app setting (the route override trumps profile
    /// and team flags). Off forces the classic SVG renderer: Penpot's wasm/Skia engine can
    /// exhaust the texture memory iOS grants a WKWebView and abort on zoom (tile-allocation
    /// panic in `_render`), which surfaces as Penpot's generic error toast.
    private var workspaceURL: URL? {
        var query = "file-id=\(fileID)&page-id=\(selectedPageID)&wasm=\(settings.webGLRendering)"
        if let teamID { query = "team-id=\(teamID)&" + query }
        return URL(string: "\(baseURL.absoluteString)/#/workspace?\(query)")
    }

    private static let hideChromeCSS = """
    [class*='settings-bar'], [class*='left-settings-bar'], [class*='right-settings-bar'],
    [class*='left-sidebar'], [class*='right-sidebar'],
    [class*='workspace-header'], [class*='main-toolbar'], [class*='top-toolbar'],
    [class*='color-palette'], [class*='palette'],
    [class*='rulers'], [class*='ruler'] {
        display: none !important;
    }
    .viewport, [class*='viewport'], .workspace-content, [class*='workspace-content'] {
        inset: 0 !important;
        left: 0 !important; right: 0 !important; top: 0 !important; bottom: 0 !important;
        width: 100vw !important;
    }
    /* Input is blocked, so any modal (release notes, onboarding) would be undismissable. */
    [class*='modal'], [class*='onboarding'], [class*='release-notes'] {
        display: none !important;
    }
    /* No text selection loupe / callout on long-press in a view-only canvas. */
    * {
        -webkit-user-select: none !important;
        -webkit-touch-callout: none !important;
    }
    """

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                if let url = workspaceURL {
                    PenpotWebView(url: url,
                                  cookie: SessionStore.authCookie(for: baseURL),
                                  injectedCSS: Self.hideChromeCSS,
                                  isLoading: $isLoading,
                                  failed: $failed)
                        .ignoresSafeArea(edges: .bottom)
                        .opacity(failed ? 0 : 1)
                }
                if isLoading && !failed {
                    ProgressView("Loading \(currentPageName)…")
                        .padding(20)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                if failed {
                    ErrorStateView(message: "Couldn't load the canvas.") {
                        failed = false
                        isLoading = true
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .principal) { pageSwitcher }
            }
        }
    }

    @ViewBuilder
    private var pageSwitcher: some View {
        if pages.count > 1 {
            Menu {
                Picker("Page", selection: $selectedPageID) {
                    ForEach(pages) { page in
                        Text(page.name).tag(page.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentPageName).font(.headline).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.bold())
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Switch page, current \(currentPageName)")
        } else {
            Text(currentPageName).font(.headline).lineLimit(1)
        }
    }
}

/// `WKWebView` wrapper that injects an auth cookie + chrome-hiding CSS + touch-pan handling,
/// and reloads when the URL (page) changes.
private struct PenpotWebView: UIViewRepresentable {
    let url: URL
    let cookie: HTTPCookie?
    let injectedCSS: String
    @Binding var isLoading: Bool
    @Binding var failed: Bool

    /// Translates touch gestures into the wheel events Penpot's desktop canvas pans/zooms on:
    /// one-finger drag → pan, two-finger pinch → zoom (Penpot zooms on ctrl+wheel).
    private static let touchPanJS = """
    (function(){
      if (window.__penpotTouch) return; window.__penpotTouch = true;
      var lastX=0,lastY=0,panning=false,lastDist=0;
      function dist(t){return Math.hypot(t[0].clientX-t[1].clientX, t[0].clientY-t[1].clientY);}
      function fire(x,y,dx,dy,zoom){
        var el=document.elementFromPoint(x,y)||document.body;
        el.dispatchEvent(new WheelEvent('wheel',{deltaX:dx,deltaY:dy,clientX:x,clientY:y,ctrlKey:!!zoom,bubbles:true,cancelable:true}));
      }
      document.addEventListener('touchstart',function(e){
        if(e.touches.length===1){panning=true;lastX=e.touches[0].clientX;lastY=e.touches[0].clientY;}
        else if(e.touches.length===2){panning=false;lastDist=dist(e.touches);}
      },{passive:false,capture:true});
      document.addEventListener('touchmove',function(e){
        var t=e.touches;
        if(t.length===1&&panning){var x=t[0].clientX,y=t[0].clientY;fire(x,y,lastX-x,lastY-y,false);lastX=x;lastY=y;e.preventDefault();}
        else if(t.length===2){var nd=dist(t),cx=(t[0].clientX+t[1].clientX)/2,cy=(t[0].clientY+t[1].clientY)/2;fire(cx,cy,0,lastDist-nd,true);lastDist=nd;e.preventDefault();}
      },{passive:false,capture:true});
      document.addEventListener('touchend',function(e){if(e.touches.length===0)panning=false;},{passive:false,capture:true});
    })();
    """

    /// Makes the workspace view-only: swallows every trusted input event that could select,
    /// move, or edit shapes before Penpot sees it. The synthetic wheel events from the touch
    /// handler above are untrusted, so panning/zooming keeps working. Guarded by the route so
    /// a session-expired login page shown in the web view stays usable.
    private static let readOnlyGuardJS = """
    (function(){
      if (window.__penpotReadOnly) return; window.__penpotReadOnly = true;
      function inWorkspace(){ return location.hash.indexOf('/workspace') !== -1; }
      function guard(e){
        if (!e.isTrusted || !inWorkspace()) return;
        e.preventDefault(); e.stopImmediatePropagation();
      }
      // pointermove/mousemove stay allowed: they only feed Penpot's internal position
      // streams (hover, zoom targets) and cannot select or move anything on their own —
      // that needs pointerdown/click, which stay blocked.
      ['pointerdown','pointerup','pointercancel',
       'mousedown','mouseup','click','dblclick','auxclick','contextmenu',
       'keydown','keypress','keyup','dragstart','drop','cut','paste','beforeinput'
      ].forEach(function(t){ window.addEventListener(t, guard, {capture:true, passive:false}); });
      // Touch events must stay live for the pan/zoom translation (registered on document
      // before this script), but must not travel on to Penpot's own canvas handlers.
      ['touchstart','touchmove','touchend','touchcancel'].forEach(function(t){
        document.addEventListener(t, function(e){
          if (e.isTrusted && inWorkspace()) e.stopImmediatePropagation();
        }, {capture:true, passive:false});
      });
    })();
    """

    /// Penpot catches workspace exceptions itself and shows only a generic toast, but it
    /// logs the real error via `console.error` — forward those (plus uncaught errors and
    /// promise rejections) to the native log so canvas issues are diagnosable.
    private static let errorBridgeJS = """
    (function(){
      if (window.__penpotErrLog) return; window.__penpotErrLog = true;
      function send(kind, msg){
        try { window.webkit.messageHandlers.penpotLog.postMessage(kind + ': ' + msg); } catch(e){}
      }
      window.addEventListener('error', function(e){
        send('js-error', (e.message||'') + ' @' + (e.filename||'') + ':' + (e.lineno||0)
             + (e.error && e.error.stack ? '\\n' + e.error.stack : ''));
      }, true);
      window.addEventListener('unhandledrejection', function(e){
        var r = e.reason;
        send('promise', (r && (r.stack || r.message)) || String(r));
      });
      var ce = console.error;
      console.error = function(){
        var parts = [];
        for (var i = 0; i < arguments.length; i++) {
          var a = arguments[i];
          try { parts.push(a instanceof Error ? (a.stack || a.message) : (typeof a === 'object' ? JSON.stringify(a) : String(a))); }
          catch(err) { parts.push(String(a)); }
        }
        send('console.error', parts.join(' '));
        ce.apply(console, arguments);
      };
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let cssJS = """
        (function () {
          var s = document.createElement('style');
          s.textContent = `\(injectedCSS)`;
          (document.head || document.documentElement).appendChild(s);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: cssJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(
            WKUserScript(source: Self.touchPanJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Must come after touchPanJS: its document-level touch stoppers rely on the pan
        // handlers having registered (and run) first.
        config.userContentController.addUserScript(
            WKUserScript(source: Self.readOnlyGuardJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(
            WKUserScript(source: Self.errorBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(context.coordinator, name: "penpotLog")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        let isFirst = context.coordinator.loadedURL == nil
        context.coordinator.loadedURL = url
        let load = { _ = webView.load(URLRequest(url: url)) }
        if isFirst, let cookie {
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie, completionHandler: load)
        } else {
            load()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let parent: PenpotWebView
        var loadedURL: URL?
        init(_ parent: PenpotWebView) { self.parent = parent }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "penpotLog" else { return }
            NSLog("PenpotCanvas JS — %@", String(describing: message.body))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.failed = false
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.failed = true
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.failed = true
        }
    }
}
