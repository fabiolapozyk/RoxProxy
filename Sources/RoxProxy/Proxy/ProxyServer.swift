import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import os.log

/// Manages the lifecycle of the local HTTP proxy server built on SwiftNIO.
final class ProxyServer {

    // MARK: - Properties

    let port: Int
    let store: ProxySessionStore
    let settingsStore: SettingsStore
    let certificateAuthority: CertificateAuthority?
    let domainCertCache: DomainCertificateCache?
    private let connectionTimeoutSeconds: Int
    // Snapshot of domain rules taken at start time (Sendable value type, safe to pass to NIO threads)
    private let domainRules: [DomainRule]

    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?

    // MARK: - Init

    /// Must be called on the `@MainActor` so settings can be read safely.
    @MainActor
    init(
        port: Int,
        store: ProxySessionStore,
        settingsStore: SettingsStore,
        certificateAuthority: CertificateAuthority? = nil,
        domainCertCache: DomainCertificateCache? = nil
    ) {
        self.port = port
        self.store = store
        self.settingsStore = settingsStore
        self.certificateAuthority = certificateAuthority
        self.domainCertCache = domainCertCache
        self.connectionTimeoutSeconds = settingsStore.settings.connectionTimeoutSeconds
        self.domainRules = settingsStore.settings.domainRules
    }

    // MARK: - Lifecycle

    /// Starts the proxy server, binding to `127.0.0.1:<port>`.
    /// Throws if the port is already in use or another bind error occurs.
    func start() async throws {
        ProxyLogger.proxy.info("Starting proxy server on port %d", port)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.group = group

        let store         = self.store
        let settingsStore = self.settingsStore
        let ca            = self.certificateAuthority
        let certCache     = self.domainCertCache
        let domainRules   = self.domainRules
        let timeoutSecs   = self.connectionTimeoutSeconds
        
        ProxyLogger.proxy.debug("Proxy configuration: timeout=%ds, domainRules=%d", timeoutSecs, domainRules.count)

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
                                settingsStore: settingsStore,
                                certificateAuthority: ca,
                                domainCertCache: certCache,
                                domainRules: domainRules
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
            channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
            ProxyLogger.proxy.info("Proxy server bound to 127.0.0.1:%d", port)
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
