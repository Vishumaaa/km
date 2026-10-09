import Foundation

/// Binary wire format. Every message is length-prefixed so it can ride a byte stream:
///
///     [len u8][type u8][payload...]       (len counts type + payload)
///
/// Payloads are little-endian.
public enum Wire {
    enum Kind: UInt8 {
        case move = 1, button = 2, scroll = 3, action = 4
    }

    public static func encode(_ event: InputEvent) -> [UInt8] {
        var body: [UInt8] = []
        switch event {
        case let .move(dx, dy):
            body.append(Kind.move.rawValue)
            body += bytes(of: dx)
            body += bytes(of: dy)
        case let .button(button, down):
            body.append(Kind.button.rawValue)
            body.append(button.rawValue)
            body.append(down ? 1 : 0)
        case let .scroll(dx, dy, phase):
            body.append(Kind.scroll.rawValue)
            body.append(phase.rawValue)
            body += bytes(of: dx.bitPattern)
            body += bytes(of: dy.bitPattern)
        case let .action(action):
            body.append(Kind.action.rawValue)
            body.append(action.rawValue)
        }
        return [UInt8(body.count)] + body
    }

    public static func encode(_ events: [InputEvent]) -> Data {
        var out: [UInt8] = []
        for event in events { out += encode(event) }
        return Data(out)
    }

    /// Decodes one message body (without the length prefix). Returns nil if malformed.
    static func decode(body: ArraySlice<UInt8>) -> InputEvent? {
        guard let first = body.first, let kind = Kind(rawValue: first) else { return nil }
        let p = Array(body.dropFirst())
        switch kind {
        case .move:
            guard p.count == 4 else { return nil }
            return .move(dx: Int16(bitPattern: UInt16(p[0]) | UInt16(p[1]) << 8),
                         dy: Int16(bitPattern: UInt16(p[2]) | UInt16(p[3]) << 8))
        case .button:
            guard p.count == 2, let b = MouseButton(rawValue: p[0]) else { return nil }
            return .button(b, down: p[1] != 0)
        case .scroll:
            guard p.count == 9, let phase = ScrollPhase(rawValue: p[0]) else { return nil }
            return .scroll(dx: Float(bitPattern: u32(p, 1)),
                           dy: Float(bitPattern: u32(p, 5)),
                           phase: phase)
        case .action:
            guard p.count == 1, let a = SystemAction(rawValue: p[0]) else { return nil }
            return .action(a)
        }
    }

    private static func bytes(of v: Int16) -> [UInt8] {
        let u = UInt16(bitPattern: v)
        return [UInt8(u & 0xff), UInt8(u >> 8)]
    }

    private static func bytes(of v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)]
    }

    private static func u32(_ p: [UInt8], _ i: Int) -> UInt32 {
        UInt32(p[i]) | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]) << 16 | UInt32(p[i + 3]) << 24
    }
}

/// Reassembles messages from an arbitrarily chunked byte stream.
public struct StreamDecoder {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func feed(_ data: Data) -> [InputEvent] {
        buffer += data
        var events: [InputEvent] = []
        var index = 0
        while index < buffer.count {
            let len = Int(buffer[index])
            guard len > 0 else { index += 1; continue }          // skip stray zero byte
            guard index + 1 + len <= buffer.count else { break } // wait for the rest
            let body = buffer[(index + 1)..<(index + 1 + len)]
            if let event = Wire.decode(body: body) { events.append(event) }
            index += 1 + len
        }
        buffer.removeFirst(index)
        return events
    }
}
