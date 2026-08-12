import Foundation

/// Payload notified to the UI when a request is suspended at a breakpoint
/// (RF2.3). Pure value type, serializable for the Flutter EventChannel.
struct BreakpointRequest: Sendable {
    /// Breakpoint id — correlates the notification with the decision.
    let id: String
    /// Id of the captured exchange this request belongs to.
    let exchangeId: String
    let method: String
    let url: String
    let headers: [(name: String, value: String)]
    /// Textual body, truncated to the exchange capture limit (RNF1).
    let body: String?
    let timestamp: Date

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "exchangeId": exchangeId,
            "type": "request",
            "method": method,
            "url": url,
            "headers": headers.map { ["name": $0.name, "value": $0.value] },
            "timestamp": Self.dateFormatter.string(from: timestamp),
        ]
        if let body { dict["body"] = body }
        return dict
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
