# Architecture

```
iPhone                                              Mac
┌────────────────────────────┐   TLS-PSK over TCP   ┌──────────────────────────┐
│ TouchSurfaceView           │   (Bonjour: _glide._ │ GlideServer (listener)   │
│  → TrackpadPipeline        │        tcp)          │  → StreamDecoder         │
│     GestureEngine          │ ───────────────────► │  → InputInjector         │
│     PointerAcceleration    │   length-prefixed    │     CGEvent mouse/scroll │
│  → Haptics                 │   binary messages    │     momentum, shortcuts  │
│  → GlideClient             │                      │ Menu-bar / window UI     │
└────────────────────────────┘                      └──────────────────────────┘
```

## Modules

- **GlideCore** (pure Swift, no Apple-only imports, fully unit-tested)
  - `InputEvent`, `Wire`, `StreamDecoder`: events and their binary encoding
  - `GestureEngine`: finger snapshots in, trackpad behaviour out (pointing, tap, right click, tap-and-drag, scroll, three-finger swipes)
  - `PointerAcceleration`: velocity-based gain with sub-pixel carry
  - `ScrollMomentum`, `VelocityTracker`: inertial scrolling
  - `TrackpadPipeline`: glue used by the phone
- **GlideNet** (Apple platforms): `GlideService` (TLS-PSK parameters), `GlideServer`, `GlideClient`, `GlideBrowser`
- **iOS/Glide**: multitouch surface, Core Haptics, connect UI, tuning sheet, landscape lock
- **Mac/GlideMac**: CGEvent input injection, momentum timer, menu-bar app and PIN window

## Wire protocol

Each message: `[len u8][type u8][payload]`, little-endian, where `len` counts `type + payload`.

| Type | Value | Payload |
|---|---|---|
| move | 1 | `dx i16`, `dy i16` (whole Mac points, already accelerated) |
| button | 2 | `button u8` (0 left, 1 right), `down u8` |
| scroll | 3 | `phase u8` (0 began, 1 changed, 2 ended), `dx f32`, `dy f32` |
| action | 4 | `action u8` (0 Mission Control, 1 App Exposé, 2 Space left, 3 Space right) |

For scroll `ended`, `dx`/`dy` carry the release velocity in points/second and drive momentum on the Mac. Unknown types are skipped.

## Design decisions

- **Acceleration runs on the phone.** Synthetic CGEvents bypass macOS pointer acceleration, and the accurate touch timestamps exist only on the phone. The Mac receives whole-pixel deltas.
- **Momentum runs on the Mac.** macOS only generates scroll inertia for real trackpad hardware, so `ScrollMomentum` synthesizes momentum-phase events.
- **One TCP connection** (Nagle off). It is reliable, so a click or release can't be lost and leave a stuck button. A separate UDP lane for movement is a planned optimization.
- **Authentication.** TLS 1.2 with a pre-shared key derived from the PIN (`SHA256("glide-v1|" + pin)`). Only a peer that completes the handshake may replace the active session; unauthenticated sockets are dropped after 5 seconds; five failed handshakes rotate the PIN.
- **Three-finger swipes** post the standard keyboard shortcuts rather than private gesture APIs, so they depend on those shortcuts being enabled.
- **The Mac app can't be sandboxed** (input injection needs Accessibility), so it can't go on the Mac App Store; it would ship notarized outside the store.
