import Foundation

/// Represents a breakpoint request sent from backend to Flutter via WebSocket
struct BreakpointRequest: Codable {
    let id: UUID
    let exchangeId: UUID
    let type: BreakpointType
    let method: String
    let url: String
    let headers: [String: String]
    let body: String?
    let isRequest: Bool
    let timestamp: Date
    
    enum BreakpointType: String, Codable {
        case request
        case response
    }
    
    init(
        id: UUID = UUID(),
        exchangeId: UUID,
        type: BreakpointType,
        method: String,
        url: String,
        headers: [String: String],
        body: String?,
        isRequest: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.exchangeId = exchangeId
        self.type = type
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.isRequest = isRequest
        self.timestamp = timestamp
    }
}