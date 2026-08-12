# Penpot iOS

A native SwiftUI app to **browse, review and comment on [Penpot](https://penpot.app)
design files from your iPhone**.

It talks to Penpot's RPC HTTP API: it lists your teams, projects and files, shows the
boards as thumbnails rendered by Penpot, embeds Penpot's own web workspace as a read-only
canvas, and lets you read existing comment threads (shown as native pins overlaid on the
board) and post new comments / replies. It's a **viewer + reviewer** — editing designs is
intentionally not supported.

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

- **File viewer**: boards as Penpot-rendered thumbnails, plus an embedded read-only canvas.
  It loads Penpot's real web *workspace* in a `WKWebView` — the editor has no read-only URL
  mode, so an injected guard swallows every input event.
- **Prototype view mode**: play interaction flows full-screen (tap hotspots to navigate
  between boards), straight from a page or a board.
- **Board detail**: zoom/pan the board with comment **pins** overlaid at the right position.
- **Comments**: an unread inbox across teams, read threads with author avatars, reply,
  resolve, delete, and create a brand-new comment by tapping on the board. Filter threads
  (all / only yours / mentions, show resolved) and mention teammates with an
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

- **Export & import**: download a file as `.penpot`, import `.penpot` archives into a
  project, export a single board as **PNG/JPEG/WebP (1x–3x), SVG or PDF** via the share
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
- Localized in English, German, Spanish, French, Portuguese (BR) and Russian; uses Penpot's
  **Work Sans** UI typeface and brand accent colors (purple on light, cyan on dark).

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

In Xcode: select the `PenpotiOS` scheme, set your **Signing Team** under
*Signing & Capabilities* (`project.yml` ships an empty one), then run on a Simulator or
device.

> The generated `PenpotiOS.xcodeproj` and `Support/Info.plist` are build artifacts — run
> `xcodegen generate` after pulling changes, and after adding any file.

## Tests

```bash
xcodebuild test -project PenpotiOS.xcodeproj -scheme PenpotiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

120 unit tests covering response decoding, pin geometry, transit parsing, multipart
layouts, font metadata sniffing, search history and settings. There are no UI tests.

## Manual test checklist

1. Launch, enter server URL (default `https://design.penpot.app`), email, password → log in.
2. Pick a team → a project → a file.
3. Confirm boards render as thumbnails.
4. Open a board, tap an existing comment pin, read the thread, post a reply.
5. Tap an empty spot on the board to create a new comment; verify it appears in the
   Penpot web app at the same position.

## Project layout

```
Sources/
  App/         App entry point + global app state
  Networking/  RPC client (one extension per domain), session/keychain storage, images
  Models/      Codable models for Penpot API responses
  Features/    Auth, Dashboard, Viewer, Comments, Settings (SwiftUI screens)
  Common/      Design system (cards, buttons, fields, pickers, swipe actions) + helpers
  Localizable.xcstrings   399 keys × 6 languages
  Resources/   Bundled Work Sans fonts
  Assets.xcassets/  App icon, launch assets, Penpot icon set
Tests/         11 unit-test files
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
- **Board export** needs the server's exporter service (always present on
  design.penpot.app; optional on self-hosted). Several features also need a recent enough
  Penpot: import ≥ 1.15, templates ≥ 1.19, Recently Deleted ≥ 2.12 (restore and permanent
  delete ≥ 2.13), @mentions ≥ 2.7, version history ≥ 2.4, font upload ≥ 2.17. Only font
  upload and version history show an explicit "unavailable" state; the rest simply degrade
  (a mention is retried without mentions, a missing menu entry stays hidden).
- Board thumbnails are rendered by Penpot's web editor, not the server: freshly imported
  files show placeholders until the file is opened in an editor once (the embedded live
  canvas also does the trick).
- The team-wide comment inbox can only list **unread** threads (API limitation); the full
  thread list is available per file.
- Offline caching is out of scope for now.
