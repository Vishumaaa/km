import Foundation

/// User-adjustable feel parameters. Live-tweakable from the trackpad screen.
struct Tuning: Codable, Equatable {
    var sensitivity: Float = 1.0
    var lowGain: Float = 1.2
    var highGain: Float = 5.0
    var kneeSpeed: Float = 600
    var naturalScrolling = true
    var hapticsEnabled = true
    var hapticStrength: Float = 1.0
    /// Touches that start this close (points) to the left/right edge are ignored (resting thumbs).
    var edgeMargin: Float = 36

    private static let key = "tuning.v1"

    init() {}

    /// Tolerant decoding, so settings saved by older versions still load when fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Tuning()
        sensitivity = try c.decodeIfPresent(Float.self, forKey: .sensitivity) ?? d.sensitivity
        lowGain = try c.decodeIfPresent(Float.self, forKey: .lowGain) ?? d.lowGain
        highGain = try c.decodeIfPresent(Float.self, forKey: .highGain) ?? d.highGain
        kneeSpeed = try c.decodeIfPresent(Float.self, forKey: .kneeSpeed) ?? d.kneeSpeed
        naturalScrolling = try c.decodeIfPresent(Bool.self, forKey: .naturalScrolling) ?? d.naturalScrolling
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        hapticStrength = try c.decodeIfPresent(Float.self, forKey: .hapticStrength) ?? d.hapticStrength
        edgeMargin = try c.decodeIfPresent(Float.self, forKey: .edgeMargin) ?? d.edgeMargin
    }

    static func load() -> Tuning {
        guard let data = UserDefaults.standard.data(forKey: key),
              let tuning = try? JSONDecoder().decode(Tuning.self, from: data) else { return Tuning() }
        return tuning
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
