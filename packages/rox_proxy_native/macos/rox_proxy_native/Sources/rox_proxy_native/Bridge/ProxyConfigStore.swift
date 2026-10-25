import Foundation

/// Thread-safe holder of the current immutable `ProxyConfig` snapshot.
///
/// NIO handlers run on multiple event loops, so the store must be readable
/// synchronously from any thread. Readers get a value copy of an immutable
/// struct; writers replace the whole value under a lock (atomic swap), so a
/// reader never observes a partially applied configuration.
final class ProxyConfigStore: @unchecked Sendable {

    private let lock = NSLock()
    private var config: ProxyConfig

    init(initial: ProxyConfig = .empty) {
        self.config = initial
    }

    /// Returns the current snapshot. Cheap: the struct is copy-on-write and the
    /// matchers are immutable references.
    func current() -> ProxyConfig {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    /// Atomically replaces the configuration and returns the applied snapshot
    /// with the new monotonic version.
    @discardableResult
    func apply(_ newConfig: ProxyConfig) -> ProxyConfig {
        lock.lock()
        let next = newConfig.withVersion(config.version + 1)
        config = next
        lock.unlock()
        return next
    }
}
