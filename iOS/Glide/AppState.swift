import SwiftUI
import GlideCore
import GlideNet

@MainActor
final class AppState: ObservableObject {
    @Published var macs: [DiscoveredMac] = []
    @Published var connection: GlideClient.State = .idle
    @Published var errorMessage: String?
    @Published var log: [String] = []
    @Published var tuning: Tuning = Tuning.load() {
        didSet { tuning.save() }
    }

    var isConnected: Bool { connection == .ready }

    private let browser = GlideBrowser()
    private let client = GlideClient()
    private var currentMac: DiscoveredMac?
    private var attempt = 0

    init() {
        browser.onLog = { [weak self] line in Task { @MainActor in self?.appendLog(line) } }
        client.onLog = { [weak self] line in Task { @MainActor in self?.appendLog(line) } }
        browser.onChange = { [weak self] macs in
            Task { @MainActor in self?.macs = macs }
        }
        client.onState = { [weak self] state in
            Task { @MainActor in self?.handle(state) }
        }
        browser.start()
    }

    func connect(_ mac: DiscoveredMac, pin: String) {
        currentMac = mac
        errorMessage = nil
        // Stored in UserDefaults for now; move to the Keychain before shipping.
        UserDefaults.standard.set(pin, forKey: pinKey(mac))
        client.connect(to: mac.endpoint, pin: pin)

        // Don't hang forever on a bad PIN, a sleeping Mac, or a blocked network.
        attempt += 1
        let thisAttempt = attempt
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if self.attempt == thisAttempt && self.connection == .connecting {
                self.client.disconnect()
                self.handle(.failed("Timed out"))
            }
        }
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 12 { log.removeFirst(log.count - 12) }
    }

    func disconnect() {
        client.disconnect()
    }

    func savedPIN(for mac: DiscoveredMac) -> String? {
        UserDefaults.standard.string(forKey: pinKey(mac))
    }

    func send(_ events: [InputEvent]) {
        client.send(events)
    }

    private func handle(_ state: GlideClient.State) {
        let wasConnected = (connection == .ready)
        connection = state
        guard case .failed = state else { return }
        if wasConnected {
            // The session worked and then dropped: the PIN is fine, keep it.
            errorMessage = "Lost the connection to your Mac. Tap it to reconnect."
        } else {
            // Most likely a wrong/rotated PIN, or the Mac is asleep or on another network.
            if let mac = currentMac { UserDefaults.standard.removeObject(forKey: pinKey(mac)) }
            errorMessage = "Couldn't connect. Check the PIN on your Mac and that both devices are on the same Wi-Fi."
        }
    }

    private func pinKey(_ mac: DiscoveredMac) -> String { "pin.\(mac.id)" }
}
