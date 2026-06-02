import Foundation
import NIOCore
import NIOPosix
@testable import RoxProxy

/// Central test harness for managing proxy lifecycle during tests.
/// 
/// Provides:
/// - Automatic port selection for parallel test execution
/// - Proxy server start/stop with test-specific configuration
/// - MITM certificate generation for HTTPS tests
/// - Helper methods for making HTTP requests through the proxy
/// - Automatic cleanup of temporary resources
///
@MainActor
final class TestHarness {
    
    // MARK: - Configuration
    
    /// Default port range for test proxy instances
    static let defaultPortRange = 18000...19000
    
    /// Shared certificate authority for all tests (thread-safe access)
    private static var _sharedCertificateAuthority: CertificateAuthority?
    private static let sharedCAQueue = DispatchQueue(label: "test.harness.ca", attributes: .concurrent)
    
    static var sharedCertificateAuthority: CertificateAuthority? {
        get { sharedCAQueue.sync { _sharedCertificateAuthority } }
        set { sharedCAQueue.sync(flags: .barrier) { _sharedCertificateAuthority = newValue } }
    }
    
    /// Shared domain certificate cache for MITM tests
    private static var _sharedDomainCertCache: DomainCertificateCache?
    static var sharedDomainCertCache: DomainCertificateCache? {
        get { sharedCAQueue.sync { _sharedDomainCertCache } }
        set { sharedCAQueue.sync(flags: .barrier) { _sharedDomainCertCache = newValue } }
    }
    
    // MARK: - Instance Properties
    
    let port: Int
    let proxyServer: ProxyServer
    let store: ProxySessionStore
    let settingsStore: SettingsStore
    
    private let ca: CertificateAuthority
    private let certCache: DomainCertificateCache
    private let tempDir: URL?
    
    private var _isRunning: Bool = false
    
    var isRunning: Bool {
        _isRunning
    }
    
    // MARK: - Initialization
    
    /// Creates a test harness with automatic port selection
    /// - Parameter portRange: Range of ports to try for the proxy server
    init(portRange: ClosedRange<Int> = defaultPortRange) throws {
        // Find an available port
        let availablePort = try Self.findAvailablePort(in: portRange)
        self.port = availablePort
        
        // Create stores (use real stores for integration testing)
        self.store = ProxySessionStore()
        self.settingsStore = SettingsStore()
        
        // Get or create CA
        let (ca, certCache, tempDir) = try Self.getOrCreateCA()
        self.ca = ca
        self.certCache = certCache
        self.tempDir = tempDir
        
        // Create proxy server with test configuration
        self.proxyServer = ProxyServer(
            port: availablePort,
            store: store,
            settingsStore: settingsStore,
            certificateAuthority: ca,
            domainCertCache: certCache
        )
        
        // Initialize static shared instances if not already set
        if TestHarness.sharedCertificateAuthority == nil {
            TestHarness.sharedCertificateAuthority = ca
            TestHarness.sharedDomainCertCache = certCache
        }
    }
    
    // MARK: - Lifecycle
    
    /// Starts the proxy server
    @MainActor
    func start() async throws {
        guard !_isRunning else { return }
        
        try await proxyServer.start()
        
        _isRunning = true
        store.proxyState = .running(port: port)
    }
    
    /// Stops the proxy server
    @MainActor
    func stop() async throws {
        guard _isRunning else { return }
        
        try await proxyServer.stop()
        
        _isRunning = false
        store.proxyState = .stopped
    }
    
    /// Resets the harness state (clears captured exchanges, resets stores)
    @MainActor
    func reset() {
        store.clear()
        settingsStore.settings = ProxySettings()
        settingsStore.isCATrusted = false
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Clean up temporary directory if we created it
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    /// Resets all shared state (for use between test suites)
    static func resetSharedState() {
        sharedCAQueue.sync(flags: .barrier) {
            _sharedCertificateAuthority = nil
            _sharedDomainCertCache = nil
        }
    }
    
    // MARK: - Static Helpers
    
    /// Returns or creates a shared certificate authority for tests
    private static func getOrCreateCA() throws -> (CertificateAuthority, DomainCertificateCache, URL?) {
        if let ca = sharedCertificateAuthority, let cache = sharedDomainCertCache {
            return (ca, cache, nil)
        }
        
        // Create a temporary directory for CA files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoxProxyTestCA")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create and save CA using the temp directory
        let certURL = tempDir.appendingPathComponent("ca-cert.der")
        let keyURL = tempDir.appendingPathComponent("ca-key.pem")
        
        // For testing, we'll use a simple approach - generate CA in temp dir
        // We need to access the private method, so we'll use a test helper
        let ca = try CertificateAuthority.loadOrGenerate()
        
        let cache = DomainCertificateCache(ca: ca)
        
        // Store in shared state
        sharedCertificateAuthority = ca
        sharedDomainCertCache = cache
        
        return (ca, cache, tempDir)
    }
    
    /// Finds an available port in the given range using socket binding
    static func findAvailablePort(in range: ClosedRange<Int>) throws -> Int {
        var serverSocket: Int32 = -1
        
        for port in range {
            serverSocket = socket(AF_INET, SOCK_STREAM, 0)
            guard serverSocket >= 0 else { continue }
            
            defer {
                if serverSocket >= 0 {
                    close(serverSocket)
                    serverSocket = -1
                }
            }
            
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(port).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            
            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
                }
            }
            
            if bindResult >= 0 {
                // Successfully bound, this port is available
                // Close and return
                close(serverSocket)
                serverSocket = -1
                return port
            }
        }
        
        throw TestHarnessError.noAvailablePort(in: range)
    }
    
    // MARK: - HTTP Request Helpers
    
    /// Makes an HTTP request through the proxy
    /// - Parameters:
    ///   - url: The target URL
    ///   - method: HTTP method (default: GET)
    ///   - body: Request body (optional)
    ///   - headers: Additional headers (optional)
    /// - Returns: HTTP response status code and body string
    func makeRequest(
        to url: String,
        method: String = "GET",
        body: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> (statusCode: Int, body: String) {
        // Validate URL
        guard let urlComponents = URLComponents(string: url) else {
            throw TestHarnessError.invalidURL(url)
        }
        
        guard let requestURL = urlComponents.url else {
            throw TestHarnessError.invalidURL(url)
        }
        
        // Build request
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        
        // Add headers
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        // Add body
        if let body = body {
            request.httpBody = body.data(using: .utf8)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        // Configure proxy using URLComponents
        var proxyComponents = URLComponents()
        proxyComponents.scheme = "http"
        proxyComponents.host = "127.0.0.1"
        proxyComponents.port = port
        
        guard let proxyURL = proxyComponents.url else {
            throw TestHarnessError.proxyNotRunning
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPSEnable": 1,
            "HTTPSProxy": proxyURL.absoluteString,
            "HTTPProxy": proxyURL.absoluteString,
            "HTTPSPort": port,
            "HTTPPort": port
        ]
        
        let session = URLSession(configuration: config)
        
        // Make request
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            return (httpResponse.statusCode, bodyString)
        } else {
            throw TestHarnessError.invalidResponse
        }
    }
    
    // MARK: - Errors
    
    enum TestHarnessError: Error, LocalizedError {
        case noAvailablePort(in: ClosedRange<Int>)
        case invalidResponse
        case proxyNotRunning
        case invalidURL(String)
        case portBindingFailed(port: Int, error: Error)
        
        var errorDescription: String? {
            switch self {
            case .noAvailablePort(let range):
                return "No available port found in range: \(range)"
            case .invalidResponse:
                return "Received invalid HTTP response"
            case .proxyNotRunning:
                return "Proxy server is not running"
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            case .portBindingFailed(let port, let error):
                return "Failed to bind to port \(port): \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Test Lifecycle Helper

/// Helper to manage test harness lifecycle with async/await
/// Automatically starts and stops the proxy for each test.
@MainActor
final class TestProxyContext {
    let harness: TestHarness
    
    init(portRange: ClosedRange<Int> = TestHarness.defaultPortRange) throws {
        self.harness = try TestHarness(portRange: portRange)
    }
    
    /// Runs a test with automatic proxy start/stop
    /// - Parameter test: The test closure to execute
    func runTest(_ test: () async throws -> Void) async throws {
        try await harness.start()
        try await test()
        try? await harness.stop()
    }
    
    deinit {
        // Note: In a real app, you might want to ensure cleanup
        // For tests, we rely on the test lifecycle
    }
}
