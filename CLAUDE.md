# Penpot iOS — working notes for Claude

A native SwiftUI client for browsing, reviewing and commenting on Penpot design files.

## Use the knowledge graph first

This repo ships a **graphify knowledge graph** of the Swift source in `graphify-out/`.
Before grepping or reading files to understand architecture, call graphs, or "what uses X",
**query the graph** — it's the fastest, most complete map of how a change ripples:

- Ask: `/graphify query "how does the auth/session flow work?"`
- Trace a path: `/graphify path "LoginView" "PenpotClient"`
- Explain a node: `/graphify explain "PenpotClient"`
- Read the map directly: `graphify-out/GRAPH_REPORT.md` (audit + communities),
  `graphify-out/graph.html` (interactive), `graphify-out/graph.json` (raw, GraphRAG-ready).

Coverage: **92 Swift files → 1,444 nodes / 3,224 edges / 73 communities** (Swift AST + the
docs). Highest-connected app-owned nodes: `AppIcon`, `PenpotClient`, `FileListItem`,
`PenpotError`, `Project`, `CommentThread`. `Models.swift` is the cross-domain bridge —
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
  `RemoteImageLoader`, `JSONCoding`.
- **Models/** — Codable Penpot API models (`Profile`, `Team`, `PenpotFile`, `Board`,
  `CommentThread`, `AccountSettings`, …). `PinMath` for board↔pin geometry.
- **App/** — entry point (`PenpotApp`), `AppState` (auth/session), `AppSettings`.
  Only the `auth-token` cookie goes to the Keychain; server URL, last email and the cached
  profile live in `UserDefaults` (`SessionStore`).
- **Features/** — `Auth`, `Dashboard`, `Viewer` (board detail + `PenpotCanvasView` WebView
  canvas), `Comments`, `Settings` — SwiftUI screens.
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
  robustness fallback.
- Board thumbnails: `get-file-object-thumbnails` is keyed by
  `"<file-id>/<page-id>/<frame-id>/frame"`; media served at `/assets/by-id/<id>`.
- Team-wide comments can only be listed as **unread** (`get-unread-comment-threads`); the
  documented `team-id` on `get-comment-threads` is ignored.
- The canvas embeds **`#/workspace`** — Penpot's real *editor*, because its read-only state
  is not reachable by URL. `readOnlyGuardJS` swallows every trusted input event; CSS-hiding
  alone does not prevent edits. Only the prototype view mode uses `#/view`, and that one
  needs no guard.
- Server-version requirements are mostly **author annotations, not runtime gates**: import
  ≥ 1.15, templates ≥ 1.19, @mentions ≥ 2.7 (a 400 is retried once without mentions),
  Recently Deleted ≥ 2.12 / restore ≥ 2.13, versions ≥ 2.4, font upload ≥ 2.17, file info
  (`get-file-stats`) ≥ 2.17, owned-organizations warning ≥ 2.18. Only font upload, version
  history and file info surface an explicit "unsupported" state.
- `get-owned-organizations-summary` returns `[]` unless the server has the `admin-console`
  flag (SaaS does, a devenv doesn't), so the delete-account org list only shows on SaaS.
- A resent upload chunk is rejected as `duplicate-chunk-index` on 2.18 but as
  `chunk-already-exists` on `develop`. Accept both: either means the chunk was stored.

## Localization

All 34 languages of Penpot's `supported-locales` are in `Sources/Localizable.xcstrings`.
`PenpotLanguage.all` maps Penpot codes to catalog codes; the catalog code must equal the
`.lproj` name (`ja`, `nb`, `zh-Hans`), not a region code. Arabic, Hebrew and Persian
switch to right-to-left through `AppSettings.layoutDirection`.

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

Tests: `xcodebuild test -project PenpotiOS.xcodeproj -scheme PenpotiOS -destination
'platform=iOS Simulator,name=iPhone 17 Pro'` — 126 tests across 11 files, all unit-level
(decoding, geometry, multipart layout, transit parsing, flag parsing). No UI tests.
