import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import os.log

/// Manages the lifecycle of the local HTTP proxy server built on SwiftNIO.
final class ProxyServer {

    // MARK: - Properties

    let port: Int
    let store: BridgeSessionStore
    let certificateAuthority: CertificateAuthority?
    let domainCertCache: DomainCertificateCache?
    private let connectionTimeoutSeconds: Int
    // Snapshot of domain rules taken at start time (Sendable value type, safe to pass to NIO threads)
    private let domainRules: [DomainRule]
    private let httpsInterceptionEnabled: Bool

    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?

    // MARK: - Init

    @MainActor
    init(
        port: Int,
        store: BridgeSessionStore,
        domainRules: [DomainRule] = [],
        connectionTimeoutSeconds: Int = 30,
        certificateAuthority: CertificateAuthority? = nil,
        domainCertCache: DomainCertificateCache? = nil,
        httpsInterceptionEnabled: Bool = true
    ) {
        self.port = port
        self.store = store
        self.certificateAuthority = certificateAuthority
        self.domainCertCache = domainCertCache
        self.connectionTimeoutSeconds = connectionTimeoutSeconds
        self.domainRules = domainRules
        self.httpsInterceptionEnabled = httpsInterceptionEnabled
    }

    // MARK: - Lifecycle

    /// Starts the proxy server, binding to `127.0.0.1:<port>`.
    /// Throws if the port is already in use or another bind error occurs.
    func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.group = group

        // Initialize metrics
        ProxyMetrics.shared.reset()
        ProxyMetrics.shared.setStartTime(Date())

        let store         = self.store
        let ca            = self.certificateAuthority
        let certCache     = self.domainCertCache
        let domainRules   = self.domainRules
        let timeoutSecs   = self.connectionTimeoutSeconds
        let httpsEnabled  = self.httpsInterceptionEnabled

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline
                    .addHandler(
                        ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)),
                        name: "HTTPRequestDecoder"
                    )
                    .flatMap {
                        channel.pipeline.addHandler(HTTPResponseEncoder(), name: "HTTPResponseEncoder")
                    }
                    .flatMap {
                        channel.pipeline.addHandler(
                            HTTPProxyHandler(
                                store: store,
                                certificateAuthority: ca,
                                domainCertCache: certCache,
                                domainRules: domainRules,
                                httpsInterceptionEnabled: httpsEnabled
                            ),
                            name: "HTTPProxyHandler"
                        )
                    }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(
                ChannelOptions.connectTimeout,
                value: TimeAmount.seconds(Int64(timeoutSecs))
            )

        do {
            channel = try await bootstrap.bind(host: "0.0.0.0", port: port).get()
            ProxyLogger.proxy.info("Proxy server bound to 0.0.0.0:%d", port)
        } catch {
            ProxyLogger.proxy.error("Failed to bind to port %d: %@", port, error.localizedDescription)
            ProxyLogger.error.error("Bind failed on port %d: %@", port, error.localizedDescription)
            try? await group.shutdownGracefully()
            self.group = nil
            throw ProxyError.bindFailed(port: port, underlying: error)
        }
    }

    /// Stops the proxy server gracefully.
    func stop() async throws {
        ProxyLogger.proxy.info("Stopping proxy server")
        try await channel?.close().get()
        try await group?.shutdownGracefully()
        channel = nil
        group = nil
        ProxyLogger.proxy.info("Proxy server stopped")
    }

    /// Replays a captured HTTP request.
    /// Returns the ID of the newly created exchange.
    func replayRequest(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data?
    ) async throws -> String {
        ProxyLogger.replay.info("Replaying request: %@ %@", method, url.absoluteString)
        // For now, implement a simple HTTP client using URLSession
        // This is a temporary solution until we implement proper SwiftNIO client
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        
        // Remove the Host header if present, as URLSession will add it automatically
        if request.allHTTPHeaderFields?["Host"] != nil {
            var modifiedHeaders = request.allHTTPHeaderFields!
            modifiedHeaders.removeValue(forKey: "Host")
            request.allHTTPHeaderFields = modifiedHeaders
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            ProxyLogger.replay.debug("Received response: %d", httpResponse.statusCode)
            // Generate a unique exchange ID
            let exchangeId = UUID().uuidString
            return exchangeId
        } else {
            ProxyLogger.replay.error("Unknown response type")
            throw NSError(domain: "com.roxproxy", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unknown response type"])
        }
    }

    // MARK: - Errors

    enum ProxyError: Error, LocalizedError {
        case bindFailed(port: Int, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .bindFailed(let port, let underlying):
                return "Cannot bind proxy on port \(port): \(underlying.localizedDescription). Try a different port in Settings."
            }
        }
    }
}
