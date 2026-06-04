# Penpot iOS

A native SwiftUI app to **browse and comment on [Penpot](https://penpot.app) design
files from your iPhone/iPad** — think "Figma for mobile", but for Penpot.

It talks to Penpot's RPC HTTP API: it lists your teams, projects and files, shows the
boards as PNG thumbnails rendered by Penpot, and lets you read existing comment threads
(shown as native pins overlaid on the board) and post new comments / replies.

## Features (MVP)

- Email + password login against any Penpot instance (cloud `design.penpot.app` or a
  configurable self-hosted server URL). The session is persisted in the Keychain.
- Browse **Teams → Projects → Files**.
- **File viewer**: boards displayed as Penpot-rendered thumbnails in a grid.
- **Board detail**: zoom/pan the board image with comment **pins** overlaid at the right
  position.
- **Comments**: open a thread, read all comments with author names, reply, resolve, and
  create a brand-new comment by tapping on the board.

## Requirements

- macOS with **Xcode 15+** (iOS 17 SDK).
- [XcodeGen](https://github.com/yonwoo9/XcodeGen) to generate the Xcode project from
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
  Features/    Auth, Dashboard, Viewer, Comments (SwiftUI screens)
  Common/      Shared UI helpers (remote image, loading/error states)
Tests/         Decoding + pin-geometry unit tests
project.yml    XcodeGen project definition
```

## Notes / limitations

- Auth uses Penpot's `login-with-password` and the resulting `auth-token` session cookie.
- Very large files that store page data as fragments may not expose all boards yet
  (fragment dereferencing is a planned follow-up).
- App icon / asset catalog and offline caching are intentionally out of scope for the MVP.
