import SwiftUI
import UIKit
import GlideCore

/// Full-screen multitouch pad. Feeds every touch change into `TrackpadPipeline`.
final class TouchSurfaceView: UIView {
    var onEvents: (([InputEvent]) -> Void)?
    var tuning = Tuning() { didSet { applyTuning() } }

    private var pipeline = TrackpadPipeline()
    private var ids: [ObjectIdentifier: Int] = [:]
    private var nextID = 0
    private let haptics = Haptics()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .black
        applyTuning()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyTuning() {
        pipeline.acceleration.sensitivity = tuning.sensitivity
        pipeline.acceleration.lowGain = tuning.lowGain
        pipeline.acceleration.highGain = tuning.highGain
        pipeline.acceleration.kneeSpeed = tuning.kneeSpeed
        haptics.enabled = tuning.hapticsEnabled
        haptics.strength = tuning.hapticStrength
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { haptics.prepare() }
    }

    // MARK: - UIKit touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        process(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let event else { return }
        let active = snapshot(event)

        // One finger: replay every coalesced sample (up to 120 Hz+) for the smoothest tracking.
        if active.count == 1, touches.count == 1, let touch = touches.first,
           let coalesced = event.coalescedTouches(for: touch), coalesced.count > 1 {
            let id = active[0].id
            var out: [InputEvent] = []
            for sample in coalesced {
                let p = sample.location(in: self)
                out += pipeline.handle(touches: [Touch(id: id, x: Float(p.x), y: Float(p.y))],
                                       time: sample.timestamp)
            }
            send(out)
        } else {
            send(pipeline.handle(touches: active, time: event.timestamp))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        process(event)
        for t in touches { ids[ObjectIdentifier(t)] = nil }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { ids[ObjectIdentifier(t)] = nil }
        send(pipeline.cancel(at: event?.timestamp ?? ProcessInfo.processInfo.systemUptime))
    }

    // MARK: - Helpers

    private func process(_ event: UIEvent?) {
        let time = event?.timestamp ?? ProcessInfo.processInfo.systemUptime
        send(pipeline.handle(touches: snapshot(event), time: time))
    }

    private func id(for touch: UITouch) -> Int {
        let key = ObjectIdentifier(touch)
        if let existing = ids[key] { return existing }
        nextID += 1
        ids[key] = nextID
        return nextID
    }

    /// Every finger currently on the glass, in a stable order (oldest finger first).
    private func snapshot(_ event: UIEvent?) -> [Touch] {
        guard let all = event?.allTouches else { return [] }
        return all
            .filter { $0.phase != .ended && $0.phase != .cancelled }
            .map { touch -> Touch in
                let p = touch.location(in: self)
                return Touch(id: id(for: touch), x: Float(p.x), y: Float(p.y))
            }
            .sorted { $0.id < $1.id }
    }

    private func send(_ events: [InputEvent]) {
        guard !events.isEmpty else { return }
        haptics.play(for: events)
        var out = events
        if !tuning.naturalScrolling {
            out = events.map { event -> InputEvent in
                if case let .scroll(dx, dy, phase) = event { return .scroll(dx: -dx, dy: -dy, phase: phase) }
                return event
            }
        }
        onEvents?(out)
    }
}

struct TouchSurface: UIViewRepresentable {
    let tuning: Tuning
    let onEvents: ([InputEvent]) -> Void

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        view.onEvents = onEvents
        view.tuning = tuning
        return view
    }

    func updateUIView(_ view: TouchSurfaceView, context: Context) {
        view.onEvents = onEvents
        if view.tuning != tuning { view.tuning = tuning }
    }
}
