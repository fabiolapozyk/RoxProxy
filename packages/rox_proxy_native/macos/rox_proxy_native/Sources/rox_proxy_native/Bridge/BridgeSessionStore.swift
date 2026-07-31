import Foundation
import os.log

/// Drop-in replacement for the old SwiftUI ProxySessionStore.
/// Receives append/update calls from NIO threads (via Task @MainActor)
/// and forwards serialized exchanges to the Flutter EventChannel.
final class BridgeSessionStore: @unchecked Sendable {

    var isRecording: Bool = true

    private let streamHandler: ExchangeStreamHandler
    private let bodyStore: BodyStore

    init(streamHandler: ExchangeStreamHandler, bodyStore: BodyStore) {
        self.streamHandler = streamHandler
        self.bodyStore = bodyStore
    }

    @MainActor
    func append(_ exchange: CapturedExchange) {
        ProxyLogger.http.debug("BridgeSessionStore: appending exchange %{public}@ %{public}@", exchange.method, exchange.url)
        guard isRecording else { 
            ProxyLogger.http.debug("BridgeSessionStore: not recording, skipping append")
            return 
        }
        let refs = bodyStore.store(exchange: exchange)
        streamHandler.send(type: "new", exchange: exchange, bodyRefs: refs)
    }

    @MainActor
    func update(_ exchange: CapturedExchange) {
        ProxyLogger.http.debug("BridgeSessionStore: updating exchange %{public}@ %{public}@", exchange.method, exchange.url)
        let refs = bodyStore.store(exchange: exchange)
        streamHandler.send(type: "update", exchange: exchange, bodyRefs: refs)
    }
}
