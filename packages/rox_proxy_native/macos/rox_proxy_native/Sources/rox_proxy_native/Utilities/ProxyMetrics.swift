import Foundation
import os.log

/// Thread-safe metrics collection for the proxy server.
/// 
/// Uses a lock for thread-safety. For high-throughput scenarios,
/// consider using atomic operations from Swift Atomics package.
final class ProxyMetrics {
    
    // MARK: - Singleton
    
    static let shared = ProxyMetrics()
    private init() {}
    
    // MARK: - Lock for thread-safety
    
    private let lock = NSLock()
    
    // MARK: - Counters
    
    private var _requestCount: Int64 = 0
    private var _errorCount: Int64 = 0
    private var _bytesReceived: Int64 = 0
    private var _bytesSent: Int64 = 0
    private var _connectRequests: Int64 = 0
    private var _mitmRequests: Int64 = 0
    private var _tunnelRequests: Int64 = 0
    
    /// Total number of HTTP/HTTPS requests processed
    var requestCount: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _requestCount
    }
    
    /// Total number of errors (connection failures, timeouts, etc.)
    var errorCount: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _errorCount
    }
    
    /// Total bytes received from clients
    var bytesReceived: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _bytesReceived
    }
    
    /// Total bytes sent to clients
    var bytesSent: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _bytesSent
    }
    
    /// Total CONNECT (HTTPS) requests
    var connectRequests: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _connectRequests
    }
    
    /// Total MITM decrypted requests
    var mitmRequests: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _mitmRequests
    }
    
    /// Total blind tunnel requests
    var tunnelRequests: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _tunnelRequests
    }
    
    // MARK: - Increment Methods
    
    func incrementRequests() {
        lock.lock()
        defer { lock.unlock() }
        _requestCount += 1
    }
    
    func incrementErrors() {
        lock.lock()
        defer { lock.unlock() }
        _errorCount += 1
    }
    
    func addReceivedBytes(_ bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        _bytesReceived += bytes
    }
    
    func addSentBytes(_ bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        _bytesSent += bytes
    }
    
    func incrementConnectRequests() {
        lock.lock()
        defer { lock.unlock() }
        _connectRequests += 1
    }
    
    func incrementMITMRequests() {
        lock.lock()
        defer { lock.unlock() }
        _mitmRequests += 1
    }
    
    func incrementTunnelRequests() {
        lock.lock()
        defer { lock.unlock() }
        _tunnelRequests += 1
    }
    
    // MARK: - Reset
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _requestCount = 0
        _errorCount = 0
        _bytesReceived = 0
        _bytesSent = 0
        _connectRequests = 0
        _mitmRequests = 0
        _tunnelRequests = 0
        ProxyLogger.proxy.info("Proxy metrics reset")
    }
    
    // MARK: - Uptime
    
    private var _startTime: Date?
    
    var startTime: Date? {
        return _startTime
    }
    
    func setStartTime(_ date: Date) {
        _startTime = date
    }
    
    var uptime: TimeInterval {
        guard let startTime = _startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - JSON Representation
    
    func toJSON() -> [String: Any] {
        return [
            "requests": requestCount,
            "errors": errorCount,
            "bytes_received": bytesReceived,
            "bytes_sent": bytesSent,
            "connect_requests": connectRequests,
            "mitm_requests": mitmRequests,
            "tunnel_requests": tunnelRequests,
            "uptime_seconds": String(format: "%.2f", uptime),
            "status": "running"
        ]
    }
    
    func toPrettyJSON() -> String {
        let json = toJSON()
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            ProxyLogger.error.error("Failed to serialize metrics to JSON: %@", error.localizedDescription)
            return "{}"
        }
    }
}
