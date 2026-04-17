import Foundation

enum BreakpointTrigger: String, Codable, Sendable {
    case request   // Pause before sending request to server
    case response  // Pause before sending response to client
    case both      // Pause for both request and response
}

struct Breakpoint: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var urlPattern: String  // URL pattern to match (can include query params)
    var trigger: BreakpointTrigger
    var isEnabled: Bool

    init(id: UUID = UUID(), urlPattern: String, trigger: BreakpointTrigger = .both, isEnabled: Bool = true) {
        self.id = id
        self.urlPattern = urlPattern
        self.trigger = trigger
        self.isEnabled = isEnabled
    }

    /// Check if this breakpoint matches the given URL
    func matches(url: String) -> Bool {
        guard isEnabled else { return false }
        
        // Simple exact match for now
        // Could be enhanced with pattern matching (wildcards, regex)
        return url == urlPattern
    }
}