# Penpot Android — working notes for Claude

Native Android counterpart of the iOS app in this repo: Kotlin + Jetpack Compose +
Material 3, feature-for-feature with `Sources/` (login incl. demo account, dashboard,
file viewer, board detail with native comment pins, WebView canvas, comments, settings).

## Layout

- **`core/`** — pure Kotlin/JVM (`kotlin("jvm")`): `PenpotClient` (+ Dashboard/Account
  extension files, ~50 RPC commands), `SessionCookieJar`/`AuthCookie`, all API models,
  board extraction, `PinMath`, SSE parsing. **All unit tests live here** and run
  without an Android SDK.
- **`app/`** — Compose UI: `app/` (AppState/AppSettings/SessionStore), `nav/`,
  `ui/theme/`, `common/`, `features/{auth,dashboard,viewer,comments,settings}`.
  `assets/canvas/` holds the four scripts injected into the canvas WebView
  (shared with iOS nearly verbatim — keep them in sync with `PenpotCanvasView.swift`).

## Build & test

```sh
cd android
./gradlew -Ppenpot.coreOnly=true :core:test   # JVM test suite, no Android SDK needed
./gradlew :app:assembleDebug                  # full build (needs Android SDK + Google Maven)
```

`-Ppenpot.coreOnly=true` skips the `:app` module entirely (see `settings.gradle.kts`) —
use it in sandboxes without access to `dl.google.com`.

## Invariants (mirror the iOS client — see also the root CLAUDE.md)

- Request params **kebab-case**, responses **camelCase**; `PenpotJson` must never get a
  naming strategy (UUID-keyed maps must survive verbatim).
- **401 = logout; 403 = Cloudflare, never logout.** `get-profile` is blocked → validate
  sessions with `get-teams`, recover profile/avatar via `get-team-members` (lowercased
  email match) — the logic lives in `AppState`.
- Cookie `Secure` flag only for https servers (plain-http dev servers otherwise lose
  the session silently; regression-tested in `AuthCookieTest`).
- Empty 200 bodies decode as JSON `null`.
- `update-profile` is a set-write: always send fullname+lang+theme together; the last
  written `lang` is cached in `AppSettings.accountLanguage`. Theme is device-local and
  never synced to the account.
- Board thumbnails re-key `"<file>/<page>/<frame>/frame"` → frame id; media loads via
  `/assets/by-id/<id>` and must go through the shared OkHttp client (cookie auth) —
  Coil is wired to it in `AppGraph`.

## Localization

`values*/strings.xml` are **generated** from `Sources/Localizable.xcstrings` by
`tools/xcstrings_to_android.py` (name map in `tools/string-keys.md`). Never edit the
generated XML — edit the String Catalog and re-run the script.
