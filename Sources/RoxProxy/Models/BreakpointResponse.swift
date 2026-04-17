import Foundation

/// Represents the user's response to a breakpoint from Flutter to backend via WebSocket
struct BreakpointResponse: Codable {
    let breakpointId: UUID
    let action: BreakpointAction
    let modifiedMethod: String?
    let modifiedUrl: String?
    let modifiedHeaders: [String: String]?
    let modifiedBody: String?
    let timestamp: Date
    
    enum BreakpointAction: String, Codable {
        case proceed
        case cancel
    }
    
    init(
        breakpointId: UUID,
        action: BreakpointAction,
        modifiedMethod: String? = nil,
        modifiedUrl: String? = nil,
        modifiedHeaders: [String: String]? = nil,
        modifiedBody: String? = nil,
        timestamp: Date = Date()
    ) {
        self.breakpointId = breakpointId
        self.action = action
        self.modifiedMethod = modifiedMethod
        self.modifiedUrl = modifiedUrl
        self.modifiedHeaders = modifiedHeaders
        self.modifiedBody = modifiedBody
        self.timestamp = timestamp
    }
}