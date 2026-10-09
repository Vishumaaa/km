import Foundation

/// Tracks recent positions and reports release velocity in units/second.
public struct VelocityTracker {
    private var samples: [(x: Float, y: Float, t: Double)] = []
    /// Only the last `window` seconds count, so a pause before lifting means "no fling".
    public var window: Double = 0.1

    public init() {}

    public mutating func reset() { samples.removeAll() }

    public mutating func add(x: Float, y: Float, time: Double) {
        samples.append((x, y, time))
        let w = window
        samples.removeAll { time - $0.t > w }
    }

    public func velocity(at time: Double) -> (vx: Float, vy: Float) {
        let recent = samples.filter { time - $0.t <= window }
        guard let first = recent.first, let last = recent.last else { return (0, 0) }
        let dt = Float(last.t - first.t)
        guard dt > 0.001 else { return (0, 0) }
        return ((last.x - first.x) / dt, (last.y - first.y) / dt)
    }
}

/// Exponential-decay inertia, run on the Mac after a scroll gesture ends.
/// (macOS only generates momentum events for real trackpad hardware, so we synthesize them.)
public struct ScrollMomentum {
    public static let minimumStartSpeed: Float = 150
    public static let stopSpeed: Float = 20

    /// Higher = stops sooner.
    public var friction: Float = 3.2
    private var vx: Float
    private var vy: Float

    public init(vx: Float, vy: Float) {
        self.vx = vx
        self.vy = vy
    }

    public var speed: Float { (vx * vx + vy * vy).squareRoot() }
    public var shouldStart: Bool { speed >= Self.minimumStartSpeed }

    /// Advances by `dt` seconds. Returns the distance to scroll this step and whether it's done.
    public mutating func step(dt: Double) -> (dx: Float, dy: Float, finished: Bool) {
        let decay = Float(exp(-Double(friction) * dt))
        let travel = (1 - decay) / friction // integral of e^{-kt} over dt
        let dx = vx * travel
        let dy = vy * travel
        vx *= decay
        vy *= decay
        return (dx, dy, speed < Self.stopSpeed)
    }
}
