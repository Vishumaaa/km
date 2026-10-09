# Glide

Use your **iPhone as a trackpad for your Mac**: precise pointer movement, tap to click, right click, drag, two-finger scroll with inertia, three-finger swipes, and haptic feedback. Native Swift on both sides, over your local Wi-Fi.

> "Glide" is a working name. This is an early, self-built project: it works, but there's no App Store release yet, so you build it yourself with Xcode (free).

## Gestures

| Gesture | Action |
|---|---|
| One finger | Move the pointer (speed-based acceleration) |
| Tap | Click |
| Two-finger tap | Right click |
| Tap, then touch and drag | Click-and-drag (tap, tap = double click) |
| Two-finger drag | Scroll, with momentum |
| Three-finger swipe up / down | Mission Control / App Exposé |
| Three-finger swipe left / right | Switch Space |

The trackpad screen is landscape. Tap the sliders icon (top-left) to tune sensitivity, the acceleration curve, scroll direction and haptics live.

## Requirements

- A **Mac** on macOS 14 or later, with **Xcode 15+** (free, Mac App Store)
- An **iPhone** on iOS 17 or later, and a cable
- A free **Apple ID** (a paid developer account is *not* needed)
- [Homebrew](https://brew.sh), to install XcodeGen
- Mac and iPhone on the **same Wi-Fi** (no VPN, no guest or AP-isolated network)

Not supported yet: iPad, Android, Windows (see [Roadmap](#roadmap)).

## Quick start

```sh
brew install xcodegen
git clone https://github.com/Vishumaaa/km.git
cd km
```

**1. Sign into Xcode.** Open Xcode, then Settings, then Accounts, and add your Apple ID.

**2. Generate the project:**
```sh
./scripts/setup.sh
```
It asks for a bundle ID prefix (anything unique, like `com.yourname`), finds your Apple Team ID, and creates `Glide.xcodeproj`. If it can't find a Team ID yet, open the project, pick your Team under *Signing & Capabilities* for both targets, build once, then re-run the script.

**3. Run the Mac app.**
```sh
open Glide.xcodeproj
```
Choose the **GlideMac** scheme and **My Mac** as the destination, then press **⌘R**. A window opens showing a 6-digit **PIN**. Click **Grant Access…** and turn Glide on in System Settings, then quit and re-run it (see [Accessibility](#accessibility-permission)).

**4. Run the iPhone app.** Plug in your iPhone and turn on **Developer Mode** (Settings, then Privacy & Security, then Developer Mode, then restart). Choose the **Glide** scheme and your iPhone, then press **⌘R**. Allow **Local Network** access when asked. On first install, trust yourself under Settings, General, **VPN & Device Management**.

**5. Connect.** Tap your Mac in the list, enter the PIN, and drag a finger on the black screen.

## Using it day to day (without Xcode)

Install an optimized build of the Mac app into `/Applications`:
```sh
./scripts/install-mac.sh
```
Add it to **System Settings, General, Login Items** so it starts automatically. Re-run the script after pulling updates.

On the iPhone, a build signed with a free Apple ID stops launching after **7 days**; re-run it from Xcode to refresh. Tools like AltStore can refresh it automatically, and a paid Apple Developer account ($99/year) extends this via TestFlight. For better responsiveness on the phone, set the Glide scheme's Run configuration to **Release** (Product, Scheme, Edit Scheme, Run, Build Configuration).

## Accessibility permission

macOS only lets an app move the cursor if you grant it **System Settings, Privacy & Security, Accessibility**. The window shows an orange warning until it's granted. After turning Glide on, **quit and reopen** the Mac app.

Rebuilding can invalidate the permission. If the warning returns, run this (using your bundle ID prefix), remove Glide from the list with **−**, and grant it again:
```sh
tccutil reset Accessibility <your-prefix>.glide.mac
```

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## How it works

An iPhone app captures touches, runs them through a gesture engine and pointer-acceleration curve, and streams small binary messages over a TLS-encrypted TCP connection (found via Bonjour, authenticated by the PIN) to a Mac menu-bar app, which turns them into real mouse, scroll and keyboard events. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
Packages/GlideKit/   GlideCore (logic, unit-tested) and GlideNet (networking)
iOS/Glide/           iPhone app
Mac/GlideMac/        Mac companion app
scripts/             setup.sh, install-mac.sh, make-icon.py (regenerates the app icon)
```

## Development

```sh
cd Packages/GlideKit && swift test    # gesture, protocol, pointer-curve and momentum tests
```

## Security

Traffic is encrypted (TLS 1.2, pre-shared key derived from the PIN) and only a device that knows the PIN can connect. After 5 failed attempts the Mac rotates the PIN. A 6-digit PIN is low entropy, so treat this as a home/office-network tool until pairing is upgraded (see Roadmap). Don't use it on untrusted networks.

## Roadmap

- iPad support
- Stronger pairing (QR code with a random key, stored in the Keychain)
- Lower-latency UDP channel for pointer movement
- Signed and notarized Mac download, App Store iPhone app
- Android and Windows clients

## Contributing

Issues and pull requests are welcome. Please run `swift test` before submitting.
