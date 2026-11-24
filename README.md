# Viewer for Penpot

A native SwiftUI app to **browse, review and comment on [Penpot](https://penpot.app)
design files from your iPhone**.

It talks to Penpot's RPC HTTP API: it lists your teams, projects and files, **draws the
boards itself as vector graphics** (sharp at any zoom, no server thumbnails needed), shows
whole pages on a native zoomable canvas, and lets you read, write and move comments right
where they belong. Penpot's own web workspace is still one tap away as a read-only live
canvas. It's a **viewer + reviewer** — editing designs is intentionally not supported.

Works with `design.penpot.app` and self-hosted Penpot, up to the current 2.19.

**Unofficial.** This app is not made by or affiliated with Kaleidos, the company behind
Penpot. "Penpot" and its logo are their trademarks, so the app is called *Viewer for
Penpot* ("Viewer" on the home screen) and has its own icon: an eye drawn as a vector path.

## Features

### Accounts & access

- **Login** against any Penpot instance (cloud `design.penpot.app` or a configurable
  self-hosted server URL), with quick server presets. The `auth-token` cookie is kept in
  the Keychain; the server URL, last email and cached profile live in `UserDefaults`.
- **Sign up and password recovery** in-app, including pasting the link from the
  verification / reset email. Both adapt to the server: the app probes `js/config.js` and
  hides what the instance has switched off (registration, terms checkbox, newsletter).
- **Demo login** on servers that enable Penpot's `demo-users` flag. It is hidden on
  `design.penpot.app`, which ships `disable-demo-users`.

### Browsing

- **Teams → Projects → Files**, Drafts, pinned projects, shared **Libraries** and
  **Fonts**; create, rename, duplicate, move and delete, with a **Recently Deleted**
  recovery area and item counts throughout the team dashboard.
- **Recently edited** files surfaced on the team dashboard, newest first.
- **File search** per team on its own screen, with recent-search history and filters
  (by project, shared libraries only).
- **Swipe a row** to delete, restore, remove or resend — everything is also reachable from
  the row's long-press menu.

### Reviewing

- **Boards rendered on the device**: the app turns each board's page data into SVG and lets
  WebKit draw it into a vector PDF, following Penpot's own renderer: fills, gradients,
  strokes, shadows, layer and background blur, masks, imported SVG and text in the file's
  fonts. Renders are cached per file revision, so a file opens instantly the second time.
  Penpot's exporter is only the fallback.
- **Even stale and huge files**: a design system like IBM Carbon (217 MB of file data) opens
  from a cached outline while it revalidates. Files imported without ever being opened in
  Penpot's editor carry outdated text sizes; the app lays such boards out again (flex
  layout and real text measurement), as the editor would.
- **Board detail**: the board as a vector PDF — zoom in and text stays sharp — with comment
  **pins** overlaid at the right position. Touch and hold a pin to move it.
- **Page canvas**: a whole page natively, boards at their real positions, plus the shapes
  that lie outside any board, layered in Penpot's paint order. Comment pins live there too:
  open a thread, drop a new comment anywhere (it goes to the board under your finger), move
  a pin, or jump to a thread from the page's thread list.
- **Live canvas**: Penpot's real web *workspace* in a `WKWebView`, read-only — the editor has
  no read-only URL mode, so an injected guard swallows every input event.
- **Prototype view mode**: play interaction flows full-screen (tap hotspots to navigate
  between boards), straight from a page or a board.
- **Comments**: an unread inbox across teams, read threads with author avatars, reply,
  resolve, delete, and create a brand-new comment by tapping on the board or the canvas.
  Filter threads (all / only yours / mentions, show resolved) and mention teammates with an
  **@-autocomplete** composer.

### Collaborating

- **Team members & invitations**: roster with roles, invite by email, change roles,
  transfer ownership, remove members and leave a team. Admins and owners can also change
  the team photo.
- **Share links**: create, copy and revoke public view links for a file, with the web
  dialog's comment/inspect audience options.
- **Version history**: named versions and day-grouped autosaves — save, rename, pin,
  restore (with Penpot's automatic safety backup) and delete.

### Assets

- **Export & import**: download a file as `.penpot` (with Penpot's library options when the
  file uses shared libraries), import `.penpot` archives into a project, export a single board as **PNG/JPEG/WebP (1x–3x), SVG or PDF** via the share
  sheet, and publish / unpublish a file as a shared library.
- **Font management**: upload `.ttf`/`.otf`/`.woff`/`.woff2` (family, weight and style are
  read from the file itself, chunked upload for large files), rename a family, and download
  a family as a ZIP.

### Look & feel

- Rebuilt in **Penpot's own design language**, verified against its live stylesheet:
  8px corner radius throughout, tonal cards on a flat page, Penpot's button and input
  styles, and its animated pencil loader for loading states.
- **Appearance** (light / dark / system) and **app language** are selectable right on the
  login screen and in Settings, applied instantly without a relaunch.
- **Profile & account**: edit name/avatar, account language, change email, notification
  settings, and account deletion.
- Localized in all 34 languages Penpot itself ships (right-to-left included), using
  Penpot's own terminology from its translation files; uses Penpot's **Work Sans** UI
  typeface, its icon set (no SF Symbols) and brand accent colors (purple on light, cyan
  on dark).

## Requirements

- macOS with **Xcode 15+** (iOS 17 SDK). The app targets **iOS 17**.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from
  `project.yml`.

## Build & run

```bash
brew install xcodegen        # once
xcodegen generate            # creates PenpotiOS.xcodeproj
open PenpotiOS.xcodeproj
```

In Xcode: select the `PenpotiOS` scheme, then run on a Simulator (no signing needed) or a
device. For a device, put your team in a git-ignored `Support/Signing.local.xcconfig`
(`DEVELOPMENT_TEAM = ABCDE12345`). Unlike a team picked under *Signing & Capabilities*,
it survives `xcodegen generate`.

> The generated `PenpotiOS.xcodeproj` and `Support/Info.plist` are build artifacts — run
> `xcodegen generate` after pulling changes, and after adding any file.

## Tests

```bash
xcodebuild test -project PenpotiOS.xcodeproj -scheme PenpotiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

181 unit tests across 16 files: response decoding, pin geometry, transit parsing, multipart
layouts, font metadata sniffing, search history and settings, the WebView scripts (run in
JavaScriptCore), the file-outline cache, the SVG generator, and WebKit probes that turn SVG
into PDF and lay out a flex row. There are no UI tests.

## Manual test checklist

1. Launch, enter server URL (default `https://design.penpot.app`), email, password → log in.
2. Pick a team → a project → a file.
3. Confirm the boards appear (drawn on the device; a pencil loader shows while one renders).
4. Open a board, zoom in: text stays sharp. Tap an existing comment pin, read the thread,
   post a reply.
5. Tap an empty spot on the board to create a new comment; verify it appears in the
   Penpot web app at the same position.
6. Open a page's canvas (the expand button in its header): zoom, pan, see shapes outside
   boards and the page's comment pins.

## Project layout

```
Sources/
  App/         App entry point + global app state
  Networking/  RPC client (one extension per domain), session/keychain storage, images
  Models/      Codable models for Penpot API responses
  Features/    Auth, Dashboard, Viewer, Comments, Settings (SwiftUI screens)
  Common/      Design system (cards, buttons, fields, pickers, swipe actions) + helpers
  Localizable.xcstrings   ~450 keys × 34 languages
  Resources/   Bundled Work Sans fonts
  Assets.xcassets/  App icon, launch assets, Penpot icon set
Tests/         15 unit-test files
project.yml    XcodeGen project definition
graphify-out/  Generated knowledge graph of the source (see CLAUDE.md)
```

## Notes / limitations

- **Designs cannot be edited.** The embedded canvas is deliberately read-only, and there is
  no drawing or shape editing anywhere. Everything *around* the design is fair game though —
  files, projects, teams, members, fonts, versions, share links and imports can all be
  changed from the app.
- Auth uses Penpot's `login-with-password` and the resulting `auth-token` session cookie.
  `get-profile` sits behind a Cloudflare challenge for non-browser clients, so sessions are
  validated via `get-teams` and the profile/avatar recovered from team membership.
- On `design.penpot.app`, **sign-up and password recovery are also Cloudflare-challenged**.
  The app detects this and links out to the website rather than working around the
  challenge.
- **Board export** to PNG/JPEG/WebP/SVG/PDF needs the server's exporter service (always
  present on design.penpot.app; optional on self-hosted). Viewing boards does not: the app
  draws them itself. Several features also need a recent enough
  Penpot: import ≥ 1.15, templates ≥ 1.19, Recently Deleted ≥ 2.12 (restore and permanent
  delete ≥ 2.13), @mentions ≥ 2.7, version history ≥ 2.4, font upload ≥ 2.17. Only font
  upload and version history show an explicit "unavailable" state; the rest simply degrade
  (a mention is retried without mentions, a missing menu entry stays hidden).
- The on-device renderer follows Penpot's classic renderer. Not covered yet: stroke end
  markers (arrows) and per-run text gradients. Groups and rotated shapes inside a layout that
  the app lays out again keep their stored size.
- The team-wide comment inbox can only list **unread** threads (API limitation); the full
  thread list is available per file.
- Rendered boards and file outlines are cached on disk; everything else needs a connection.
