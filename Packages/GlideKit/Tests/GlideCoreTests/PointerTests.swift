import XCTest
@testable import GlideCore

final class PointerTests: XCTestCase {
    func testGainRisesMonotonicallyAndStaysInBounds() {
        let a = PointerAcceleration()
        var previous: Float = 0
        for speed in stride(from: Float(0), through: 5000, by: 50) {
            let g = a.gain(forSpeed: speed)
            XCTAssertGreaterThanOrEqual(g, previous)
            XCTAssertGreaterThanOrEqual(g, a.lowGain)
            XCTAssertLessThanOrEqual(g, a.highGain)
            previous = g
        }
    }

    func testSlowMovementDoesNotStallBecauseOfRounding() {
        var a = PointerAcceleration()
        var total = 0
        for _ in 0..<120 { total += Int(a.process(dx: 0.3, dy: 0, dt: 1.0 / 120).dx) }
        // 120 * 0.3 = 36 touch points at roughly lowGain: expect well over 36 px, never 0.
        XCTAssertGreaterThan(total, 36)
    }

    func testSymmetry() {
        var right = PointerAcceleration()
        var left = PointerAcceleration()
        let r = right.process(dx: 10, dy: 0, dt: 1.0 / 60)
        let l = left.process(dx: -10, dy: 0, dt: 1.0 / 60)
        XCTAssertEqual(r.dx, -l.dx)
    }

    func testMomentumDecaysAndFinishes() {
        var m = ScrollMomentum(vx: 0, vy: 1500)
        XCTAssertTrue(m.shouldStart)
        var distance: Float = 0
        var finished = false
        for _ in 0..<1000 {
            let step = m.step(dt: 1.0 / 120)
            XCTAssertGreaterThanOrEqual(step.dy, 0)
            distance += step.dy
            if step.finished { finished = true; break }
        }
        XCTAssertTrue(finished)
        // Total travel of exp decay is v / friction.
        XCTAssertEqual(distance, 1500 / m.friction, accuracy: 25)
    }

    func testSlowReleaseDoesNotFling() {
        XCTAssertFalse(ScrollMomentum(vx: 0, vy: 40).shouldStart)
    }

    func testVelocityTrackerIgnoresStalePauses() {
        var v = VelocityTracker()
        for i in 0..<10 { v.add(x: 0, y: Float(i) * 10, time: Double(i) * 0.01) }
        XCTAssertGreaterThan(v.velocity(at: 0.09).vy, 900)
        XCTAssertEqual(v.velocity(at: 0.5).vy, 0) // finger rested before lifting
    }
}
