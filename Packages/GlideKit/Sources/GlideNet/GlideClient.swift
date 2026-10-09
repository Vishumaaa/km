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
            self?.onChange?(macs)
        }
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
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "glide.client", qos: .userInteractive)

    public init() {}

    public func connect(to endpoint: NWEndpoint, pin: String) {
        disconnect()
        let c = NWConnection(to: endpoint, using: GlideService.parameters(pin: pin))
        connection = c
        onState?(.connecting)
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, self.connection === c else { return }
            switch state {
            case .ready:
                self.onState?(.ready)
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

    public func send(_ events: [InputEvent]) {
        guard let c = connection, !events.isEmpty else { return }
        c.send(content: Wire.encode(events), completion: .contentProcessed { _ in })
    }
}
#endif
