import Foundation

/// Converts a CapturedExchange to a [String: Any?] dictionary
/// suitable for passing over the Flutter platform channel.
enum ExchangeSerializer {

    static func serialize(
        _ exchange: CapturedExchange,
        bodyRefs: (request: String?, response: String?)
    ) -> [String: Any?] {
        return [
            "id":               exchange.id.uuidString,
            "startTime":        exchange.startTime.timeIntervalSince1970 * 1000,
            "endTime":          exchange.endTime.map { $0.timeIntervalSince1970 * 1000 } as Any?,
            "method":           exchange.method,
            "url":              exchange.url,
            "scheme":           exchange.scheme,
            "host":             exchange.host,
            "port":             exchange.port,
            "path":             exchange.path,
            "requestHeaders":   serializeHeaders(exchange.requestHeaders),
            "requestBodyRef":   bodyRefs.request as Any?,
            "requestSize":      exchange.requestSize,
            "statusCode":       exchange.statusCode as Any?,
            "statusMessage":    exchange.statusMessage as Any?,
            "responseHeaders":  exchange.responseHeaders.map { serializeHeaders($0) } as Any?,
            "responseBodyRef":  bodyRefs.response as Any?,
            "responseSize":     exchange.responseSize as Any?,
            "isHTTPS":          exchange.isHTTPS,
            "isMITMDecrypted":  exchange.isMITMDecrypted,
            "isMapLocal":       exchange.isMapLocal,
            "state":            stateString(exchange.state),
            "errorMessage":     errorMessage(exchange.state) as Any?,
        ]
    }

    private static func serializeHeaders(
        _ headers: [(name: String, value: String)]
    ) -> [[String: String]] {
        headers.map { ["name": $0.name, "value": $0.value] }
    }

    private static func stateString(_ state: CapturedExchange.ExchangeState) -> String {
        switch state {
        case .inProgress: return "inProgress"
        case .completed:  return "completed"
        case .failed:     return "failed"
        }
    }

    private static func errorMessage(_ state: CapturedExchange.ExchangeState) -> String? {
        if case .failed(let msg) = state { return msg }
        return nil
    }
}
