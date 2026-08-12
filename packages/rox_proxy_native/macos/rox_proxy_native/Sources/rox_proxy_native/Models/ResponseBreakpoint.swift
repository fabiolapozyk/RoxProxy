import Foundation

/// Payload notified to the UI when a response is suspended at a breakpoint.
/// Pure value type, serializable for the Flutter EventChannel.
struct ResponseBreakpoint: Sendable {
    /// Breakpoint id — correlates the notification with the decision.
    let id: String
    /// Id of the captured exchange this response belongs to.
    let exchangeId: String
    let method: String
    let url: String
    let statusCode: Int
    let statusMessage: String?
    let headers: [(name: String, value: String)]
    /// Textual body, truncated to the exchange capture limit (RNF1).
    let body: String?
    let timestamp: Date

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "exchangeId": exchangeId,
            "type": "response",
            "method": method,
            "url": url,
            "statusCode": statusCode,
            "headers": headers.map { ["name": $0.name, "value": $0.value] },
            "timestamp": Self.dateFormatter.string(from: timestamp),
        ]
        if let statusMessage { dict["statusMessage"] = statusMessage }
        if let body { dict["body"] = body }
        return dict
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
