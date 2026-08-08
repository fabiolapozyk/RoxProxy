import Foundation

// MARK: - Stubs
// Minimal stand-ins for app-only types referenced by MapLocalHandler,
// so the Map Local code can be compiled and tested standalone.

final class BridgeSessionStore: @unchecked Sendable {
    @MainActor func update(_ exchange: CapturedExchange) {}
}

final class ProxyMetrics {
    static let shared = ProxyMetrics()
    private init() {}
    func incrementRequests() {}
    func incrementErrors() {}
    func addSentBytes(_ bytes: Int64) {}
}
