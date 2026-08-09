import Foundation

// MARK: - Stub
// Minimal stand-in for the Flutter-dependent ExchangeStreamHandler,
// so BridgeSessionStore can be compiled and tested standalone.
// Mirrors the `send(type:exchange:bodyRefs:)` internal API of the real handler.

final class ExchangeStreamHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [(type: String, url: String)] = []

    var sentEvents: [(type: String, url: String)] {
        lock.withLock { _sent }
    }

    var sentCount: Int {
        lock.withLock { _sent.count }
    }

    func send(
        type: String,
        exchange: CapturedExchange,
        bodyRefs: (request: String?, response: String?)
    ) {
        lock.withLock { _sent.append((type: type, url: exchange.url)) }
    }
}
