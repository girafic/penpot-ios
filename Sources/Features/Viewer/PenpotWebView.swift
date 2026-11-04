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
    /// Reports Penpot's route name (`workspace`, `viewer`, `auth-login`, …) whenever the SPA
    /// routes — lets hosts detect it routing away (e.g. to `auth-login` when the injected
    /// session cookie has expired). See ``routeJS``.
    var onRouteChange: ((String) -> Void)? = nil
    /// Called when iOS kills the web content process (typically for exceeding its memory
    /// budget). `failed` is set too; the host decides how to explain it and when to retry.
    var onProcessTerminated: (() -> Void)? = nil

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

    /// Defines `window.__penpotRoute()`, Penpot's current route name, and reports every
    /// route change (as a `penpot:route` window event and to the `penpotRoute` handler).
    ///
    /// Penpot routed by hash (`#/workspace?…`, `#/auth/login`) until 2.19 and now routes by
    /// query string (`/?screen=workspace&…`, `/?screen=auth-login`), redirecting old links.
    /// Both forms map to the new route names, and the history API is hooked because the
    /// new router navigates with `pushState`/`replaceState`, which fire no `hashchange`.
    static let routeJS = """
    (function(){
      if (window.__penpotRoute) return;
      window.__penpotRoute = function () {
        var screen = /[?&]screen=([^&#]*)/.exec(location.search || '');
        if (screen) return decodeURIComponent(screen[1]);
        var path = (location.hash || '').replace(/^#\\/?/, '').split('?')[0];
        return path === 'view' ? 'viewer' : path.replace(/\\//g, '-');
      };
      var last = null;
      function changed() {
        var route = window.__penpotRoute();
        if (route === last) return;
        last = route;
        window.dispatchEvent(new CustomEvent('penpot:route', { detail: route }));
        try { window.webkit.messageHandlers.penpotRoute.postMessage(route); } catch (e) {}
      }
      ['pushState', 'replaceState'].forEach(function (name) {
        var original = history[name];
        history[name] = function () {
          var result = original.apply(this, arguments);
          changed();
          return result;
        };
      });
      window.addEventListener('popstate', changed);
      window.addEventListener('hashchange', changed);
      document.addEventListener('DOMContentLoaded', changed);
    })();
    """

    /// Makes the workspace view-only: swallows every trusted input event that could select,
    /// move, or edit shapes before Penpot sees it. The synthetic wheel events from the touch
    /// handler above are untrusted, so panning/zooming keeps working.
    ///
    /// Only Penpot's auth screens stay usable, so a session-expired login page shown in the
    /// web view still works. Everything else is blocked: the check fails closed. It used to
    /// allow input unless the hash contained `/workspace`, and when Penpot 2.19 moved to
    /// query-string routing the hash went empty and the canvas became editable.
    static let readOnlyGuardJS = """
    (function(){
      if (window.__penpotReadOnly) return; window.__penpotReadOnly = true;
      function usable(){ return (window.__penpotRoute ? window.__penpotRoute() : '').indexOf('auth') === 0; }
      function guard(e){
        if (!e.isTrusted || usable()) return;
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
          if (e.isTrusted && !usable()) e.stopImmediatePropagation();
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

    /// The user script that installs `css` as a `<style>` element. The CSS goes in as a
    /// JSON string literal: pasted into a JS template literal, a single backtick (even in
    /// a CSS comment) ended the string, broke the script, and silently dropped *all* the
    /// injected CSS.
    static func styleInjectionScript(css: String) -> String {
        let literal = (try? JSONEncoder().encode(css)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (function () {
          var s = document.createElement('style');
          s.textContent = \(literal);
          (document.head || document.documentElement).appendChild(s);
        })();
        """
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(source: Self.styleInjectionScript(css: injectedCSS),
                         injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Before everything else: the input guard and the hosts' route guards build on it.
        config.userContentController.addUserScript(
            WKUserScript(source: Self.routeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
        config.userContentController.add(context.coordinator, name: "penpotRoute")

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
            switch message.name {
            case "penpotLog":
                NSLog("PenpotWebView JS — %@", String(describing: message.body))
            case "penpotRoute":
                guard let route = message.body as? String else { return }
                NSLog("PenpotWebView — route: %@", route)
                parent.onRouteChange?(route)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            NSLog("PenpotWebView — navigation started: %@", webView.url?.absoluteString ?? "-")
            parent.isLoading = true
            parent.failed = false
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NSLog("PenpotWebView — navigation finished: %@", webView.url?.absoluteString ?? "-")
            parent.isLoading = false
        }
        /// iOS kills a web content process that outgrows its memory budget — Penpot's editor
        /// on a heavy page can do that on a 4 GB iPhone. Without this method WebKit reloads
        /// the page on its own, and a page that is simply too heavy crashes again: an
        /// endless reload loop. Stop and let the host show an error instead.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            NSLog("PenpotWebView — web content process terminated: %@", webView.url?.absoluteString ?? "-")
            parent.isLoading = false
            parent.failed = true
            parent.onProcessTerminated?()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("PenpotWebView — navigation failed: %@", error.localizedDescription)
            parent.isLoading = false
            parent.failed = true
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("PenpotWebView — provisional navigation failed: %@", error.localizedDescription)
            parent.isLoading = false
            parent.failed = true
        }
    }
}
