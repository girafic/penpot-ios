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
    /* The SaaS cookie banner (injected via the <!--cookie-consent--> template hook) is
       chrome, not content — and with input swallowed it couldn't be dismissed anyway.
       Generic selectors plus the host containers of common consent tools (shadow-DOM
       vendors are hidden via their host element). Not accepting = no tracking. */
    [class*='cookie'], [id*='cookie'],
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
                                  failed: $failed)
                        .ignoresSafeArea(edges: .bottom)
                        .opacity(failed ? 0 : 1)
                }
                if isLoading && !failed {
                    PencilLoadingBadge(message: Text("Loading \(currentPageName)…"))
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
