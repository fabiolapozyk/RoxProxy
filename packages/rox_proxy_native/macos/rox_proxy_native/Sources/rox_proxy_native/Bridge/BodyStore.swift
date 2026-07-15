import Foundation
import os.log

/// Thread-safe in-memory store for request/response body bytes.
/// Bodies are keyed by UUID string so Flutter can fetch them lazily
/// via the 'fetchBody' MethodChannel call.
final class BodyStore: @unchecked Sendable {

    private let lock = NSLock()
    private var store: [String: Data] = [:]

    /// Stores the request and response bodies of an exchange (if any)
    /// and returns the reference UUIDs assigned to each.
    func store(exchange: CapturedExchange) -> (request: String?, response: String?) {
        ProxyLogger.http.debug("BodyStore: storing bodies for exchange %@ %@", exchange.method, exchange.url)
        let reqRef = storeBodyContent(exchange.requestBody)
        let resRef = storeBodyContent(exchange.responseBody)
        ProxyLogger.http.debug("BodyStore: requestRef=%@, responseRef=%@", reqRef ?? "nil", resRef ?? "nil")
        return (request: reqRef, response: resRef)
    }

    /// Stores a single body Data and returns its reference UUID, or nil if empty.
    private func storeBodyContent(_ content: BodyContent?) -> String? {
        guard let content, let data = content.data, !data.isEmpty else { return nil }
        let ref = UUID().uuidString
        ProxyLogger.http.debug("BodyStore: storing %d bytes with ref %@", data.count, ref)
        lock.withLock { store[ref] = data }
        return ref
    }

    /// Retrieves body bytes by reference. Returns nil if not found.
    func fetch(ref: String) -> Data? {
        let data = lock.withLock { store[ref] }
        ProxyLogger.http.debug("BodyStore: fetching body for ref %@, found=%s", ref, data != nil ? "yes" : "no")
        return data
    }

    /// Releases a single body reference.
    func release(ref: String) {
        ProxyLogger.http.debug("BodyStore: releasing body for ref %@", ref)
        lock.withLock { store.removeValue(forKey: ref) }
    }

    /// Releases all cached bodies.
    func releaseAll() {
        ProxyLogger.http.debug("BodyStore: releasing all bodies")
        lock.withLock { store.removeAll() }
    }
}
