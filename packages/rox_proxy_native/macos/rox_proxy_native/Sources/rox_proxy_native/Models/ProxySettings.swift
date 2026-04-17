import Foundation

struct ProxySettings: Codable, Sendable, Equatable {
    var port: Int = 8080
    var domainRules: [DomainRule] = []
    var breakpoints: [Breakpoint] = []
    var isRecording: Bool = true
    var maxExchanges: Int = 10_000
    var autoStartProxy: Bool = true
    var connectionTimeoutSeconds: Int = 30
    var setSystemProxy: Bool = true
}
