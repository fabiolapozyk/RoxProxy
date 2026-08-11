import Foundation

/// Centralizes the breakpoint trigger conditions (RF1.3).
///
/// v1: configured in code — every request triggers when the feature is
/// enabled, with an optional method filter. Host/path are available for
/// future rule-based conditions.
struct BreakpointMatcher: Sendable {

    /// Global on/off switch for the feature.
    let isEnabled: Bool
    /// Non-empty set restricts breakpoints to these HTTP methods
    /// (compared uppercased). Empty set = all methods.
    let methodFilter: Set<String>

    init(isEnabled: Bool, methodFilter: Set<String> = []) {
        self.isEnabled = isEnabled
        self.methodFilter = methodFilter
    }

    func shouldBreakpointRequest(method: String, host: String, path: String) -> Bool {
        guard isEnabled else { return false }
        if methodFilter.isEmpty { return true }
        return methodFilter.contains(method.uppercased())
    }
}
