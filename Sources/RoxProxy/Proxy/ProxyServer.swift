import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import Logging

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
    private let websocketPort: Int

    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?
    private var webSocketServer: WebSocketServer?

    // MARK: - Init

    /// Must be called on the `@MainActor` so settings can be read safely.
    @MainActor
    init(
        port: Int,
        store: ProxySessionStore,
        settingsStore: SettingsStore,
        certificateAuthority: CertificateAuthority? = nil,
        domainCertCache: DomainCertificateCache? = nil,
        websocketPort: Int = 8081
    ) {
        self.port = port
        self.store = store
        self.settingsStore = settingsStore
        self.certificateAuthority = certificateAuthority
        self.domainCertCache = domainCertCache
        self.connectionTimeoutSeconds = settingsStore.settings.connectionTimeoutSeconds
        self.domainRules = settingsStore.settings.domainRules
        self.websocketPort = websocketPort
    }

    // MARK: - Lifecycle

    /// Starts the proxy server, binding to `127.0.0.1:<port>`.
    /// Throws if the port is already in use or another bind error occurs.
    func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.group = group

        let store         = self.store
        let settingsStore = self.settingsStore
        let ca            = self.certificateAuthority
        let certCache     = self.domainCertCache
        let domainRules   = self.domainRules
        let timeoutSecs   = self.connectionTimeoutSeconds
        let websocketPort = self.websocketPort

        // Start WebSocket server for breakpoint communication
        let webSocketServer = WebSocketServer(group: group, logger: Logger(label: "com.roxproxy.WebSocketServer"))
        self.webSocketServer = webSocketServer
        
        try webSocketServer.start(port: websocketPort)
        catch {
            try? await group.shutdownGracefully()
            self.group = nil
            throw ProxyError.websocketFailed(port: websocketPort, underlying: error)
        }

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
                                domainRules: domainRules,
                                webSocketServer: webSocketServer
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
        } catch {
            try? await group.shutdownGracefully()
            self.group = nil
            throw ProxyError.bindFailed(port: port, underlying: error)
        }
    }

    /// Stops the proxy server gracefully.
    func stop() async throws {
        try await channel?.close().get()
        webSocketServer?.stop()
        webSocketServer = nil
        try await group?.shutdownGracefully()
        channel = nil
        group = nil
    }

    // MARK: - Errors

    enum ProxyError: Error, LocalizedError {
        case bindFailed(port: Int, underlying: Error)
        case websocketFailed(port: Int, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .bindFailed(let port, let underlying):
                return "Cannot bind proxy on port \(port): \(underlying.localizedDescription). Try a different port in Settings."
            case .websocketFailed(let port, let underlying):
                return "Cannot start WebSocket server on port \(port): \(underlying.localizedDescription)."
            }
        }
    }
}
