import Foundation

/// User-adjustable feel parameters. Live-tweakable from the trackpad screen.
struct Tuning: Codable, Equatable {
    var sensitivity: Float = 1.0
    var lowGain: Float = 1.2
    var highGain: Float = 5.0
    var kneeSpeed: Float = 600
    var naturalScrolling = true

    private static let key = "tuning.v1"

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
