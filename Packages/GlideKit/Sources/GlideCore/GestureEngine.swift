import Foundation

public struct Touch: Equatable {
    public var id: Int
    public var x: Float
    public var y: Float
    public init(id: Int, x: Float, y: Float) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public struct GestureConfig {
    public var tapMaxDuration: Double = 0.25
    public var tapMaxTravel: Float = 12
    /// A touch that lands this soon after a tap becomes a click-and-drag (or double/triple click).
    public var dragWindow: Double = 0.30
    /// Scroll doesn't start until fingers have travelled this far (keeps taps clean).
    public var scrollStartTravel: Float = 2
    public var swipeMinDistance: Float = 60
    public init() {}
}

public enum GestureOutput: Equatable {
    /// Raw pointer movement in touch points; run through `PointerAcceleration` before sending.
    case pointerDelta(dx: Float, dy: Float)
    case event(InputEvent)
}

/// Turns a stream of "here are all fingers currently down" snapshots into trackpad behaviour:
/// pointing, tap to click, two-finger tap for right click, tap-and-drag, two-finger scroll
/// and three-finger swipes.
public struct GestureEngine {
    private enum Mode { case idle, pointing, dragging, scrolling, multi, ignoring }
    private struct P { var x: Float; var y: Float }

    public var config = GestureConfig()

    private var mode: Mode = .idle
    private var last: [Int: P] = [:]
    private var startPos: [Int: P] = [:]
    private var startTime: Double = 0
    private var maxTouches = 0
    private var maxDisplacement: Float = 0
    private var primaryID: Int?
    private var lastTapTime: Double = -1

    private var scrollStarted = false
    private var scrollPos = P(x: 0, y: 0)
    private var velocity = VelocityTracker()

    private var multiStart = P(x: 0, y: 0)
    private var multiCurrent = P(x: 0, y: 0)

    public init() {}

    /// Abandon any gesture in progress (e.g. app backgrounded). Releases a held button.
    public mutating func cancel(at time: Double) -> [GestureOutput] {
        var out: [GestureOutput] = []
        if mode == .dragging { out.append(.event(.button(.left, down: false))) }
        if mode == .scrolling && scrollStarted {
            out.append(.event(.scroll(dx: 0, dy: 0, phase: .ended)))
        }
        mode = .idle
        last = [:]
        lastTapTime = -1
        return out
    }

    public mutating func update(touches: [Touch], time: Double) -> [GestureOutput] {
        var current: [Int: P] = [:]
        for t in touches { current[t.id] = P(x: t.x, y: t.y) }
        let n = current.count
        var out: [GestureOutput] = []

        if mode == .idle {
            guard n > 0 else { last = [:]; return [] }
            beginGesture(touches: touches, current: current, time: time, out: &out)
            last = current
            return out
        }

        if n == 0 {
            out += finish(time: time)
            mode = .idle
            last = [:]
            return out
        }

        maxTouches = max(maxTouches, n)
        for (id, p) in current {
            if let s = startPos[id] {
                maxDisplacement = max(maxDisplacement, hypot(p.x - s.x, p.y - s.y))
            } else {
                startPos[id] = p
            }
        }

        switch mode {
        case .pointing:
            if n >= 3 {
                mode = .multi
                beginMulti(current)
            } else if n == 2 {
                mode = .scrolling
                resetScroll(at: time)
            } else if let id = touches.first?.id {
                if id == primaryID, let prev = last[id], let cur = current[id] {
                    appendPointer(from: prev, to: cur, out: &out)
                } else {
                    primaryID = id
                }
            }

        case .dragging:
            if let id = primaryID, let prev = last[id], let cur = current[id] {
                appendPointer(from: prev, to: cur, out: &out)
            } else if let id = touches.first?.id {
                primaryID = id // original finger lifted; follow another without jumping
            }

        case .scrolling:
            if n >= 3 {
                if scrollStarted { out.append(scrollEnd(at: time)) }
                mode = .multi
                beginMulti(current)
            } else if n == 2 {
                var sx: Float = 0, sy: Float = 0, count: Float = 0
                for (id, cur) in current {
                    if let prev = last[id] {
                        sx += cur.x - prev.x
                        sy += cur.y - prev.y
                        count += 1
                    }
                }
                if count > 0 {
                    let dx = sx / count, dy = sy / count
                    scrollPos.x += dx
                    scrollPos.y += dy
                    if scrollStarted {
                        velocity.add(x: scrollPos.x, y: scrollPos.y, time: time)
                        out.append(.event(.scroll(dx: dx, dy: dy, phase: .changed)))
                    } else if hypot(scrollPos.x, scrollPos.y) >= config.scrollStartTravel {
                        scrollStarted = true
                        velocity.add(x: scrollPos.x, y: scrollPos.y, time: time)
                        out.append(.event(.scroll(dx: 0, dy: 0, phase: .began)))
                        out.append(.event(.scroll(dx: scrollPos.x, dy: scrollPos.y, phase: .changed)))
                    }
                }
            } else if scrollStarted {
                // Dropped to one finger mid-scroll: finish cleanly, ignore the rest.
                out.append(scrollEnd(at: time))
                mode = .ignoring
            }
            // Dropped to one finger before scrolling began: stay put, so a slightly
            // staggered two-finger tap still registers as a right click on lift.

        case .multi:
            if n >= 3 {
                multiCurrent = centroid(current)
            } else {
                out += resolveMulti()
                mode = .ignoring
            }

        case .ignoring, .idle:
            break
        }

        last = current
        return out
    }

    // MARK: - Gesture start / end

    private mutating func beginGesture(touches: [Touch], current: [Int: P], time: Double,
                                       out: inout [GestureOutput]) {
        startTime = time
        startPos = current
        maxTouches = current.count
        maxDisplacement = 0
        primaryID = touches.first?.id

        if current.count == 1 {
            if lastTapTime >= 0 && time - lastTapTime <= config.dragWindow {
                mode = .dragging
                out.append(.event(.button(.left, down: true)))
            } else {
                mode = .pointing
            }
        } else if current.count == 2 {
            mode = .scrolling
            resetScroll(at: time)
        } else {
            mode = .multi
            beginMulti(current)
        }
    }

    private mutating func finish(time: Double) -> [GestureOutput] {
        let isTap = time - startTime <= config.tapMaxDuration
            && maxDisplacement <= config.tapMaxTravel
        switch mode {
        case .pointing:
            if maxTouches == 1 && isTap {
                lastTapTime = time
                return [.event(.button(.left, down: true)), .event(.button(.left, down: false))]
            }
            lastTapTime = -1
            return []

        case .dragging:
            // A drag that barely moved is really a second/third click of a multi-click.
            lastTapTime = maxDisplacement <= config.tapMaxTravel ? time : -1
            return [.event(.button(.left, down: false))]

        case .scrolling:
            lastTapTime = -1
            if scrollStarted { return [scrollEnd(at: time)] }
            if maxTouches == 2 && isTap {
                return [.event(.button(.right, down: true)), .event(.button(.right, down: false))]
            }
            return []

        case .multi:
            lastTapTime = -1
            return resolveMulti()

        case .ignoring, .idle:
            lastTapTime = -1
            return []
        }
    }

    // MARK: - Helpers

    private func appendPointer(from prev: P, to cur: P, out: inout [GestureOutput]) {
        let dx = cur.x - prev.x, dy = cur.y - prev.y
        if dx != 0 || dy != 0 { out.append(.pointerDelta(dx: dx, dy: dy)) }
    }

    private mutating func resetScroll(at time: Double) {
        scrollStarted = false
        scrollPos = P(x: 0, y: 0)
        velocity.reset()
        velocity.add(x: 0, y: 0, time: time)
    }

    private func scrollEnd(at time: Double) -> GestureOutput {
        let v = velocity.velocity(at: time)
        return .event(.scroll(dx: v.vx, dy: v.vy, phase: .ended))
    }

    private func centroid(_ points: [Int: P]) -> P {
        let n = Float(points.count)
        let sx = points.values.reduce(0) { $0 + $1.x }
        let sy = points.values.reduce(0) { $0 + $1.y }
        return P(x: sx / n, y: sy / n)
    }

    private mutating func beginMulti(_ current: [Int: P]) {
        multiStart = centroid(current)
        multiCurrent = multiStart
    }

    private func resolveMulti() -> [GestureOutput] {
        let dx = multiCurrent.x - multiStart.x
        let dy = multiCurrent.y - multiStart.y
        guard hypot(dx, dy) >= config.swipeMinDistance else { return [] }
        let action: SystemAction
        if abs(dx) > abs(dy) {
            action = dx < 0 ? .spaceRight : .spaceLeft // content moves with the fingers
        } else {
            action = dy < 0 ? .missionControl : .appExpose
        }
        return [.event(.action(action))]
    }
}
