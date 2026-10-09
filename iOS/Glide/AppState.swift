import SwiftUI
import GlideCore
import GlideNet

@MainActor
final class AppState: ObservableObject {
    @Published var macs: [DiscoveredMac] = []
    @Published var connection: GlideClient.State = .idle
    @Published var errorMessage: String?
    @Published var tuning: Tuning = Tuning.load() {
        didSet { tuning.save() }
    }

    var isConnected: Bool { connection == .ready }

    private let browser = GlideBrowser()
    private let client = GlideClient()
    private var currentMac: DiscoveredMac?

    init() {
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
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if self.connection == .connecting {
                self.client.disconnect()
                self.handle(.failed("Timed out"))
            }
        }
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
        connection = state
        if case .failed = state {
            // Most likely a wrong/rotated PIN, or the Mac is asleep or on another network.
            if let mac = currentMac { UserDefaults.standard.removeObject(forKey: pinKey(mac)) }
            errorMessage = "Couldn't connect. Check the PIN on your Mac and that both devices are on the same Wi-Fi."
        }
    }

    private func pinKey(_ mac: DiscoveredMac) -> String { "pin.\(mac.id)" }
}
