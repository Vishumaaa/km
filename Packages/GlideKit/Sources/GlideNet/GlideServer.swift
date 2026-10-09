#if canImport(Network)
import Foundation
import Network
import GlideCore

/// Mac side: advertises over Bonjour and accepts one authenticated phone at a time.
/// All callbacks fire on an internal serial queue; hop to the main actor for UI work.
public final class GlideServer: @unchecked Sendable {
    public enum Status: Equatable {
        case stopped, listening, connected, failed(String)
    }

    public var onEvents: (@Sendable ([InputEvent]) -> Void)?
    public var onDisconnect: (@Sendable () -> Void)?
    public var onStatus: (@Sendable (Status) -> Void)?
    /// A peer connected but failed the TLS handshake (wrong PIN or not a Glide client).
    public var onFailedHandshake: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "glide.server", qos: .userInteractive)
    private var listener: NWListener?
    private var active: NWConnection?
    private var decoder = StreamDecoder()

    public init() {}

    public func start(pin: String, name: String) throws {
        let l = try NWListener(using: GlideService.parameters(pin: pin))
        l.service = NWListener.Service(name: name, type: GlideService.bonjourType)
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onStatus?(.listening)
            case let .failed(error): self?.onStatus?(.failed(error.localizedDescription))
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        queue.async {
            self.teardown()
            self.listener = l
            l.start(queue: self.queue)
        }
    }

    public func stop() {
        queue.async {
            self.teardown()
            self.onStatus?(.stopped)
        }
    }

    private func teardown() {
        listener?.cancel()
        listener = nil
        if let c = active {
            active = nil
            c.cancel()
            onDisconnect?()
        }
    }

    private func accept(_ connection: NWConnection) {
        var authenticated = false

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                authenticated = true
                // Only a peer that completed the PIN handshake may replace the current session.
                if let old = self.active {
                    self.active = nil
                    old.cancel()
                    self.onDisconnect?()
                }
                self.active = connection
                self.decoder = StreamDecoder()
                self.onStatus?(.connected)
                self.receive(on: connection)
            case .failed, .cancelled:
                if case .failed = state, !authenticated { self.onFailedHandshake?() }
                if self.active === connection {
                    self.active = nil
                    self.onDisconnect?()
                    self.onStatus?(.listening)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)

        // Don't let half-open, unauthenticated sockets linger.
        queue.asyncAfter(deadline: .now() + 5) { [weak connection] in
            if !authenticated { connection?.cancel() }
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection, self.active === connection else { return }
            if let data, !data.isEmpty {
                let events = self.decoder.feed(data)
                if !events.isEmpty { self.onEvents?(events) }
            }
            if error == nil && !isComplete {
                self.receive(on: connection)
            } else {
                connection.cancel()
            }
        }
    }
}
#endif
