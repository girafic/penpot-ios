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
    @State private var index: Int
    @State private var isLoading = true
    @State private var failed = false
    @State private var sessionExpired = false

    init(baseURL: URL, fileID: String, pages: [CanvasPage],
         initialPageID: String, initialIndex: Int = 0, title: String) {
        self.baseURL = baseURL
        self.fileID = fileID
        self.pages = pages
        self.title = title
        _selectedPageID = State(initialValue: initialPageID)
        _index = State(initialValue: initialIndex)
    }

    private var currentPageName: String {
        pages.first { $0.id == selectedPageID }?.name ?? title
    }

    /// The authenticated view-mode route. `index` is the starting board's position among
    /// the page's viewer-visible frames (the viewer clamps out-of-range values itself).
    private var viewModeURL: URL? {
        URL(string: "\(baseURL.absoluteString)/#/view?file-id=\(fileID)&page-id=\(selectedPageID)"
            + "&section=interactions&index=\(index)")
    }

    /// Hides the viewer chrome. Deliberately not reusing the workspace CSS: its broad
    /// `[class*='palette']`-style selectors could hit viewer classes, and the viewer's
    /// overlays (`viewer-overlay`) are prototype content that must stay visible.
    private static let hideViewerChromeCSS = """
    [class*='viewer-header'], [class*='thumbnails-panel'], [class*='thumbnails-close'] {
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
    /* The SaaS cookie banner (injected via the <!--cookie-consent--> template hook) —
       chrome, not prototype content. Generic selectors plus common consent-tool hosts.
       Not accepting = no tracking. */
    [class*='cookie'], [id*='cookie'],
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
    /// and same-document hash changes never reach the native navigation delegate. Bounce
    /// anything that leaves `#/view`, except `#/auth` (an expired session must not be
    /// trapped in a back-loop; it is detected natively via the route callback instead).
    private static let viewRouteGuardJS = """
    (function(){
      if (window.__penpotViewGuard) return; window.__penpotViewGuard = true;
      window.addEventListener('hashchange', function () {
        var h = location.hash || '';
        if (h.indexOf('/view') === -1 && h.indexOf('/auth') === -1) { history.back(); }
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
                                  onRouteChange: { hash in
                                      if hash.hasPrefix("#/auth") { sessionExpired = true }
                                  })
                        .ignoresSafeArea(edges: .bottom)
                        .opacity(failed ? 0 : 1)
                }
                if isLoading && !failed && !sessionExpired {
                    PencilLoadingBadge(message: Text("Loading \(currentPageName)…"))
                }
                if failed && !sessionExpired {
                    ErrorStateView(message: "Couldn't load the presentation.") {
                        failed = false
                        isLoading = true
                    }
                }
                if sessionExpired {
                    // Deliberately no appState.logout(): the RPC session may still be fine —
                    // only the web view's injected cookie was rejected (mirrors the canvas'
                    // conservative stance on Cloudflare hiccups).
                    ErrorStateView(message: "Your session has expired. Please sign in again.")
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
            index = 0
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
