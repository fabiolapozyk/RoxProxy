import Foundation
import NIOSSL
import os.log

/// Thread-safe cache of per-domain TLS certificates signed by the root CA.
///
/// Uses a lock rather than an actor so NIO event-loop threads can call
/// `certificate(for:)` synchronously without async/await bridging.
final class DomainCertificateCache: @unchecked Sendable {

    private let ca: CertificateAuthority
    private let lock = NSLock()
    private var _cache: [String: (cert: NIOSSLCertificate, key: NIOSSLPrivateKey)] = [:]

    init(ca: CertificateAuthority) {
        self.ca = ca
    }

    /// Returns a (cert, key) pair for the given host, generating and caching it if needed.
    func certificate(for host: String) throws -> (NIOSSLCertificate, NIOSSLPrivateKey) {
        lock.lock()
        defer { lock.unlock() }
        if let cached = _cache[host] {
            ProxyLogger.certificate.debug("Cache hit for domain certificate: %{public}@", host)
            return (cached.cert, cached.key)
        }
        ProxyLogger.certificate.debug("Cache miss for domain certificate: %{public}@, generating", host)
        let pair = try ca.generateDomainCertificate(for: host)
        _cache[host] = (cert: pair.0, key: pair.1)
        return pair
    }

    /// Evicts all cached certificates (e.g. after CA regeneration).
    func clearCache() {
        ProxyLogger.certificate.debug("Clearing domain certificate cache")
        lock.lock()
        defer { lock.unlock() }
        _cache.removeAll()
    }
}
