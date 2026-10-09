import AppKit
import CoreGraphics
import GlideCore

/// Turns `InputEvent`s into real macOS input via CGEvent. Needs Accessibility permission.
/// Everything runs on one private serial queue, so it is safe to call from any thread.
final class InputInjector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "glide.injector", qos: .userInteractive)
    private let source = CGEventSource(stateID: .hidSystemState)

    private var leftDown = false
    private var rightDown = false
    private var clickCount: Int64 = 0
    private var lastClickUptime: TimeInterval = 0
    private var lastClickPoint = CGPoint.zero
    private var lastClickButton: MouseButton = .left
    private var leftDownAt: TimeInterval = 0
    private var rightDownAt: TimeInterval = 0

    private var scrollRemainderX: Float = 0
    private var scrollRemainderY: Float = 0
    private var momentum: ScrollMomentum?
    private var momentumTimer: DispatchSourceTimer?
    private var momentumTick: TimeInterval = 0
    private var momentumStarted = false

    private var cachedDisplays: [CGRect] = []
    private var displaysFetchedAt: TimeInterval = 0

    func handle(_ events: [InputEvent]) {
        queue.async { events.forEach(self.apply) }
    }

    /// Releases anything held down (call when the phone disconnects).
    func releaseAll() {
        queue.async {
            if self.leftDown { self.button(.left, down: false) }
            if self.rightDown { self.button(.right, down: false) }
            self.stopMomentum()
        }
    }

    private func apply(_ event: InputEvent) {
        switch event {
        case let .move(dx, dy): move(dx: Int(dx), dy: Int(dy))
        case let .button(b, down): button(b, down: down)
        case let .scroll(dx, dy, phase): scroll(dx: dx, dy: dy, phase: phase)
        case let .action(action): perform(action)
        }
    }

    // MARK: - Pointer

    /// Modifier flags for synthetic mouse events: whatever is really held (Cmd, Shift, Option),
    /// minus Control/Fn, which we only ever synthesize ourselves. A stale Control would make
    /// left clicks behave as right clicks.
    private func cleanFlags() -> CGEventFlags {
        CGEventSource.flagsState(.hidSystemState).subtracting([.maskControl, .maskSecondaryFn, .maskNumericPad])
    }

    private var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func move(dx: Int, dy: Int) {
        let current = location
        let target = constrained(CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy)),
                                 from: current)
        let type: CGEventType = leftDown ? .leftMouseDragged : (rightDown ? .rightMouseDragged : .mouseMoved)
        let cgButton: CGMouseButton = rightDown ? .right : .left
        guard let e = CGEvent(mouseEventSource: source, mouseType: type,
                              mouseCursorPosition: target, mouseButton: cgButton) else { return }
        e.flags = cleanFlags()
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        e.post(tap: .cghidEventTap)
    }

    /// Keeps the cursor on a screen. Moving off the edge clamps to the display you were on.
    private func constrained(_ p: CGPoint, from current: CGPoint) -> CGPoint {
        let displays = displayBounds()
        if displays.contains(where: { $0.contains(p) }) { return p }
        guard let home = displays.first(where: { $0.contains(current) }) ?? displays.first else { return p }
        return CGPoint(x: min(max(p.x, home.minX), home.maxX - 1),
                       y: min(max(p.y, home.minY), home.maxY - 1))
    }

    private func displayBounds() -> [CGRect] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - displaysFetchedAt < 1, !cachedDisplays.isEmpty { return cachedDisplays }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        cachedDisplays = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        displaysFetchedAt = now
        return cachedDisplays
    }

    // MARK: - Buttons

    private func button(_ b: MouseButton, down: Bool) {
        if down {
            if (b == .left && leftDown) || (b == .right && rightDown) { return }
            stopMomentum() // touching the pad stops inertia, like the real thing
        } else if (b == .left && !leftDown) || (b == .right && !rightDown) {
            return
        } else {
            // A tap arrives as press + release in the same instant. Some controls (Safari's
            // toolbar, tab strips) treat a zero-length press as press-and-hold or ignore it,
            // so make every click last at least as long as a quick real one.
            let heldFor = ProcessInfo.processInfo.systemUptime - (b == .left ? leftDownAt : rightDownAt)
            let minimum = 0.045
            if heldFor < minimum { usleep(UInt32((minimum - heldFor) * 1_000_000)) }
        }

        let p = location
        let type: CGEventType
        let cgButton: CGMouseButton
        switch (b, down) {
        case (.left, true): type = .leftMouseDown; cgButton = .left
        case (.left, false): type = .leftMouseUp; cgButton = .left
        case (.right, true): type = .rightMouseDown; cgButton = .right
        case (.right, false): type = .rightMouseUp; cgButton = .right
        }

        if down {
            let now = ProcessInfo.processInfo.systemUptime
            let near = hypot(p.x - lastClickPoint.x, p.y - lastClickPoint.y) < 8
            if lastClickButton == b && near && now - lastClickUptime <= NSEvent.doubleClickInterval {
                clickCount += 1
            } else {
                clickCount = 1
            }
            lastClickUptime = now
            lastClickPoint = p
            lastClickButton = b
        }

        if let e = CGEvent(mouseEventSource: source, mouseType: type,
                           mouseCursorPosition: p, mouseButton: cgButton) {
            e.flags = cleanFlags()
            e.setIntegerValueField(.mouseEventClickState, value: clickCount)
            e.setIntegerValueField(.mouseEventButtonNumber, value: b == .left ? 0 : 1)
            e.setDoubleValueField(.mouseEventPressure, value: down ? 1.0 : 0.0)
            e.post(tap: .cghidEventTap)
        }
        if down {
            let now = ProcessInfo.processInfo.systemUptime
            if b == .left { leftDownAt = now } else { rightDownAt = now }
        }
        if b == .left { leftDown = down } else { rightDown = down }
    }

    // MARK: - Scrolling

    // CGScrollPhase / CGMomentumScrollPhase raw values.
    private enum ScrollPhaseRaw {
        static let began: Int64 = 1, changed: Int64 = 2, ended: Int64 = 4
        static let momentumBegin: Int64 = 1, momentumContinue: Int64 = 2, momentumEnd: Int64 = 3
    }

    private func scroll(dx: Float, dy: Float, phase: ScrollPhase) {
        switch phase {
        case .began:
            stopMomentum()
            scrollRemainderX = 0
            scrollRemainderY = 0
            postScroll(dx: 0, dy: 0, phase: ScrollPhaseRaw.began, momentumPhase: 0)
        case .changed:
            postScroll(dx: dx, dy: dy, phase: ScrollPhaseRaw.changed, momentumPhase: 0)
        case .ended:
            // dx/dy carry the release velocity (points/second).
            postScroll(dx: 0, dy: 0, phase: ScrollPhaseRaw.ended, momentumPhase: 0)
            startMomentum(vx: dx, vy: dy)
        }
    }

    private func postScroll(dx: Float, dy: Float, phase: Int64, momentumPhase: Int64) {
        scrollRemainderX += dx
        scrollRemainderY += dy
        let ix = Int32(scrollRemainderX.rounded(.towardZero))
        let iy = Int32(scrollRemainderY.rounded(.towardZero))
        scrollRemainderX -= Float(ix)
        scrollRemainderY -= Float(iy)

        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                              wheel1: iy, wheel2: ix, wheel3: 0) else { return }
        e.flags = cleanFlags()
        // Pin the event to the pointer. Without an explicit location, browser-based apps
        // (Electron, Chromium) can't tell which view the scroll belongs to and drop it.
        e.location = location
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        e.post(tap: .cghidEventTap)
    }

    private func startMomentum(vx: Float, vy: Float) {
        let m = ScrollMomentum(vx: vx, vy: vy)
        guard m.shouldStart else { return }
        momentum = m
        momentumStarted = false
        momentumTick = ProcessInfo.processInfo.systemUptime

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.stepMomentum() }
        momentumTimer = timer
        timer.resume()
    }

    private func stepMomentum() {
        guard var m = momentum else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - momentumTick
        momentumTick = now

        let step = m.step(dt: dt)
        momentum = m
        if step.finished {
            postScroll(dx: 0, dy: 0, phase: 0, momentumPhase: ScrollPhaseRaw.momentumEnd)
            cancelMomentumTimer()
        } else {
            let phase = momentumStarted ? ScrollPhaseRaw.momentumContinue : ScrollPhaseRaw.momentumBegin
            momentumStarted = true
            postScroll(dx: step.dx, dy: step.dy, phase: 0, momentumPhase: phase)
        }
    }

    private func stopMomentum() {
        guard momentum != nil else { return }
        if momentumStarted {
            postScroll(dx: 0, dy: 0, phase: 0, momentumPhase: ScrollPhaseRaw.momentumEnd)
        }
        cancelMomentumTimer()
    }

    private func cancelMomentumTimer() {
        momentumTimer?.cancel()
        momentumTimer = nil
        momentum = nil
        momentumStarted = false
    }

    // MARK: - System gestures (via the stock keyboard shortcuts)

    private func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    private func perform(_ action: SystemAction) {
        let key: CGKeyCode
        switch action {
        case .missionControl: key = 126 // Ctrl+Up
        case .appExpose: key = 125      // Ctrl+Down
        case .spaceLeft: key = 123      // Ctrl+Left
        case .spaceRight: key = 124     // Ctrl+Right
        }
        // Press and release Control like a real keyboard would. Posting arrow keys that merely
        // carry a Control flag leaves macOS believing Control is still down, and it then stamps
        // that flag onto later clicks, which turns every left click into a right click.
        let controlKey: CGKeyCode = 59
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn]
        postKey(controlKey, down: true, flags: .maskControl)
        postKey(key, down: true, flags: arrowFlags)
        postKey(key, down: false, flags: arrowFlags)
        postKey(controlKey, down: false, flags: [])
    }
}
