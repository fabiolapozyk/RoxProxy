import Foundation
import FlutterMacOS
import os.log

/// FlutterStreamHandler for the 'com.roxproxy/exchanges' EventChannel.
/// Receives serialized exchange events from BridgeSessionStore and pushes
/// them to the Flutter Dart side via the event sink.
final class ExchangeStreamHandler: NSObject, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        ProxyLogger.proxy.debug("Exchange stream handler: onListen called")
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        ProxyLogger.proxy.debug("Exchange stream handler: onCancel called")
        eventSink = nil
        return nil
    }

    // MARK: - Internal API

    /// Called from BridgeSessionStore (which ensures we're on MainActor).
    func send(
        type: String,
        exchange: CapturedExchange,
        bodyRefs: (request: String?, response: String?)
    ) {
        ProxyLogger.http.debug("Sending exchange event to Flutter: type=%@, url=%@", type, exchange.url)
        guard let sink = eventSink else {
            ProxyLogger.http.error("Exchange stream handler: eventSink is nil, cannot send event")
            return 
        }
        let dict: [String: Any?] = [
            "type":     type,
            "exchange": ExchangeSerializer.serialize(exchange, bodyRefs: bodyRefs),
        ]
        sink(dict as Any)
    }
}
