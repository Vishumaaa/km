import XCTest
@testable import GlideCore

final class GestureTests: XCTestCase {
    private func run(_ engine: inout GestureEngine, _ frames: [(t: Double, touches: [Touch])]) -> [GestureOutput] {
        frames.flatMap { engine.update(touches: $0.touches, time: $0.t) }
    }

    private func finger(_ id: Int, _ x: Float, _ y: Float) -> Touch { Touch(id: id, x: x, y: y) }

    func testOneFingerMoveEmitsPointerDeltas() {
        var e = GestureEngine()
        let out = run(&e, [(0, [finger(1, 100, 100)]), (0.01, [finger(1, 104, 98)])])
        XCTAssertEqual(out, [.pointerDelta(dx: 4, dy: -2)])
    }

    func testTapClicks() {
        var e = GestureEngine()
        let out = run(&e, [(0, [finger(1, 50, 50)]), (0.1, [])])
        XCTAssertEqual(out, [.event(.button(.left, down: true)), .event(.button(.left, down: false))])
    }

    func testSlowPressIsNotATap() {
        var e = GestureEngine()
        let out = run(&e, [(0, [finger(1, 50, 50)]), (0.6, [])])
        XCTAssertTrue(out.isEmpty)
    }

    func testTwoFingerTapRightClicks() {
        var e = GestureEngine()
        let out = run(&e, [(0, [finger(1, 50, 50), finger(2, 90, 50)]), (0.1, [])])
        XCTAssertEqual(out, [.event(.button(.right, down: true)), .event(.button(.right, down: false))])
    }

    func testStaggeredTwoFingerLiftStillRightClicks() {
        var e = GestureEngine()
        let out = run(&e, [
            (0, [finger(1, 50, 50), finger(2, 90, 50)]),
            (0.08, [finger(1, 50, 50)]),
            (0.10, []),
        ])
        XCTAssertEqual(out, [.event(.button(.right, down: true)), .event(.button(.right, down: false))])
    }

    func testTwoFingerScrollBeginsChangesEndsWithVelocity() {
        var e = GestureEngine()
        var frames: [(t: Double, touches: [Touch])] = [(0, [finger(1, 50, 100), finger(2, 90, 100)])]
        for i in 1...10 {
            let y = 100 + Float(i) * 10
            frames.append((Double(i) * 0.01, [finger(1, 50, y), finger(2, 90, y)]))
        }
        frames.append((0.105, []))
        let out = run(&e, frames)

        guard case let .event(.scroll(_, _, firstPhase))? = out.first else { return XCTFail("no scroll") }
        XCTAssertEqual(firstPhase, .began)
        guard case let .event(.scroll(_, vy, lastPhase))? = out.last else { return XCTFail("no end") }
        XCTAssertEqual(lastPhase, .ended)
        XCTAssertGreaterThan(vy, 800) // 10 pt per 10 ms = 1000 pt/s

        let total = out.reduce(Float(0)) {
            if case let .event(.scroll(_, dy, .changed)) = $1 { return $0 + dy }
            return $0
        }
        XCTAssertEqual(total, 100, accuracy: 0.01)
        XCTAssertFalse(out.contains(.event(.button(.right, down: true))))
    }

    func testTapAndDragHoldsButtonThenReleases() {
        var e = GestureEngine()
        let out = run(&e, [
            (0, [finger(1, 50, 50)]), (0.08, []),             // tap
            (0.2, [finger(1, 50, 50)]),                       // touch again quickly: press
            (0.25, [finger(1, 70, 50)]),                      // drag
            (0.4, []),                                        // release
        ])
        XCTAssertEqual(out, [
            .event(.button(.left, down: true)), .event(.button(.left, down: false)),
            .event(.button(.left, down: true)),
            .pointerDelta(dx: 20, dy: 0),
            .event(.button(.left, down: false)),
        ])
    }

    func testCancelReleasesHeldButton() {
        var e = GestureEngine()
        _ = run(&e, [(0, [finger(1, 5, 5)]), (0.05, []), (0.1, [finger(1, 5, 5)])])
        XCTAssertEqual(e.cancel(at: 0.2), [.event(.button(.left, down: false))])
    }

    func testThreeFingerSwipeLeftGoesToNextSpace() {
        var e = GestureEngine()
        func three(_ x: Float) -> [Touch] { [finger(1, x, 100), finger(2, x + 30, 100), finger(3, x + 60, 100)] }
        let out = run(&e, [(0, three(200)), (0.05, three(150)), (0.1, three(100)), (0.15, [])])
        XCTAssertEqual(out, [.event(.action(.spaceRight))])
    }

    func testThreeFingerSwipeUpIsMissionControl() {
        var e = GestureEngine()
        func three(_ y: Float) -> [Touch] { [finger(1, 100, y), finger(2, 130, y), finger(3, 160, y)] }
        let out = run(&e, [(0, three(300)), (0.05, three(240)), (0.1, three(180)), (0.15, [])])
        XCTAssertEqual(out, [.event(.action(.missionControl))])
    }

    func testPipelineAcceleratesAndConvertsToWholePixels() {
        var p = TrackpadPipeline()
        _ = p.handle(touches: [finger(1, 0, 0)], time: 0)
        let events = p.handle(touches: [finger(1, 10, 0)], time: 1.0 / 60)
        guard case let .move(dx, dy)? = events.first else { return XCTFail("no move") }
        XCTAssertGreaterThanOrEqual(dx, 10) // gain >= 1
        XCTAssertEqual(dy, 0)
    }
}
