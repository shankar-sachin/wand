# CLAUDE.md

Guidance for Claude Code (and other AI agents) working in this repository.

## What this is

**Wand** — an iOS 26 Liquid Glass remote for Samsung Tizen TVs (2016 and newer). One
screen: a remote shaped like Samsung's physical Smart Remote, with a quick switcher for
multiple saved TVs.

## Build & run

XcodeGen project. `project.yml` is the source of truth; the `.xcodeproj` is generated and
git-ignored.

```bash
xcodegen generate
xcodebuild -project Wand.xcodeproj -scheme Wand -sdk iphonesimulator build
xcodebuild -project Wand.xcodeproj -scheme Wand -sdk iphonesimulator test
```

- **Always edit `project.yml`** for targets, build settings, or Info.plist keys — never the
  generated `.xcodeproj`.
- Toolchain: Xcode 26, Swift 6 strict concurrency, iOS 26 deployment target.

## Architecture

- **SwiftUI + `@Observable`.** No `ObservableObject`; state is read narrowly so a
  connection change doesn't invalidate the whole remote.
- **`SamsungSession` (`Drivers/Samsung/`)** is an actor owning one `URLSessionWebSocketTask`
  per TV. Its `send(_:)` is `nonisolated` and synchronous on purpose — see below.
- **`ConnectionManager` (`Services/`)** is the `@MainActor` façade: a pool of up to three
  live sessions, scene-phase and `NWPathMonitor` handling, and the key-press entry points.
- **`TVDriver`** is a protocol seam for adding brands. Everything Samsung-specific lives
  under `Drivers/Samsung/`.

## The latency rules

These are the point of the app; don't regress them.

1. **Never make the press path `async`.** `ConnectionManager.press` → `SamsungSession.send`
   → `AsyncStream.Continuation.yield` must stay synchronous and non-isolated. Wrapping a
   press in `Task { await … }` adds scheduling jitter and can reorder keys.
2. **Keys act on touch-down.** Use `KeyPressBehaviour` (`DesignSystem/GlassControls.swift`),
   not `Button`, for anything that sends a command.
3. **Never gate a view's appearance on connection state.** A key must animate identically
   with the socket down.
4. **Warm the haptic generators.** `Haptics.shared` is prepared at launch and re-prepared
   after each fire.

## Liquid Glass gotchas

- Content must be **inside** the view that carries `.glassEffect`, not stacked over it. A
  `GlassEffectContainer` hoists glass into a shared compositing layer that draws above
  ordinary siblings, so anything layered on top of a glass shape vanishes.
- A bare `Circle()` or `Rectangle()` renders **filled** with the foreground colour. Use
  `Color.clear` when you only want the glass.
- `NavigationStack` and `Form` paint opaque backgrounds; put `Theme.Backdrop()` *inside*
  them, and use `.scrollContentBackground(.hidden)` for lists.
- The remote never scrolls. `RemoteView` measures its own content with `onGeometryChange`
  and scales to fit — don't pin it to a fixed design height.

## Samsung protocol gotchas

- The `name` query parameter is base64 **with padding stripped**. A raw `==` makes the TV
  accept the socket and then never respond. This fails silently.
- `wss://` on 8002 only; `ws://` on 8001 opens and is dropped on this generation.
- `/api/v2/` answers in standby but `/api/v2/applications/…` hangs — treat a timeout there
  as "TV asleep", not "app absent".
- App IDs vary by TV year; `TVApp.candidateIDs` is ordered newest-first and probed via
  `SamsungREST.resolveAppID`.
- Wake-on-LAN needs *Settings › General › Network › Expert Settings › Power On with Mobile*
  enabled on the TV, and the set can take ~20s to accept a socket after waking.

## Testing

`tools/MockSamsungTV.swift` stands in for a TV (`--deny`, `--silent`, `--delay` reproduce
the failure modes). Add `127.0.0.1` in the app; loopback deliberately uses plain `ws://`.

Unit tests cover the wire format, subnet enumeration, Wake-on-LAN packet bytes, and the app
catalog. They are pure and need no network.

## App icon

Master artwork lives in `assets/logo.png`. Install it with:

```bash
./scripts/install_icon.sh
```

That resizes to 1024x1024 and strips the alpha channel — iOS rejects or blackens icons
that carry one. The installed file is
`Wand/Resources/Assets.xcassets/AppIcon.appiconset/wand.png`.

## Device builds

`DEVELOPMENT_TEAM` belongs in `Config/Local.xcconfig`, which `project.yml` references via
`configFiles`. Setting it through Xcode's Signing UI instead does not survive the next
`xcodegen generate`, since the project is rewritten from `project.yml`.

The app needs the **Local Network** permission on device (declared as
`NSLocalNetworkUsageDescription`). The Simulator does not enforce local-network privacy,
so a bug here is invisible until you run on hardware.
