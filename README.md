# Wand

A Samsung TV remote for iPhone, in Liquid Glass. Built for iOS 26.

The remote keeps the shape of Samsung's Smart Remote — the big navigation ring, the
volume and channel rockers, the four app keys — rendered as one continuous piece of glass
that refracts the backdrop behind it. Light and dark are both first-class.

Save every TV in the house and switch between them from the pill at the top; the app keeps
the nearest few connected in the background, so switching costs nothing.

## Build

XcodeGen project — `project.yml` is the source of truth, the `.xcodeproj` is generated and
git-ignored.

```bash
xcodegen generate
xcodebuild -project Wand.xcodeproj -scheme Wand -sdk iphonesimulator build
xcodebuild -project Wand.xcodeproj -scheme Wand -sdk iphonesimulator test
```

Requires Xcode 26 / iOS 26 SDK.

## Running on an iPhone

1. **Add your Apple ID** — Xcode › Settings › Accounts › **+** › Apple ID. A free account
   is enough; no paid membership needed.
2. **Put your Team ID in `Config/Local.xcconfig`**:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```
   Find it in Xcode › Settings › Accounts › Manage Certificates, or on
   developer.apple.com/account under Membership. It goes in that file rather than through
   Xcode's Signing UI because `xcodegen generate` rewrites the project from `project.yml`
   and would wipe a UI-set team.
3. **Regenerate and open**: `xcodegen generate && open Wand.xcodeproj`
4. Plug the iPhone in, pick it from the device menu, press **⌘R**.
5. **On the iPhone**, first launch only: Settings › General › VPN & Device Management ›
   trust your developer certificate.
6. **Allow "Local Network"** when the app asks. Wand cannot find or control any TV without
   it — the whole app talks directly to the TV over your Wi-Fi. If you dismissed it,
   re-enable under Settings › Wand › Local Network.

Both the phone and the TV must be on the same Wi-Fi. A free Apple ID's build stops
launching after 7 days; re-running from Xcode renews it.

## What it does

- **Finds TVs by sweeping the subnet.** SSDP needs a multicast entitlement Apple grants by
  application, so Wand probes `http://<host>:8001/api/v2/` instead. That single response
  carries the TV's name, model, stable id, and MAC — everything needed to save it.
- **Pairs and remembers.** The TV shows an "Allow?" prompt on first connection and returns
  a token, which is stored in the Keychain.
- **Wakes a sleeping TV.** A powered-down Samsung refuses WebSocket connections entirely,
  so the power key sends a Wake-on-LAN magic packet before trying to connect.
- **Launches apps that are actually installed.** Samsung removed the WebSocket
  installed-app call on 2020+ firmware, so Wand probes each candidate app ID over REST and
  shows only what the TV confirms.
- **Types into TV search fields** over `SendInputString`, and offers a swipe pad that
  translates flicks into direction keys.

## Why it feels instant

Latency was the design constraint, not a later optimisation.

- **Keys fire on touch-down, not touch-up.** `Button` acts when the finger lifts, which on
  a remote reads as however long you rested on the key. `KeyPressBehaviour` drives from raw
  touch events instead.
- **`send` never awaits.** It is `nonisolated` and does nothing but push onto an
  `AsyncStream`, so a press costs a queue push on the main thread — no actor hop, no `Task`
  allocation, and key order is preserved.
- **The socket is open before you press.** Connections start at launch, not when a view
  appears, and are kept alive with pings and rebuilt with backoff. Backgrounding holds them
  for 30 seconds so app-switching doesn't cost a reconnect.
- **Presses during a blip aren't lost.** The stream buffers the most recent 32 commands and
  flushes them the instant the socket returns.
- **Switching TVs is free** because the target socket is already open — the pool keeps the
  nearest three connected.
- **Haptics are pre-warmed.** A cold `UIFeedbackGenerator` costs tens of milliseconds on
  first fire.

Settings › Diagnostics reports median and p95 press-to-send, so this is measurable rather
than asserted.

## Protocol notes

Learned the hard way against a UN65MU6070 (2017, Tizen 2.0.25):

| Detail | Finding |
| --- | --- |
| Transport | `wss://<host>:8002/api/v2/channels/samsung.remote.control`. Plain `ws://` on 8001 opens and is dropped immediately. |
| `name` parameter | Base64 of the client name **with padding stripped**. A raw `==` makes the TV accept the socket and then never send `ms.channel.connect` — it fails silently, not loudly. |
| Certificate | Self-signed `SmartViewSDK` root, TLS 1.2. Accepted via `URLSessionDelegate`, scoped to the TV's own host. No third-party WebSocket library needed. |
| Token | Arrives in the `ms.channel.connect` payload. A token the TV has revoked causes the socket to open and die within ~2s, which Wand treats as "re-pair". |
| Standby | `/api/v2/` answers from the standby chip, but `/api/v2/applications/…` hangs. So a timeout there means "asleep", not "not installed". |
| App IDs | Changed around 2020 and several apps carry more than one. Candidates are probed newest-first. |

## Testing without a TV

`tools/MockSamsungTV.swift` is a dependency-free stand-in that speaks the same REST and
WebSocket protocol:

```bash
swift tools/MockSamsungTV.swift          # --deny, --silent, --delay <s> for failure modes
```

Then add `127.0.0.1` in the app's "Add by IP address" field. Wand uses plain `ws://` for
loopback so the mock needs no certificate.

## Layout

```
Wand/
  DesignSystem/   Theme, Haptics, and the glass key/ring/rocker primitives
  Models/         TVDevice, RemoteKey, TVApp catalog
  Drivers/        TVDriver seam; Samsung session actor, REST client, trust delegate
  Services/       ConnectionManager (warm socket pool), discovery, Wake-on-LAN,
                  Keychain tokens, device store, app resolver
  Features/       Remote, Apps, Devices, Settings
```

The `TVDriver` seam exists so another brand can be added without disturbing the UI.
