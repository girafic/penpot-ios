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
struct PenpotCanvasView: View {
    @Environment(\.dismiss) private var dismiss
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
    private var workspaceURL: URL? {
        var query = "file-id=\(fileID)&page-id=\(selectedPageID)"
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

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
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

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: PenpotWebView
        var loadedURL: URL?
        init(_ parent: PenpotWebView) { self.parent = parent }

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
