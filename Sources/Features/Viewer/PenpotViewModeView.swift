import SwiftUI

/// Penpot's prototype **view mode** (`#/view`) in a web view: plays interaction flows —
/// tapping hotspots navigates between boards — with the viewer's own header and thumbnail
/// strip hidden so only the presented board shows.
///
/// Unlike the workspace canvas this embed swallows **no** input: the view-mode route is
/// Penpot's dedicated read-only presentation app (no editing surface exists there), and
/// hotspots need real, trusted taps. The only mutating affordance — the header's edit
/// pencil — is hidden by CSS, and a hash guard bounces any navigation that would leave
/// `#/view` (except `#/auth`, which is surfaced natively as an expired session instead).
struct PenpotViewModeView: View {
    @Environment(\.dismiss) private var dismiss
    let baseURL: URL
    let fileID: String
    /// Pages that have something to play (the page picker only offers these).
    let pages: [CanvasPage]
    let title: String

    @State private var selectedPageID: String
    @State private var frameID: String?
    @State private var index: Int
    @State private var isLoading = true
    @State private var failed = false
    @State private var sessionExpired = false
    /// Bumped by "Retry" and a page switch to rebuild the web view: the same URL alone
    /// wouldn't reload it.
    @State private var webViewID = 0
    /// iOS ended the web content process: the view mode loads the whole file, and a large
    /// one (a design system) outgrows the memory a web view may use on an iPhone.
    @State private var ranOutOfMemory = false

    /// `initialFrameID` is the board to start on, `initialIndex` its position in the
    /// page's ``PenpotPage/viewerFrameIDs``.
    init(baseURL: URL, fileID: String, pages: [CanvasPage],
         initialPageID: String, initialFrameID: String? = nil, initialIndex: Int = 0,
         title: String) {
        self.baseURL = baseURL
        self.fileID = fileID
        self.pages = pages
        self.title = title
        _selectedPageID = State(initialValue: initialPageID)
        _frameID = State(initialValue: initialFrameID)
        _index = State(initialValue: initialIndex)
    }

    private var currentPageName: String {
        pages.first { $0.id == selectedPageID }?.name ?? title
    }

    private var viewModeURL: URL? {
        Self.viewModeURL(baseURL: baseURL, fileID: fileID, pageID: selectedPageID,
                         frameID: frameID, index: index)
    }

    /// The authenticated view-mode route, starting on `frameID`. Penpot looks the frame
    /// up in its own frame list and ignores `index` then (since 1.19.2; a frame hidden
    /// in the viewer starts at the first). `index`, the frame's position in that list,
    /// is for older servers. The viewer clamps an out-of-range index itself.
    ///
    /// `wasm=false` keeps the viewer on Penpot's classic SVG renderer. Newer servers play
    /// prototypes with the WebGL renderer (`available-viewer-wasm`) when the team has
    /// `render-wasm/v1`, and that outgrows a web view's memory on an iPhone within
    /// seconds, as on the canvas. The route parameter overrides the team's features; older
    /// servers ignore it.
    static func viewModeURL(baseURL: URL, fileID: String, pageID: String,
                            frameID: String?, index: Int) -> URL? {
        let frame = frameID.map { "&frame-id=\($0)" } ?? ""
        return URL(string: "\(baseURL.absoluteString)/#/view?file-id=\(fileID)&page-id=\(pageID)"
                   + "\(frame)&section=interactions&index=\(index)&wasm=false")
    }

    /// Hides the viewer chrome. Deliberately not reusing the workspace CSS: its broad
    /// `[class*='palette']`-style selectors could hit viewer classes, and the viewer's
    /// overlays (`viewer-overlay`) are prototype content that must stay visible.
    static let hideViewerChromeCSS = """
    [class*='viewer-header'], [class*='thumbnails-panel'], [class*='thumbnails-close'],
    [class*='viewer_thumbnails__'] {
        display: none !important;
    }
    [class*='viewer-section'] {
        inset: 0 !important;
        height: 100vh !important;
    }
    /* Input stays live here, but Penpot's modals (release notes, onboarding) don't belong
       in a presentation. */
    [class*='modal'], [class*='onboarding'], [class*='release-notes'] {
        display: none !important;
    }
    /* The SaaS cookie banner — chrome, not prototype content. It is Penpot's own
       `div.CookieConsent_wrapper` (penpot.app/scripts/cookie-consent.js): the `i` flag
       matters, attribute selectors are case-sensitive. Plus common consent-tool hosts.
       Not accepting = no tracking. */
    [class*='cookie' i], [id*='cookie' i],
    #onetrust-consent-sdk, #CybotCookiebotDialog, [class*='cky-'],
    [class*='osano-'], #didomi-host, #usercentrics-root {
        display: none !important;
    }
    /* No text selection loupe / callout on long-press while presenting. */
    * {
        -webkit-user-select: none !important;
        -webkit-touch-callout: none !important;
    }
    """

    /// The header is hidden, but keyboard shortcuts or deep links could still route away —
    /// and same-document route changes never reach the native navigation delegate. Bounce
    /// anything that leaves the viewer, except the auth screens (an expired session must
    /// not be trapped in a back-loop; it is detected natively via the route callback
    /// instead). Builds on ``PenpotWebView/routeJS``'s `penpot:route` event.
    private static let viewRouteGuardJS = """
    (function(){
      if (window.__penpotViewGuard) return; window.__penpotViewGuard = true;
      window.addEventListener('penpot:route', function (e) {
        var route = e.detail || '';
        if (route && route !== 'viewer' && route.indexOf('auth') !== 0) { history.back(); }
      });
    })();
    """

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                if let url = viewModeURL, !sessionExpired {
                    PenpotWebView(url: url,
                                  cookie: SessionStore.authCookie(for: baseURL),
                                  injectedCSS: Self.hideViewerChromeCSS,
                                  extraUserScripts: [Self.viewRouteGuardJS],
                                  isLoading: $isLoading,
                                  failed: $failed,
                                  onRouteChange: { route in
                                      if route.hasPrefix("auth") { sessionExpired = true }
                                  },
                                  // Without a handler WebKit reloads the page itself, and a
                                  // file that is too large dies again: an endless loop.
                                  onProcessTerminated: { ranOutOfMemory = true })
                        .id(webViewID)
                        .ignoresSafeArea(edges: .bottom)
                        .opacity(failed ? 0 : 1)
                }
                if isLoading && !failed && !sessionExpired {
                    PencilLoadingBadge(message: Text("Loading \(currentPageName)…"))
                }
                if failed && !sessionExpired {
                    ErrorStateView(message: ranOutOfMemory
                                   ? .appLocalized("This file is too large to present on this device. You can still open its boards one by one.")
                                   : .appLocalized("Couldn't load the presentation.")) {
                        reload()
                    }
                }
                if sessionExpired {
                    // Deliberately no appState.logout(): the RPC session may still be fine —
                    // only the web view's injected cookie was rejected (mirrors the canvas'
                    // conservative stance on Cloudflare hiccups).
                    ErrorStateView(message: .appLocalized("Your session has expired. Please sign in again."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .principal) { pageSwitcher }
            }
        }
        .onChange(of: selectedPageID) {
            // The starting board belonged to the initial page; other pages start at the top.
            frameID = nil
            index = 0
            if failed { reload() }
        }
    }

    /// Builds a fresh web view: "Retry", or another page after a failure (the failed web
    /// view stays hidden and would never show the new page).
    private func reload() {
        failed = false
        ranOutOfMemory = false
        isLoading = true
        webViewID += 1
    }

    @ViewBuilder
    private var pageSwitcher: some View {
        if pages.count > 1 {
            Menu {
                PenpotMenuChoices(selection: $selectedPageID,
                                  options: pages.map { (value: $0.id, label: Text($0.name)) })
            } label: {
                HStack(spacing: 4) {
                    Text(currentPageName).font(.workSans(.headline)).lineLimit(1)
                    AppIcon.chevronDown.image(size: 12)
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Switch page, current \(currentPageName)")
        } else {
            Text(currentPageName).font(.workSans(.headline)).lineLimit(1)
        }
    }
}
