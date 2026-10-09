#if canImport(Network)
import Foundation
import Network
import GlideCore

public struct DiscoveredMac: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint
}

/// iPhone side: finds Macs advertising Glide on the local network.
public final class GlideBrowser: @unchecked Sendable {
    public var onChange: (@Sendable ([DiscoveredMac]) -> Void)?
    public var onLog: (@Sendable (String) -> Void)?
    private var browser: NWBrowser?

    public init() {}

    public func start() {
        stop()
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: GlideService.bonjourType, domain: nil), using: parameters)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let macs = results.compactMap { result -> DiscoveredMac? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return DiscoveredMac(id: name, name: name, endpoint: result.endpoint)
            }.sorted { $0.name < $1.name }
            self?.onLog?("found \(macs.count) Mac(s): \(macs.map(\.name))")
            self?.onChange?(macs)
        }
        b.stateUpdateHandler = { [weak self] state in self?.onLog?("browser: \(state)") }
        b.start(queue: .main)
        browser = b
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }
}

/// iPhone side: one authenticated connection to a Mac. Callbacks may fire on any thread.
public final class GlideClient: @unchecked Sendable {
    public enum State: Equatable {
        case idle, connecting, ready, failed(String)
    }

    public var onState: (@Sendable (State) -> Void)?
    /// Human-readable trace of every connection state change, for on-screen debugging.
    public var onLog: (@Sendable (String) -> Void)?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "glide.client", qos: .userInteractive)

    public init() {}

    public func connect(to endpoint: NWEndpoint, pin: String) {
        disconnect()
        let c = NWConnection(to: endpoint, using: GlideService.parameters(pin: pin))
        connection = c
        onLog?("connecting to \(endpoint)")
        onState?(.connecting)
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, self.connection === c else { return }
            self.onLog?("connection: \(state)")
            switch state {
            case .ready:
                self.onState?(.ready)
                self.watchForClose(c)
            case let .failed(error):
                self.connection = nil
                self.onState?(.failed(error.localizedDescription))
            case let .waiting(error):
                // No route / refused. Don't sit in limbo; let the user retry.
                self.connection = nil
                c.cancel()
                self.onState?(.failed(error.localizedDescription))
            case .cancelled:
                if self.connection === c { self.connection = nil }
                self.onState?(.idle)
            default:
                break
            }
        }
        c.start(queue: queue)
    }

    public func disconnect() {
        guard let c = connection else { return }
        connection = nil
        c.cancel()
        onState?(.idle)
    }

    /// We never expect data from the Mac. Reading anyway is how we find out it closed the
    /// connection (quit, slept, rotated its PIN), instead of typing into a dead trackpad.
    private func watchForClose(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64) { [weak self, weak c] _, _, isComplete, error in
            guard let self, let c, self.connection === c else { return }
            if isComplete || error != nil {
                self.connection = nil
                c.cancel()
                self.onState?(.failed("The Mac closed the connection."))
            } else {
                self.watchForClose(c)
            }
        }
    }

    public func send(_ events: [InputEvent]) {
        guard let c = connection, !events.isEmpty else { return }
        c.send(content: Wire.encode(events), completion: .contentProcessed { _ in })
    }
}
#endif
