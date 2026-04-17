import Foundation
import FlutterMacOS

/// FlutterStreamHandler for the 'com.roxproxy/breakpoints' EventChannel.
/// Receives breakpoint events from ProxyMethodHandler and pushes them to Flutter.
final class BreakpointStreamHandler: NSObject, FlutterStreamHandler {

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

    /// Called from ProxyMethodHandler when a breakpoint is hit.
    @MainActor
    func sendBreakpointEvent(data: [String: Any]) {
        print("DEBUG: BreakpointStreamHandler.sendBreakpointEvent called")
        print("DEBUG: Event data: \(data)")
        
        if eventSink == nil {
            print("DEBUG: ERROR: eventSink is nil! No Flutter listener for breakpoint events.")
            return
        }
        
        print("DEBUG: Sending breakpoint event to Flutter via event sink...")
        eventSink?(data as Any)
        print("DEBUG: Breakpoint event sent successfully")
    }
}