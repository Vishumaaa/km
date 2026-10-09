# Troubleshooting

## Xcode

**The scheme list only shows GlideCore / GlideNet.**
You opened the Swift package instead of the project. Quit Xcode and run `open Glide.xcodeproj` from the repo root. If **Glide** and **GlideMac** still don't appear: scheme menu, Manage Schemes, **Autocreate Schemes Now**.

**"Signing requires a development team."**
Click the project, select the target, Signing & Capabilities, choose your Team. Better: run `./scripts/setup.sh` again so the Team ID is saved (regenerating the project otherwise clears it).

**My iPhone isn't listed as a destination.**
Unlock it, replug the cable, tap **Trust**, and enable Developer Mode (Settings, Privacy & Security, Developer Mode, restart). Check Window, Devices and Simulators (⇧⌘2).

**"Untrusted Developer" on the iPhone.**
Settings, General, **VPN & Device Management**, tap your Apple ID, **Trust**.

**The bundle ID is not available.**
Someone already owns it. Re-run `./scripts/setup.sh` with a more unique prefix.

**The app disappeared / won't open after a week.**
Free Apple ID builds expire after 7 days. Run it from Xcode again.

## Connecting

**The Mac doesn't appear on the iPhone.**
- The Mac app must be running (look for the Glide window or menu-bar hand icon).
- Both devices on the same Wi-Fi; turn off VPNs; avoid guest or "client isolation" networks.
- iPhone: Settings, Privacy & Security, **Local Network**, make sure Glide is on.
- Mac: System Settings, Privacy & Security, **Local Network**, make sure Glide is on, and check the firewall isn't blocking it.
- The **Debug log** at the bottom of the iPhone connect screen shows what it found.

**It sits on "Connecting…" or says it couldn't connect.**
Re-enter the PIN exactly as shown in the Mac window. After 5 wrong tries the Mac generates a new PIN. The connect attempt gives up after 10 seconds; check the debug log lines on both devices.

**The menu-bar icon is missing.**
Notched MacBooks hide menu-bar icons when it's crowded. The Glide window shows the same PIN and status.

## It connects but nothing happens

**The cursor doesn't move.**
Grant **Accessibility** (see the README), then quit and reopen the Mac app. If Glide is already toggled on but the warning remains, the entry is stale: run `tccutil reset Accessibility <your-prefix>.glide.mac`, remove Glide from the list with **−**, and grant it again.

**Three-finger swipes do nothing.**
They send the standard keyboard shortcuts (Ctrl + arrow keys). Enable them in System Settings, Keyboard, Keyboard Shortcuts, **Mission Control**.

**Scrolling is backwards.**
Toggle **Natural scrolling** in the iPhone's Feel panel (sliders icon).

**The pointer is too fast or slow.**
Adjust **Sensitivity** in the Feel panel.

## Still stuck?

Open an issue with: your macOS and iOS versions, what you see on screen, and the Debug log from the iPhone connect screen.
