import Foundation

/// Velocity-based pointer acceleration with sub-pixel accumulation.
///
/// Posting synthetic events from the Mac bypasses macOS's own pointer acceleration, so the
/// curve lives here. Gain rises smoothly from `lowGain` (slow, precise movement) to `highGain`
/// (fast flicks across the screen). These defaults are a starting point for tuning by feel.
public struct PointerAcceleration {
    public var sensitivity: Float = 1.0
    public var lowGain: Float = 1.2
    public var highGain: Float = 5.0
    /// Speed (touch points/second) at which gain is halfway between low and high.
    public var kneeSpeed: Float = 600

    private var smoothedSpeed: Float = 0
    private var remainderX: Float = 0
    private var remainderY: Float = 0

    public init() {}

    public func gain(forSpeed speed: Float) -> Float {
        let s2 = speed * speed
        let k2 = kneeSpeed * kneeSpeed
        return lowGain + (highGain - lowGain) * (s2 / (s2 + k2))
    }

    /// Clears speed history (call at the start of a new touch).
    public mutating func resetSpeed() {
        smoothedSpeed = 0
    }

    /// Converts a raw touch delta (points) into whole Mac points, carrying fractions forward.
    public mutating func process(dx: Float, dy: Float, dt: Double) -> (dx: Int16, dy: Int16) {
        let clampedDt = Float(min(max(dt, 1.0 / 240.0), 1.0 / 20.0))
        let speed = (dx * dx + dy * dy).squareRoot() / clampedDt
        // Light smoothing so timestamp jitter doesn't make the gain flutter.
        smoothedSpeed += 0.4 * (speed - smoothedSpeed)

        let g = gain(forSpeed: smoothedSpeed) * sensitivity
        let totalX = remainderX + dx * g
        let totalY = remainderY + dy * g
        let wholeX = totalX.rounded(.towardZero)
        let wholeY = totalY.rounded(.towardZero)
        remainderX = totalX - wholeX
        remainderY = totalY - wholeY
        return (Self.clampToInt16(wholeX), Self.clampToInt16(wholeY))
    }

    private static func clampToInt16(_ v: Float) -> Int16 {
        Int16(max(Float(Int16.min), min(Float(Int16.max), v)))
    }
}
