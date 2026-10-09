import AppKit
import ApplicationServices
import GlideNet

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var pin: String
    @Published private(set) var status: GlideServer.Status = .stopped
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()

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
        server.onEvents = { events in injector.handle(events) }
        server.onDisconnect = { injector.releaseAll() }
        server.onStatus = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        server.onFailedHandshake = { [weak self] in
            Task { @MainActor in self?.noteFailedHandshake() }
        }
        startServer()

        // Accessibility can be granted at any time in System Settings; keep the UI honest.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.accessibilityTrusted = AXIsProcessTrusted() }
        }
        if !accessibilityTrusted { requestAccessibility() }
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
        } catch {
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
