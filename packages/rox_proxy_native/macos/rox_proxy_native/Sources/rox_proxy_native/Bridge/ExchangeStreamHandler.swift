import Foundation
import FlutterMacOS

/// FlutterStreamHandler for the 'com.roxproxy/exchanges' EventChannel.
/// Receives serialized exchange events from BridgeSessionStore and pushes
/// them to the Flutter Dart side via the event sink.
final class ExchangeStreamHandler: NSObject, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
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
        guard let sink = eventSink else { return }
        let dict: [String: Any?] = [
            "type":     type,
            "exchange": ExchangeSerializer.serialize(exchange, bodyRefs: bodyRefs),
        ]
        sink(dict as Any)
    }

    /// Called from ProxyMethodHandler when a breakpoint is hit.
    func sendEvent(type: String, data: [String: Any]) {
        guard let sink = eventSink else { return }
        var dict = data
        dict["type"] = type
        sink(dict as Any)
    }
}
