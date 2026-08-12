import Foundation
import FlutterMacOS
import os.log

/// FlutterStreamHandler for the 'com.roxproxy/breakpointEvents' EventChannel
/// (RF6.1). Receives breakpoint notifications from the core and pushes them to
/// the Flutter Dart side via the event sink.
///
/// Also implements `BreakpointHandler.Notifier`: the sink presence is the
/// "UI available" signal the core uses to decide whether it may suspend a
/// request (RF3.3).
final class BreakpointStreamHandler: NSObject, FlutterStreamHandler, BreakpointHandler.Notifier {

    private var eventSink: FlutterEventSink?

    // MARK: - BreakpointHandler.Notifier

    /// True while the Dart side is listening. The core never suspends without
    /// an active sink (degradazione graziosa).
    var isAvailable: Bool { eventSink != nil }

    func requestSuspended(_ request: BreakpointRequest) {
        guard let sink = eventSink else { return }
        let dict: [String: Any] = [
            "type": "request",
            "request": request.toDictionary(),
        ]
        sink(dict)
    }

    func responseSuspended(_ response: ResponseBreakpoint) {
        guard let sink = eventSink else { return }
        let dict: [String: Any] = [
            "type": "response",
            "response": response.toDictionary(),
        ]
        sink(dict)
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        ProxyLogger.breakpoint.debug("Breakpoint stream handler: onListen called")
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        ProxyLogger.breakpoint.debug("Breakpoint stream handler: onCancel called")
        eventSink = nil
        return nil
    }
}
