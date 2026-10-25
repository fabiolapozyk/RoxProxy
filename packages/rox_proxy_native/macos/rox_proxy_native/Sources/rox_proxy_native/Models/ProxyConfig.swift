import Foundation

/// Immutable snapshot of the proxy configuration that can be hot-reloaded
/// without restarting the server.
///
/// A snapshot is captured at the start of every request and kept for the whole
/// exchange (request + response). In-flight requests and existing tunnels keep
/// the version they started with; new requests read the latest version from
/// `ProxyConfigStore`.
struct ProxyConfig: Sendable {

    /// DOMAIN rules used at CONNECT time to decide whether to MITM a host.
    let domainRules: [DomainRule]

    /// Map Local matcher for the current rule set (only enabled rules).
    let mapLocalMatcher: MapLocalMatcher

    /// Breakpoint matcher for the current rule set.
    let breakpointMatcher: BreakpointMatcher

    /// Global breakpoint toggle. When false no request/response is suspended.
    let breakpointEnabled: Bool

    /// Global HTTPS interception toggle, read at CONNECT time.
    let httpsInterceptionEnabled: Bool

    /// Monotonic configuration version, assigned by `ProxyConfigStore`.
    let version: Int

    /// Returns a copy of this configuration with a new version. Used by the
    /// store to stamp a snapshot without mutating the original.
    func withVersion(_ version: Int) -> ProxyConfig {
        ProxyConfig(
            domainRules: domainRules,
            mapLocalMatcher: mapLocalMatcher,
            breakpointMatcher: breakpointMatcher,
            breakpointEnabled: breakpointEnabled,
            httpsInterceptionEnabled: httpsInterceptionEnabled,
            version: version
        )
    }

    static let empty = ProxyConfig(
        domainRules: [],
        mapLocalMatcher: MapLocalMatcher(rules: []),
        breakpointMatcher: BreakpointMatcher(rules: []),
        breakpointEnabled: false,
        httpsInterceptionEnabled: true,
        version: 0
    )
}
