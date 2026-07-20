# Penpot iOS — working notes for Claude

A native SwiftUI client for browsing and commenting on Penpot design files.

## Use the knowledge graph first

This repo ships a **graphify knowledge graph** of the Swift source in `graphify-out/`.
Before grepping or reading files to understand architecture, call graphs, or "what uses X",
**query the graph** — it's the fastest, most complete map of how a change ripples:

- Ask: `/graphify query "how does the auth/session flow work?"`
- Trace a path: `/graphify path "LoginView" "PenpotClient"`
- Explain a node: `/graphify explain "PenpotClient"`
- Read the map directly: `graphify-out/GRAPH_REPORT.md` (audit + communities),
  `graphify-out/graph.html` (interactive), `graphify-out/graph.json` (raw, GraphRAG-ready).

Coverage: **51 Swift files → 686 nodes / 1,358 edges / 31 communities** (Swift AST + the
docs). Highest-connected "god nodes": `PenpotClient`, `Profile`, `AppIcon`, `Project`,
`CommentThread`. `Profile` is a notable cross-domain bridge (auth ↔ API ↔ comments ↔ viewer).

## Keep the graph fresh

After changing Swift files, refresh it: **`/graphify . --update`** (incremental; Swift AST
extraction is free, no API key needed). Never hand-edit anything under `graphify-out/`.
The graph is scoped to the Swift source + README + `project.yml`; icon assets and
asset-catalog JSON are deliberately excluded as noise.

## Project shape (from the graph's communities)

- **Networking/** — Penpot RPC client (`PenpotClient` + `+Dashboard`/`+Account` extensions),
  `SessionStore`/`Keychain` auth, `PenpotError`, `RemoteImageLoader`, `JSONCoding`.
- **Models/** — Codable Penpot API models (`Profile`, `Team`, `PenpotFile`, `Board`,
  `CommentThread`, `AccountSettings`, …). `PinMath` for board↔pin geometry.
- **App/** — entry point (`PenpotApp`), `AppState` (auth/session), `AppSettings`.
- **Features/** — `Auth`, `Dashboard`, `Viewer` (board detail + `PenpotCanvasView` WebView
  canvas), `Comments`, `Settings` — SwiftUI screens.
- **Common/** — shared UI (`RemoteImage`, `AppIcon`, `StateViews`, `Typography`, `PenpotAvatar`).

## Build & run

XcodeGen project — the `.xcodeproj` and `Support/Info.plist` are generated artifacts.
After pulling or editing `project.yml`: `xcodegen generate`. The Simulator needs no signing;
device builds use development team `295ZCZVB9H` (set in `project.yml`).

## Penpot API gotchas (bite easily)

- Responses are **camelCase**, request params are **kebab-case** (`file-id`, not `fileId`).
- `get-profile` is Cloudflare-challenged (403) for the app — validate sessions with
  `get-teams`, recover the profile/avatar via `get-team-members`. Map HTTP 403 to a
  non-fatal error, never to "logged out".
- Board thumbnails: `get-file-object-thumbnails` is keyed by
  `"<file-id>/<page-id>/<frame-id>/frame"`; media served at `/assets/by-id/<id>`.
