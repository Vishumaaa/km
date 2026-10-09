# Glide (working name)

Use your iPhone as a Mac trackpad. Native Swift on both sides.

```
Packages/GlideKit/
  GlideCore   pure-Swift logic: wire protocol, gesture engine, pointer curve, scroll momentum
  GlideNet    Network.framework transport: Bonjour discovery + TLS (PIN-derived pre-shared key)
iOS/Glide     iPhone app: multitouch surface, Mac discovery, live "Feel" tuning sheet
Mac/GlideMac  menu-bar companion: receives events and injects them with CGEvent
project.yml   XcodeGen spec that generates the Xcode project for both apps
```

## Run it

Requirements: Xcode 15+, an iPhone on iOS 17+, a Mac on macOS 14+, both on the same Wi-Fi.

```sh
brew install xcodegen
xcodegen                                    # creates Glide.xcodeproj
(cd Packages/GlideKit && swift test)        # run the core tests first
open Glide.xcodeproj
```

1. Edit `bundleIdPrefix` and the two `PRODUCT_BUNDLE_IDENTIFIER`s in `project.yml` to something unique to you, then re-run `xcodegen`.
2. In Xcode, for **both** targets, open *Signing & Capabilities* and pick your Team (a free Apple ID works).
3. Run the **GlideMac** scheme on My Mac. Grant *Accessibility* access when prompted (System Settings → Privacy & Security → Accessibility). A hand icon appears in the menu bar showing a 6-digit PIN.
4. Plug in your iPhone, enable Developer Mode (Settings → Privacy & Security), and run the **Glide** scheme on it. Allow *Local Network* access when asked.
5. Tap your Mac in the list and enter the PIN.

With a free Apple ID the iPhone build expires after 7 days; just re-run from Xcode.

## Gestures

| Gesture | Action |
|---|---|
| One finger | Move pointer (velocity-based acceleration) |
| Tap | Click |
| Two-finger tap | Right click |
| Two-finger drag | Scroll, with inertia |
| Tap, then touch and drag | Click-and-drag (tap, tap = double click) |
| Three-finger swipe up / down | Mission Control / App Exposé (Ctrl+Up / Ctrl+Down) |
| Three-finger swipe left / right | Switch Space (Ctrl+Right / Ctrl+Left) |

The swipes post the stock keyboard shortcuts, so those must be enabled in System Settings → Keyboard → Keyboard Shortcuts → Mission Control.

## Tuning the feel

Tap the sliders icon (top-left of the trackpad screen) to adjust sensitivity and the acceleration curve live.
The defaults in `PointerAcceleration` / `GestureConfig` are educated guesses; expect to tune them.

## Design notes

- **Acceleration lives on the phone.** Events posted with CGEvent bypass macOS pointer acceleration, and touch timestamps (which are accurate) are only available on the phone. The Mac receives whole-pixel deltas.
- **Scroll momentum lives on the Mac.** macOS only generates inertia events for real trackpad hardware, so `ScrollMomentum` synthesizes them, driven by the release velocity the phone sends.
- **Transport is a single TCP connection** (Nagle off, TLS-PSK). It is reliable, so a click or button release can never be lost. Next step for the lowest latency: send move/scroll over a separate UDP channel and keep buttons on TCP.
- **Security:** only a device that knows the PIN can complete the handshake, and traffic is encrypted. After 5 failed handshakes the Mac rotates the PIN. A 6-digit PIN is low-entropy; before any public release, replace it with a random key exchanged via QR code, and store it in the Keychain.

## Status

Written without access to Xcode or a Swift compiler, so **nothing here has been compiled or run yet**. Expect to fix a few compile errors on first build. Start with `swift test` in `Packages/GlideKit`: the gesture, protocol, curve and momentum logic is unit-tested. The injector, transport and UI need real-device testing.
