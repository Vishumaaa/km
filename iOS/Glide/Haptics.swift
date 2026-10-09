import CoreHaptics
import UIKit
import GlideCore

/// Trackpad-style haptics. A tap-click is a sharp "press" then a soft "release", a right click
/// is a heavier, duller thud, and swipes and scroll starts get their own light cues.
/// Falls back to UIKit impact feedback on hardware without Core Haptics.
final class Haptics {
    private enum Kind: CaseIterable {
        case click, clickDown, clickUp, rightClick, action, scrollStart
    }

    var enabled = true
    var strength: Float = 1.0 {
        didSet { if oldValue != strength { buildPlayers() } }
    }

    private var engine: CHHapticEngine?
    private var players: [Kind: CHHapticPatternPlayer] = [:]
    private let fallbackDown = UIImpactFeedbackGenerator(style: .rigid)
    private let fallbackUp = UIImpactFeedbackGenerator(style: .light)

    init() {
        fallbackDown.prepare()
        fallbackUp.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = false
            e.resetHandler = { [weak self] in
                try? self?.engine?.start()
                self?.buildPlayers()
            }
            try e.start()
            engine = e
            buildPlayers()
        } catch {
            engine = nil
        }
    }

    /// Call when the view appears; the engine stops while the app is in the background.
    func prepare() {
        try? engine?.start()
    }

    /// Chooses the right cue for a batch of events produced by one touch update.
    func play(for events: [InputEvent]) {
        guard enabled else { return }
        var leftDown = false, leftUp = false, rightDown = false
        for event in events {
            switch event {
            case let .button(.left, down):
                if down { leftDown = true } else { leftUp = true }
            case let .button(.right, down):
                if down { rightDown = true }
            case .action:
                fire(.action)
            case .scroll(_, _, .began):
                fire(.scrollStart)
            default:
                break
            }
        }
        if rightDown { fire(.rightClick) }
        // A tap arrives as press + release in one batch: play one combined click, not two buzzes.
        if leftDown && leftUp {
            fire(.click)
        } else if leftDown {
            fire(.clickDown)
        } else if leftUp {
            fire(.clickUp)
        }
    }

    // MARK: - Internals

    private func fire(_ kind: Kind) {
        if let player = players[kind] {
            try? player.start(atTime: CHHapticTimeImmediate)
            return
        }
        switch kind {
        case .clickUp, .scrollStart: fallbackUp.impactOccurred(intensity: CGFloat(strength))
        default: fallbackDown.impactOccurred(intensity: CGFloat(strength))
        }
    }

    private func pulses(for kind: Kind) -> [(time: TimeInterval, intensity: Float, sharpness: Float)] {
        switch kind {
        case .click: return [(0, 0.9, 0.85), (0.05, 0.4, 0.5)]
        case .clickDown: return [(0, 0.9, 0.85)]
        case .clickUp: return [(0, 0.4, 0.5)]
        case .rightClick: return [(0, 1.0, 0.35), (0.06, 0.55, 0.25)]
        case .action: return [(0, 0.75, 0.6), (0.07, 0.6, 0.5)]
        case .scrollStart: return [(0, 0.25, 0.4)]
        }
    }

    /// Players are built once and reused so each cue starts with minimal latency.
    private func buildPlayers() {
        guard let engine else { return }
        players = [:]
        for kind in Kind.allCases {
            let events = pulses(for: kind).map { pulse in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, pulse.intensity * strength)),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.sharpness),
                    ],
                    relativeTime: pulse.time)
            }
            if let pattern = try? CHHapticPattern(events: events, parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                players[kind] = player
            }
        }
    }
}
