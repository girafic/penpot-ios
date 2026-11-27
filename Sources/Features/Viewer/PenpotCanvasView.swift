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
    @State private var barWidth: CGFloat?
    @State private var isLoading = true
    @State private var failed = false
    /// Bumped by "Retry" to rebuild the web view: the same URL alone wouldn't reload it.
    @State private var webViewID = 0
    /// Set once the canvas crashed with WebGL on: the rest of this session uses Penpot's
    /// classic renderer. The setting itself stays as the user chose it.
    @State private var webGLFallback = false
    @State private var showsWebGLNotice = false
    /// The web content process died even without WebGL: the page is too heavy for iOS.
    @State private var ranOutOfMemory = false

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

    /// "Done" becomes an X where the page's name doesn't fit beside it
    /// (``NavigationBarFit``).
    private var compactBar: Bool {
        guard let barWidth else { return false }
        return !NavigationBarFit.titleFits(currentPageName, chevron: pages.count > 1,
                                          leading: .text(.appLocalized("Done")),
                                          trailingIcons: 0, width: barWidth)
    }

    /// Penpot's authenticated workspace route for the selected page.
    /// `wasm` mirrors the "WebGL rendering" app setting (the route override trumps profile
    /// and team flags). Off forces the classic SVG renderer: Penpot's wasm/Skia engine can
    /// exhaust the texture memory iOS grants a WKWebView and abort on zoom (tile-allocation
    /// panic in `_render`), which surfaces as Penpot's generic error toast.
    private var usesWebGL: Bool { settings.webGLRendering && !webGLFallback }

    private var workspaceURL: URL? {
        var query = "file-id=\(fileID)&page-id=\(selectedPageID)&wasm=\(usesWebGL)"
        if let teamID { query = "team-id=\(teamID)&" + query }
        return URL(string: "\(baseURL.absoluteString)/#/workspace?\(query)")
    }

    static let hideChromeCSS = """
    [class*='settings-bar'], [class*='left-settings-bar'], [class*='right-settings-bar'],
    [class*='left-sidebar'], [class*='right-sidebar'],
    [class*='workspace-header'], [class*='main-toolbar'], [class*='top-toolbar'],
    /* 2.18 renamed the drawing toolbar: main_ui_workspace_top_toolbar__toolbar & co. */
    [class*='workspace_top_toolbar__'],
    [class*='color-palette'], [class*='palette'],
    [class*='rulers'], [class*='ruler'] {
        display: none !important;
    }
    .viewport, [class*='viewport'], .workspace-content, [class*='workspace-content'] {
        inset: 0 !important;
        left: 0 !important; right: 0 !important; top: 0 !important; bottom: 0 !important;
        width: 100vw !important;
    }
    /* Penpot ≥ 2.18 keeps comment bubbles on the canvas outside comments mode. With input
       swallowed they're inert, and comments are handled natively — so hide the web layer. */
    [class*='workspace-comments-container'] {
        display: none !important;
    }
    /* Input is blocked, so any modal (release notes, onboarding) would be undismissable. */
    [class*='modal'], [class*='onboarding'], [class*='release-notes'] {
        display: none !important;
    }
    /* The SaaS cookie banner is chrome, not content — and with input swallowed it
       couldn't be dismissed anyway. It is Penpot's own `div.CookieConsent_wrapper`
       (penpot.app/scripts/cookie-consent.js): the `i` flag matters, attribute selectors
       are case-sensitive. Plus the host containers of common consent tools (shadow-DOM
       vendors are hidden via their host element). Not accepting = no tracking. */
    [class*='cookie' i], [id*='cookie' i],
    #onetrust-consent-sdk, #CybotCookiebotDialog, [class*='cky-'],
    [class*='osano-'], #didomi-host, #usercentrics-root {
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
                                  bridgeTouchToWheel: true,
                                  swallowInput: true,
                                  isLoading: $isLoading,
                                  failed: $failed,
                                  onProcessTerminated: handleProcessTermination)
                        .id(webViewID)
                        .ignoresSafeArea(edges: .bottom)
                        .opacity(failed ? 0 : 1)
                }
                if isLoading && !failed {
                    PencilLoadingBadge(message: Text("Loading \(currentPageName)…"))
                }
                if failed {
                    ErrorStateView(message: ranOutOfMemory
                                   ? .appLocalized("This page needs more memory than iOS allows for the canvas. Try a smaller page.")
                                   : .appLocalized("Couldn't load the canvas.")) {
                        failed = false
                        ranOutOfMemory = false
                        isLoading = true
                        webViewID += 1
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showsWebGLNotice {
                    webGLNotice
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(6))
                            withAnimation { showsWebGLNotice = false }
                        }
                }
            }
            .trackingWidth($barWidth)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { DoneButton(compact: compactBar) { dismiss() } }
                ToolbarItem(placement: .principal) { pageSwitcher }
            }
        }
    }

    private var webGLNotice: some View {
        Label {
            Text("WebGL rendering needed more memory than this device allows, so the canvas switched to standard rendering.")
        } icon: {
            AppIcon.info.image
        }
        .font(.workSans(.footnote))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.penpotSurface, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// iOS ended the web content process. On an iPhone, Penpot's WebGL renderer outgrows the
    /// memory a web view may use within seconds (reproduced on an iPhone 13 mini), so retry
    /// once with the classic renderer. If that dies as well, the page itself is too heavy.
    private func handleProcessTermination() {
        if usesWebGL {
            webGLFallback = true
            failed = false
            isLoading = true
            webViewID += 1
            withAnimation { showsWebGLNotice = true }
        } else {
            ranOutOfMemory = true
        }
    }

    private var pageSwitcher: some View {
        PageSwitcher(pages: pages, selection: $selectedPageID, fallbackTitle: title)
    }
}
