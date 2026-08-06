import SwiftUI
import WebKit

/// `WKWebView` wrapper for embedding Penpot's web app, shared by the read-only workspace
/// canvas and the prototype view mode. Injects the auth cookie + chrome-hiding CSS, and
/// reloads when the URL (page) changes. The two embeds differ in input handling:
///
/// - The **workspace** (``PenpotCanvasView``) passes `bridgeTouchToWheel` (touch → wheel
///   events, because the desktop canvas pans/zooms on wheel) and `swallowInput` (the
///   workspace is Penpot's real editor, so every trusted input event is blocked).
/// - The **view mode** (``PenpotViewModeView``) passes neither: the viewer is inherently
///   read-only and prototype hotspots need real, trusted taps.
struct PenpotWebView: UIViewRepresentable {
    let url: URL
    let cookie: HTTPCookie?
    let injectedCSS: String
    /// Translate touch gestures into wheel events (workspace canvas pan/zoom).
    var bridgeTouchToWheel = false
    /// Swallow all trusted input so nothing can be edited (workspace only).
    var swallowInput = false
    /// Additional user scripts, injected at document start after the built-in ones.
    var extraUserScripts: [String] = []
    @Binding var isLoading: Bool
    @Binding var failed: Bool
    /// Reports `location.hash` after each finished navigation — lets hosts detect the SPA
    /// routing away (e.g. to `#/auth` when the injected session cookie has expired).
    var onRouteChange: ((String) -> Void)? = nil

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
        if bridgeTouchToWheel {
            config.userContentController.addUserScript(
                WKUserScript(source: Self.touchPanJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if swallowInput {
            // Must come after touchPanJS: its document-level touch stoppers rely on the pan
            // handlers having registered (and run) first.
            config.userContentController.addUserScript(
                WKUserScript(source: Self.readOnlyGuardJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.userContentController.addUserScript(
            WKUserScript(source: Self.errorBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        for script in extraUserScripts {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
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
            NSLog("PenpotWebView JS — %@", String(describing: message.body))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.failed = false
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            if let onRouteChange = parent.onRouteChange {
                webView.evaluateJavaScript("location.hash") { result, _ in
                    if let hash = result as? String {
                        onRouteChange(hash)
                    }
                }
            }
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
