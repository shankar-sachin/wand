# Wand 1.0.0

First release. A Samsung TV remote for iPhone, in Liquid Glass.

## The remote

The face follows Samsung's physical Smart Remote — power and mic, the number and colour
keys, the large navigation ring with OK at its centre, back/home/play-pause, and the
volume and channel rockers with mute and guide on their centre presses. It's drawn as one
continuous piece of glass in a single `GlassEffectContainer`, so adjacent keys refract
together rather than reading as separate blobs.

The whole wand scales to fit the screen and never scrolls; it's a physical object, so it
doesn't rearrange itself between devices.

Light and dark are both designed, not derived. Each gets its own ambient backdrop so the
glass has something to bend.

## Multiple TVs

Save every TV in the house. The pill at the top shows the current one with a live status
dot; tap it for the list, or swipe it to cycle. Switching is instantaneous because the app
keeps the nearest three TVs connected in the background — the socket you're switching *to*
is already open.

## Apps

Four app keys along the bottom, defaulting to YouTube, Netflix, Prime Video and Disney+,
with real vector logos and dark-mode artwork so the navy marks stay legible on dark glass.
Reorder them or swap in others from the All Apps page, which shows only what the TV
reports as actually installed.

## Also

- **Wake-on-LAN.** A sleeping Samsung refuses WebSocket connections outright, so the power
  key sends a magic packet before trying to connect.
- **Swipe pad.** Flicks become direction keys — faster than tapping arrows through a grid.
- **Keyboard.** Types into TV search fields over `SendInputString` instead of pecking at
  the on-screen keyboard.
- **Diagnostics.** Settings reports median and p95 press-to-send latency.

## Built for latency

- Keys act on touch-**down**, not touch-up.
- `send` is nonisolated and synchronous — a press costs a queue push, with no `Task`
  allocation and no reordering.
- Connections open at launch, are held with pings, and survive 30 seconds of backgrounding
  so app-switching doesn't cost a reconnect.
- Presses during a reconnect are buffered and flushed in order rather than dropped.
- Haptic generators are pre-warmed; a cold one costs tens of milliseconds on first fire.

## Verified against

A Samsung UN65MU6070 (2017, Tizen 2.0.25) — discovery, token pairing, token reuse across
reconnects, key delivery, app install probing, and Wake-on-LAN. Plus 27 unit tests and a
bundled mock TV (`tools/MockSamsungTV.swift`) covering the flows offline.

## Known limits

- Samsung Tizen 2016 and newer only. Older sets use a different port-55000 protocol.
- Wake-on-LAN needs *Power On with Mobile* enabled on the TV, and the set can take ~20
  seconds to accept a socket after waking.
- If the TV was previously denied, clear the app from
  *Settings › General › External Device Manager › Device Connection Manager › Device List*
  before pairing again.
