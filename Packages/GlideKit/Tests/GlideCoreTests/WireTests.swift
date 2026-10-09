import XCTest
@testable import GlideCore

final class WireTests: XCTestCase {
    private let samples: [InputEvent] = [
        .move(dx: 5, dy: -7),
        .move(dx: Int16.min, dy: Int16.max),
        .button(.left, down: true),
        .button(.right, down: false),
        .scroll(dx: 1.5, dy: -22.25, phase: .changed),
        .scroll(dx: 0, dy: 900, phase: .ended),
        .action(.missionControl),
        .action(.spaceRight),
    ]

    func testRoundTrip() {
        var decoder = StreamDecoder()
        let decoded = decoder.feed(Wire.encode(samples))
        XCTAssertEqual(decoded, samples)
    }

    func testByteAtATimeDelivery() {
        var decoder = StreamDecoder()
        var decoded: [InputEvent] = []
        for byte in Wire.encode(samples) {
            decoded += decoder.feed(Data([byte]))
        }
        XCTAssertEqual(decoded, samples)
    }

    func testUnknownMessageIsSkippedNotFatal() {
        var decoder = StreamDecoder()
        let garbage = Data([2, 99, 0])                       // unknown type, well-framed
        let good = Wire.encode([.button(.left, down: true)])
        XCTAssertEqual(decoder.feed(garbage + good), [.button(.left, down: true)])
    }
}
