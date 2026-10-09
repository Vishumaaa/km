import Foundation

/// Phone-side glue: touches in, wire-ready events out.
public struct TrackpadPipeline {
    public var engine = GestureEngine()
    public var acceleration = PointerAcceleration()
    private var lastPointerTime: Double?

    public init() {}

    /// `touches` is every finger currently down; `time` is the touch timestamp in seconds.
    public mutating func handle(touches: [Touch], time: Double) -> [InputEvent] {
        var events: [InputEvent] = []
        for output in engine.update(touches: touches, time: time) {
            switch output {
            case let .pointerDelta(dx, dy):
                var dt = lastPointerTime.map { time - $0 } ?? 1.0 / 60.0
                if dt > 0.1 || dt <= 0 {
                    acceleration.resetSpeed() // new touch after a pause
                    dt = 1.0 / 60.0
                }
                lastPointerTime = time
                let moved = acceleration.process(dx: dx, dy: dy, dt: dt)
                if moved.dx != 0 || moved.dy != 0 {
                    events.append(.move(dx: moved.dx, dy: moved.dy))
                }
            case let .event(event):
                events.append(event)
            }
        }
        return events
    }

    public mutating func cancel(at time: Double) -> [InputEvent] {
        engine.cancel(at: time).compactMap { output in
            if case let .event(e) = output { return e }
            return nil
        }
    }
}
