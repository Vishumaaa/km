import AppKit
import ApplicationServices
import GlideCore
import GlideNet

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var pin: String
    @Published private(set) var status: GlideServer.Status = .stopped
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var log: [String] = []

    private let server = GlideServer()
    private let injector = InputInjector()
    private var failedHandshakes = 0
    private var started = false

    private init() {
        let saved = UserDefaults.standard.string(forKey: "pin")
        pin = saved ?? Self.makePIN()
        UserDefaults.standard.set(pin, forKey: "pin")
    }

    func start() {
        guard !started else { return }
        started = true

        let injector = injector
        server.onLog = { [weak self] line in
            print("Glide: \(line)")
            Task { @MainActor in self?.appendLog(line) }
        }
        server.onEvents = { [weak self] events in
            injector.handle(events)
            for case let .button(button, down) in events {
                let line = "button \(button) \(down ? "down" : "up")"
                print("Glide: \(line)")
                Task { @MainActor in self?.appendLog(line) }
            }
        }
        server.onDisconnect = { injector.releaseAll() }
        server.onStatus = { [weak self] status in
            print("Glide: server status \(status)")
            Task { @MainActor in self?.status = status }
        }
        server.onFailedHandshake = { [weak self] in
            print("Glide: a device failed the PIN handshake")
            Task { @MainActor in self?.noteFailedHandshake() }
        }
        startServer()
        print("Glide: PIN is \(pin)")

        // Accessibility can be granted at any time in System Settings; keep the UI honest.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.accessibilityTrusted = AXIsProcessTrusted() }
        }
        if !accessibilityTrusted { requestAccessibility() }
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 8 { log.removeFirst(log.count - 8) }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func newPIN() {
        pin = Self.makePIN()
        UserDefaults.standard.set(pin, forKey: "pin")
        failedHandshakes = 0
        startServer()
    }

    private func startServer() {
        do {
            try server.start(pin: pin, name: Host.current().localizedName ?? "Mac")
            print("Glide: server starting, PIN \(pin)")
        } catch {
            print("Glide: server failed to start: \(error)")
            status = .failed(error.localizedDescription)
        }
    }

    /// Someone who doesn't know the PIN is trying to connect. After a few misses, rotate it.
    private func noteFailedHandshake() {
        failedHandshakes += 1
        if failedHandshakes >= 5 { newPIN() }
    }

    private static func makePIN() -> String {
        String(format: "%06d", Int.random(in: 0..<1_000_000))
    }
}
