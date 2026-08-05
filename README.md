# Penpot iOS

A native SwiftUI app to **browse, review and comment on [Penpot](https://penpot.app)
design files from your iPhone**.

It talks to Penpot's RPC HTTP API: it lists your teams, projects and files, shows the
boards as thumbnails rendered by Penpot, embeds Penpot's own web viewer as a read-only
canvas, and lets you read existing comment threads (shown as native pins overlaid on the
board) and post new comments / replies. It's a **viewer + reviewer** — editing designs is
intentionally not supported.

## Features

- **Login** against any Penpot instance (cloud `design.penpot.app` or a configurable
  self-hosted server URL), with quick server presets and a one-tap **demo account**. The
  session is persisted in the Keychain.
- **Appearance** (light / dark / system) and **app language** are selectable right on the
  login screen and in Settings, applied instantly without a relaunch.
- Browse **Teams → Projects → Files**, Drafts, pinned projects, shared **Libraries** and
  **Fonts**; create, rename, duplicate, move and delete, with a **Recently Deleted**
  recovery area.
- **File viewer**: boards as Penpot-rendered thumbnails, plus an embedded read-only canvas
  (Penpot's web viewer in a `WKWebView`).
- **Board detail**: zoom/pan the board with comment **pins** overlaid at the right position.
- **Comments**: an unread inbox across teams, read threads with author avatars, reply,
  resolve, delete, and create a brand-new comment by tapping on the board.
- **Profile & account**: edit name/avatar, account language, change email, notification
  settings, and account deletion.
- **Export** a file as `.penpot`, and publish / unpublish a file as a shared library.
- Localized in English, German, Spanish, French, Portuguese (BR) and Russian; uses Penpot's
  **Work Sans** UI typeface and brand accent colors (purple on light, green on dark).

## Requirements

- macOS with **Xcode 15+** (iOS 17 SDK).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from
  `project.yml`.

## Build & run

```bash
brew install xcodegen        # once
xcodegen generate            # creates PenpotiOS.xcodeproj
open PenpotiOS.xcodeproj
```

In Xcode: select the `PenpotiOS` scheme, set your **Signing Team** under
*Signing & Capabilities*, then run on a Simulator or device.

> The generated `PenpotiOS.xcodeproj` and `Support/Info.plist` are build artifacts — run
> `xcodegen generate` after pulling changes.

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
  Networking/  RPC client, session/keychain storage, image loading
  Models/      Codable models for Penpot API responses
  Features/    Auth, Dashboard, Viewer, Comments, Settings (SwiftUI screens)
  Common/      Shared UI helpers (remote image, loading/error states, brand colors, typography)
Tests/         Decoding + pin-geometry unit tests
project.yml    XcodeGen project definition
```

## Notes / limitations

- The app is **view + comment only** — the embedded canvas is read-only and editing designs
  is not supported.
- Auth uses Penpot's `login-with-password` and the resulting `auth-token` session cookie.
  `get-profile` sits behind a Cloudflare challenge for non-browser clients, so sessions are
  validated via `get-teams` and the profile/avatar recovered from team membership.
- Very large files that store page data as fragments may not expose all boards yet
  (fragment dereferencing is a planned follow-up).
- Offline caching is out of scope for now.
