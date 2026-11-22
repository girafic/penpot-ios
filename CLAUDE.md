# Penpot iOS — working notes for Claude

A native SwiftUI client for browsing, reviewing and commenting on Penpot design files.

**Name and icon: "Viewer for Penpot"**, unofficial. "Penpot" and its logo are Kaleidos'
trademarks (App Review 5.2.1 / 4.1), so the app is *Viewer for Penpot* in the store,
**"Viewer"** on the home screen (`CFBundleDisplayName`), bundle ID
`io.github.girafic.viewerforpenpot` (never `app.penpot.*`), with its own icon: an eye
drawn as a vector path (round nodes like Penpot's path editor, a bezier handle), flat on
Penpot purple `#6911D4` (white eye, `#7EFFF5` iris and handle, `#18181A` pupil). `AppIcon`
is that; the `LaunchLogo` and the splash's `AppMark` are the same glyph in one color, the
node rings and the iris cut out by an even-odd clip path (a mask would be rasterized in
the PDF).
Penpot's logo (`PenpotLogo`) stays only where Penpot itself shows it: the default team's
avatar. The repo and the Xcode target keep the name `penpot-ios` / `PenpotiOS`.

## Use the knowledge graph first

This repo ships a **graphify knowledge graph** of the Swift source in `graphify-out/`.
Before grepping or reading files to understand architecture, call graphs, or "what uses X",
**query the graph** — it's the fastest, most complete map of how a change ripples:

- Ask: `/graphify query "how does the auth/session flow work?"`
- Trace a path: `/graphify path "LoginView" "PenpotClient"`
- Explain a node: `/graphify explain "PenpotClient"`
- Read the map directly: `graphify-out/GRAPH_REPORT.md` (audit + communities),
  `graphify-out/graph.html` (interactive), `graphify-out/graph.json` (raw, GraphRAG-ready).

Coverage: **92 Swift files → 1,995 nodes / 4,959 edges / 122 communities** (Swift AST +
the docs). Highest-connected app-owned nodes: `AppIcon`, `Writer` (the SVG writer in
`PenpotSVG`), `PenpotClient`, `PageCanvasUIView`, `BoardPreviewRenderer`, `FileListItem`,
`PenpotError`. `Models.swift` is the cross-domain bridge —
nearly every feature decodes through it.

## Keep the graph fresh

After changing Swift files, refresh it: **`graphify update .`** (incremental; Swift AST
extraction is free, no API key needed). Never hand-edit anything under `graphify-out/`.
The graph is scoped to the Swift source + README + `project.yml`; icon assets and
asset-catalog JSON are deliberately excluded as noise.

## Project shape

- **Networking/** — `PenpotClient` plus one extension per domain: `+Dashboard`, `+Account`,
  `+Auth` (register / recover / server-capability probe), `+Members`, `+Share`, `+Versions`,
  `+Export`, `+Import`, `+Fonts`. Around it: `SessionStore`/`Keychain` auth, `PenpotError`,
  `RemoteImageLoader`, `JSONCoding`, `FileOutlineCache` (ETag-revalidated outlines) and
  `BoardPreviewRenderer` (render queue and disk cache; the exporter is its fallback).
- **Models/** — Codable Penpot API models (`Profile`, `Team`, `PenpotFile`, `Board`,
  `CommentThread`, `AccountSettings`, …). `PinMath` for board↔pin geometry.
- **App/** — entry point (`PenpotApp`), `AppState` (auth/session), `AppSettings`.
  Only the `auth-token` cookie goes to the Keychain; server URL, last email and the cached
  profile live in `UserDefaults` (`SessionStore`).
- **Features/** — `Auth`, `Dashboard`, `Viewer`, `Comments`, `Settings` — SwiftUI screens.
  `Viewer` holds the on-device renderer (`PenpotSVG` → `LocalBoardRenderer`), the board
  detail (`BoardDetailView`, `BoardVectorView`), the native page canvas (`PageCanvasView`
  with `CommentPinView`s), the live canvas (`PenpotCanvasView`), the prototype view mode
  (`PenpotViewModeView`) and the file sheets (export, share links, versions, info).
- **Common/** — the design system (below) plus `RemoteImage`, `PenpotAvatar`, `StateViews`,
  `Typography`, `AppIcon`, `FontFileMetadata` (CoreText font sniffing).

## Design system — use these, don't hand-roll

Every screen is built from `Sources/Common`; there is no `List` or `Form` left in the app.

| Component | Use for |
| --- | --- |
| `PenpotCard` / `PenpotCardRow` / `PenpotCardDivider` | grouped rows — the `List` replacement |
| `.penpotField(label:error:)` | every text input |
| `.buttonStyle(.penpot(.primary/.secondary/.ghost/.link/.destructive))` | every button |
| `PenpotMenuPicker` | a dropdown in a card row's trailing slot |
| `PenpotSegmentedPicker` | tab switchers |
| `.penpotSwipeActions(id:)` | swipe-to-delete on a row |
| `.penpotPageBackground()` | screen background |
| `PencilLoaderView` / `PencilLoadingBadge` | loading states |
| `AppIcon` | every icon. No SF Symbols anywhere |
| `PenpotMenuChoices` / `PenpotMenuCheckLabel` | single choices and toggles inside a `Menu` |
| `.toggleStyle(.penpot)` | every `Toggle`: Penpot's 30×18 switch (×1.2), not iOS 26's 63×28 one |

**Icons** come from Penpot's set via `Scripts/fetch-penpot-icons.sh`. Penpot's icons are
Feather icons scaled to 2/3. Icons Penpot lacks are drawn in that style in
`Scripts/penpot-icons-extra/`. A `Picker` or `Toggle` inside a `Menu` would draw Apple's
checkmark, so menus use `PenpotMenuChoices` with Penpot's `tick`. `.searchable`'s glyphs
and the back chevron are swapped via UIKit appearance in `PenpotApp`.

Verified against Penpot's own live CSS and `penpot/penpot@develop`, so change these only
with equal evidence:

- **8px radius everywhere** (`$br-8`) — cards, inputs, buttons, tabs, thumbnails. The one
  exception is the dashboard library badge, which Penpot gives 6px on a 32px square.
- **Inputs have no visible border at rest.** Penpot declares `border: 1px solid
  var(--input-border-color)`, but that token and `--input-background-color` both resolve to
  `--color-background-tertiary`, so it is the fill color. The accent border is the *focus*
  signal, 1px, and the fill does **not** change on focus.
- **Field labels are `--color-foreground-primary`** (pure black/white), 12px uppercase at
  weight 500 — not a muted gray.
- **Links** (`forgot-pass-link` / `register-link` / `demo-account-link` share one rule):
  14px weight 400, `--color-accent-primary`, no fill, no padding, sentence case, underline
  only on hover → mapped to the pressed state on touch.
- Filled buttons uppercase their label at the **display layer** (`.textCase`), never in the
  string catalog — casing rules differ per language.

## SwiftUI traps that already bit us

- **`.swipeActions` is `List`-only** and fails *silently* elsewhere. That is why swiping
  vanished with the `List` removal; `PenpotSwipeActions.swift` restores it as a nested
  horizontal `ScrollView` (UIKit arbitrates perpendicular nested scrolling correctly, so a
  hand-rolled `DragGesture` fighting the vertical scroll is not needed).
- **`.listRowBackground` is also `List`-only** — same silent no-op.
- **A `Section` is not a view**, so no background or border can be drawn behind a whole list
  section. That is the reason `PenpotCard` exists at all.
- **`ButtonStyle.makeBody` cannot read `@Environment(\.isEnabled)`** — an inner `View`
  struct must, or every `.disabled()` call site renders as enabled.
- **`.frame(maxWidth:)` does not make a `Text` re-wrap.** Only a *definite* width is
  proposed down to the text; a max just clips it. `PenpotSwipeActions` uses a fixed width.
- **`Dictionary.values.first` is non-deterministic per launch** — it made file covers appear
  to shuffle. Sort before picking.
- **Mutate `@Observable` UI state on the main actor.** `AppState` wasn't isolated, so
  `bootstrap()` set `phase` from a background executor and the app could hang on the
  splash screen. It is `@MainActor` now; keep new observable state classes that way.

## Penpot API gotchas (bite easily)

- Responses are **camelCase**, request params are **kebab-case** (`file-id`, not `fileId`).
- **`GET` is only allowed for commands starting with `get-`**; anything else must be a POST
  or the server answers **405**. This broke `search-files`.
- `get-profile` is Cloudflare-challenged (403) for the app — validate sessions with
  `get-teams`, recover the profile/avatar via `get-team-members`. Map HTTP 403 to a
  non-fatal error, never to "logged out". A 403 *with* a JSON `code` body is a real server
  error and is surfaced as such; HTML/empty means Cloudflare.
- The **five unauthenticated auth POSTs** (register/recover) are Cloudflare-challenged on
  the SaaS. Link out to the website — never attempt to evade the challenge.
- `/api/export` speaks **transit**, and Penpot registers a *custom* tag: the download URI
  arrives as `{"~#uri": "…"}`, not a plain string.
- Server capabilities have no RPC — probe **`{server}/js/config.js`** and parse
  `penpotFlags` (`PenpotClient+Auth.swift`). `design.penpot.app` ships
  `disable-demo-users`, so the demo-login link is hidden there.
- `get-file` is sent **without** a `features` param on purpose (servers then inline page
  data); pointer pages are still resolved via `get-file-fragment` → `get-page` as a
  robustness fallback. Declaring features is no shortcut: the server then demands every
  team feature.
- **`get-file` is huge for design systems**: Carbon is 217 MB of JSON and 51 s, of which
  the grid needs ~80 KB. So `FileViewerView` shows a cached `FileOutline` at once and
  revalidates with the ETag (`If-None-Match` → 304 in ms; the ETag covers revn, vern and
  permissions). A first open shows `get-page` (first page only, under a second) while the
  whole file loads.
- Board thumbnails: `get-file-object-thumbnails` is keyed by
  `"<file-id>/<page-id>/<frame-id>/frame"`; media served at `/assets/by-id/<id>`.
- **A comment's `frame-id` depends on where it was made.** Penpot's editor takes the
  topmost frame under the click, nested ones included (`get-frame-id-by-position`: a
  table cell); its view mode, and this app, take the root board. The view mode then only
  shows threads of that root board. The board detail also shows threads on frames nested
  in it (`PinMath.thread(_:isOn:pageBoardIDs:)`: a frame that is no root board of the page,
  at a position inside the board); the page canvas shows every thread of the page.
- Team-wide comments can only be listed as **unread** (`get-unread-comment-threads`); the
  documented `team-id` on `get-comment-threads` is ignored.
- The canvas embeds **`#/workspace`** — Penpot's real *editor*, because its read-only state
  is not reachable by URL. `readOnlyGuardJS` swallows every trusted input event; CSS-hiding
  alone does not prevent edits. Only the prototype view mode uses `#/view`, and that one
  needs no guard.
- **Penpot routes by query string since 2.19**: `#/workspace?…` is redirected to
  `/?screen=workspace&…`, `#/auth/login` to `/?screen=auth-login`, and navigation uses
  `pushState` (no `hashchange`). Never read `location.hash` for the route: use
  `PenpotWebView.routeJS` (`__penpotRoute()`, both formats). The input guard keyed on the
  hash went inert and the canvas became editable, so it now fails closed: everything is
  blocked except the `auth-*` screens. The app keeps building `#/…` links because servers
  before 2.19 only understand those.
- **Board thumbnails are made by the web editor, not the server.** `get-file-object-thumbnails`
  is empty for imported/template files until someone opens each page in Penpot's
  *classic* renderer. The WebGL renderer (`render-wasm/v1`) skips thumbnail generation
  entirely (`data/workspace/pages.cljs`), so files only ever opened with it never get any.
- **Boards are rendered on the device** (`LocalBoardRenderer`): `get-page` →
  `PenpotSVG` (an SVG document per board, following Penpot's classic renderer
  `render.cljs`/`ui/shapes/*`) → hidden `WKWebView` → `createPDF`. The PDF feeds the
  board detail and the native page canvas (`BoardVectorView`, a `CATiledLayer` that
  re-tiles under zoom), and a bitmap drawn from it is the preview where Penpot has no
  thumbnail. Text is HTML in a `foreignObject` laid out from the content tree, like the
  editor: the stored `positionData` can be stale (the exporter cuts "Back Toke" from it).
  Fonts: `/fonts/sourcesanspro-*.woff`, Google fonts via `/internal/gfonts/css`, team
  fonts via `get-font-variants` → `/assets/by-id/<woff1FileId>`.
- **WKWebView traps of that renderer**: outside any window WebKit throttles timers and
  font loads (renders stall); a view removed from the window after loading never
  finishes `createPDF`. So the web views sit at the bottom of the window, covered.
  One document for a whole design-system page made `createPDF` take seconds *per board*
  (it paints the whole document), hence one document per board. Two workers, newest
  request first; `createPDF` of a text-heavy board is real work (~0.8 s on a Mac).
- **`createPDF` turns every element with a `filter` or a `mask` into a bitmap** (2× on
  a Mac), children and text included: a card with a drop shadow came out stair-stepped
  under zoom. So shadows are drawn from *copies* of the shape (`shadowed`: drop shadows
  under it, inner shadows over it) and the shape itself carries no filter; an opaque
  board casts its shadow from its outline, so its children aren't laid out twice. Plain
  opaque masks become clip paths. Only layer blur keeps one filter (blurred anyway).
  Shadows **without blur** are paths, no filter at all (`hardShadow`): Penpot's filters
  read a hard alpha, which for a filled, untransformed rect/board/ellipse is its outline
  (`alphaIsOutline`; a fill-less board counts when filled children cover it). Carbon draws
  table rules as 1 px inner shadows, ~350 per board: as filters a 1080×6510 board took
  19 s on a Mac and failed on an iPhone 13 mini; as paths 1.1 s.
- **Background blur** (WebGL-renderer only, `backgroundBlur` on the shape) is CSS
  `backdrop-filter` in Penpot's own SVG export, which WebKit **never** draws into a PDF
  (nor into an offscreen snapshot). So the writer tracks the markup written so far
  (`backdrop`, only on pages that have one) and draws a blurred copy of it, cut to the
  shape, before the shape. Its sigma is render-wasm's `0.57735 × value + 0.5`; layer blur
  keeps the classic renderer's `stdDeviation = value`.
  Raise `BoardPreviewRenderer.Key.renderVersion` when renders change, or the cache keeps
  showing the old ones.
- **Files nobody opened in the editor carry stale geometry.** Imported files (Carbon-v48)
  have texts without `positionData` whose stored sizes are far off (a 54 px headline
  stored 106 px wide), so the flex layouts around them are stale too and texts overlap.
  Penpot's editor re-measures such texts when a page opens, reflows and *saves* (a revn
  bump). So boards with such texts get a layout pass first (`needsLayout`): `layoutProbe`
  mirrors the board as HTML (flex → CSS flexbox, children in *reverse* `shapes` order,
  `stretch` acts as start for items that aren't `fill`), WebKit measures it
  (`layoutScript`), and the writer translates moved shapes and resizes texts and hug
  boards. Only stale texts and the layouts holding them reflow; the rest keeps its stored
  geometry, as in Penpot, where a hug board whose content didn't change keeps its size.
  Root boards keep their size (their document is that rect).
- The exporter (`/api/export`) is only the fallback now. It is scarce: 5 headless
  browsers per instance, 10 s to get one, else a 500 `~:timeout`; a 504 marks the board
  as failed for the session (`BoardPreviewRenderer`, one job at a time).
- The page canvas is native (`PageCanvasView`): boards at their selrect positions in a
  `UIScrollView`, plus **islands**: root shapes outside any board, grouped by proximity
  (`PenpotSVG.islands`) and drawn like boards (id `island-<lowest shape id>` through
  `LocalBoardRenderer`, never the exporter, which only renders boards). Tiles are layered
  in Penpot's paint order (`Page.layers`); a board lying under one shape and over another
  splits their island, so each island is entirely under or over every board it overlaps.
  Island bounds come from stored geometry, so a stale auto-width text outside any board
  can still be clipped. Every page opens natively; the live canvas is a toolbar button.
  The page's comment threads show as pins there too (UIKit-hosted `CommentPinView`s in a
  screen-space layer); a new one goes to the topmost board under the tap, or to
  `Board.rootFrameID` outside every board, as in Penpot. Touch and hold moves a pin; the
  drop point picks its board the same way (`update-comment-thread-position` `frame-id`).
- SaaS pages load a cookie banner from `penpot.app/scripts/cookie-consent.js`
  (`div.CookieConsent_wrapper`). CSS attribute selectors are **case-sensitive**, so
  both WebViews hide it with `[class*='cookie' i]`. Without the `i` the banner stays up.
- Server-version requirements are mostly **author annotations, not runtime gates**: import
  ≥ 1.15, templates ≥ 1.19, @mentions ≥ 2.7 (a 400 is retried once without mentions),
  Recently Deleted ≥ 2.12 / restore ≥ 2.13, versions ≥ 2.4, font upload ≥ 2.17, file info
  (`get-file-stats`) ≥ 2.17, owned-organizations warning ≥ 2.18. Only font upload, version
  history and file info surface an explicit "unsupported" state.
- `get-owned-organizations-summary` returns `[]` unless the server has the `admin-console`
  flag (SaaS does, a devenv doesn't), so the delete-account org list only shows on SaaS.
- A resent upload chunk is rejected as `duplicate-chunk-index` on 2.18 but as
  `chunk-already-exists` on `develop`. Accept both: either means the chunk was stored.
- With the `admin-console` flag (mandatory in a future release), *every* request 503s
  while the Admin Console is unreachable (`{"type":"nitrate-unavailable"}`) or not set up
  (`nitrate-not-configured`). There is no `code`, only a `type`. `PenpotError` shows
  Penpot's own wording for both; session restore already treats 503 as transient.
- **2.19 closes RPC param schemas**: an unknown param is now a 400, not ignored. Only send
  params the method's schema lists (`/api/main/doc`). `create-file`/`-project`/`-team`
  reject a client `id`.
- `export-binfile` takes `type` (`include-libraries` / `merge-libraries` /
  `detach-libraries` / `link-later`) since 2.19. The old `include-libraries` /
  `embed-assets` booleans are deprecated but still in the schema, and pre-2.19 servers only
  read those, so `exportBinfile` sends both. `FileDownloadSheet` mirrors Penpot's dialog:
  shown only when `has-file-libraries` (a POST) is true, and `link-later` only with the
  `export-link-later` flag (off on SaaS).
- 2.19 locks an account after repeated failed logins: a 429 with `code: account-locked`
  and the remaining seconds in `ttl`. `PenpotError` turns it into minutes.

## Canvas WebView traps

- User-script CSS goes in as a **JSON string literal** (`styleInjectionScript`). A JS
  template literal broke on a single backtick in a CSS comment and silently dropped *all*
  injected CSS. `BoardExportTests` evaluates the script in JavaScriptCore.
- Penpot's CSS-module class names carry the file path (`main_ui_workspace_top_toolbar__…`,
  `main_ui_viewer_thumbnails__…`) and change between releases. Match on
  `[class*='…__']` and re-check them against the live CSS after a Penpot update.
- iOS kills the web content process when Penpot's editor outgrows its memory budget
  (WebGL dies within a second on a 4 GB iPhone; heavy pages die without it, in Safari too).
  Without `webViewWebContentProcessDidTerminate` WebKit reloads by itself, which loops.
  `PenpotCanvasView` falls back from WebGL to the classic renderer once, then shows a
  memory error whose retry rebuilds the web view (`webViewID`).

## Localization

All 34 languages of Penpot's `supported-locales` are in `Sources/Localizable.xcstrings`.
`PenpotLanguage.all` maps Penpot codes to catalog codes; the catalog code must equal the
`.lproj` name (`ja`, `nb`, `zh-Hans`), not a region code. Arabic, Hebrew and Persian
switch to right-to-left through `AppSettings.layoutDirection`. Info.plist texts (purpose
strings) are translated separately in `Sources/InfoPlist.xcstrings`.

- **Terminology follows Penpot's own `.po` files** (`penpot/penpot@develop`
  `frontend/translations/`). Where Penpot has the same English text, use its translation.
  German uses formal "Sie", as Penpot does. Strings Penpot doesn't have are AI
  translations with no native review.
- **Never open that file for writing with a truncating write.** A stub script once emptied
  it. Read, mutate, validate, then write.
- Plural strings need hand-added `%lld` keys with `variations.plural` holding each
  language's CLDR categories (e.g. Arabic needs all six). Extraction writes dead `%@`
  twins that the runtime never looks up.


## Build & run

XcodeGen project — the `.xcodeproj` and `Support/Info.plist` are generated artifacts.
After pulling or editing `project.yml`, or after **adding a file**: `xcodegen generate`.
The Simulator needs no signing. For device builds, `DEVELOPMENT_TEAM` comes from the
git-ignored `Support/Signing.local.xcconfig` (included by `Support/Signing.xcconfig`).
The repo is public, so never commit a team ID to `project.yml`.

App Store setup:
- **iPhone only** (`TARGETED_DEVICE_FAMILY: "1"`).
- `ITSAppUsesNonExemptEncryption: false`: the app only uses HTTPS through Apple's APIs.
- `NSAllowsArbitraryLoads` stays for self-hosted http servers. Explain it in the review
  notes.
- `Sources/PrivacyInfo.xcprivacy` declares no tracking, no collected data and one
  required-reason API: `UserDefaults` (CA92.1). Add the reason there when code starts
  using file timestamps, disk space, system uptime or active keyboards, or the upload is
  rejected.
- **No link to Penpot's subscription, billing or pricing pages.** App Review counts a path
  to purchases outside In-App Purchase as steering (3.1.1); the Settings "Subscription"
  row was removed for that.
- `NSPhotoLibraryAddUsageDescription` must stay: a PNG/JPEG board export goes to the share
  sheet, whose "Save Image" writes to Photos, and without the key iOS kills the app. Its
  translations live in `Sources/InfoPlist.xcstrings` (all 34 languages, Penpot's board
  term from `Localizable.xcstrings`). Every new Info.plist purpose string goes there too.

Tests: `xcodebuild test -project PenpotiOS.xcodeproj -scheme PenpotiOS -destination
'platform=iOS Simulator,name=iPhone 17 Pro'` — 171 tests across 15 files, all unit-level
(decoding, geometry, multipart layout, transit parsing, flag parsing, error mapping, the
WebView scripts in JavaScriptCore, the preview renderer's queue, the outline cache and
its 304 path via a URLProtocol stub, the SVG generator, and a WebKit SVG→PDF probe). No UI tests. A test run
relaunches the app on that Simulator.
