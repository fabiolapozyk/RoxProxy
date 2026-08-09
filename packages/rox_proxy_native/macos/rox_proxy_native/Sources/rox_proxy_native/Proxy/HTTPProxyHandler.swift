import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
import os.log

/// Main proxy channel handler.
///
/// - Buffers the incoming HTTP request (head + body parts) until `.end` arrives.
/// - Opens a TCP connection to the upstream server.
/// - Forwards the request and streams the response back to the client.
/// - Handles `CONNECT` as a passthrough tunnel (Step 6) or MITM (Step 7).
final class HTTPProxyHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn  = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    // MARK: - State machine

    private enum State {
        /// Waiting for the first request head.
        case idle
        /// Collecting request body parts before opening the upstream connection.
        case collecting(head: HTTPRequestHead, bodyParts: [ByteBuffer])
        /// Upstream connection established; forwarding response to client.
        case forwarding
    }

    private var state: State = .idle

    // MARK: - Dependencies

    let store: BridgeSessionStore
    let certificateAuthority: CertificateAuthority?
    let domainCertCache: DomainCertificateCache?
    let domainRules: [DomainRule]
    let httpsInterceptionEnabled: Bool
    let mapLocalMatcher: MapLocalMatcher?

    init(
        store: BridgeSessionStore,
        certificateAuthority: CertificateAuthority? = nil,
        domainCertCache: DomainCertificateCache? = nil,
        domainRules: [DomainRule] = [],
        httpsInterceptionEnabled: Bool = true,
        mapLocalMatcher: MapLocalMatcher? = nil
    ) {
        self.store = store
        self.certificateAuthority = certificateAuthority
        self.domainCertCache = domainCertCache
        self.domainRules = domainRules
        self.httpsInterceptionEnabled = httpsInterceptionEnabled
        self.mapLocalMatcher = mapLocalMatcher
    }

    // MARK: - ChannelInboundHandler

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            ProxyLogger.http.debug("Received request: %{public}@ %{public}@", head.method.rawValue, head.uri)
            handleHead(context: context, head: head)
        case .body(let buffer):
            handleBody(buffer: buffer)
        case .end:
            handleEnd(context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        ProxyLogger.http.debug("Channel inactive")
        state = .idle
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ProxyLogger.error.error("Channel error: %{public}@", error.localizedDescription)
        context.close(promise: nil)
    }

    // MARK: - Head

    private func handleHead(context: ChannelHandlerContext, head: HTTPRequestHead) {
        guard case .idle = state else {
            // Pipelining not fully supported in v1 — close
            ProxyLogger.http.error("Pipelining rejected: received request while state is not idle")
            context.close(promise: nil)
            return
        }

        if head.method == .CONNECT {
            // HTTPS tunnel — Step 6 / Step 7
            ProxyLogger.http.debug("CONNECT request to %{public}@", head.uri)
            handleCONNECT(context: context, head: head)
            return
        }

        ProxyLogger.http.debug("HTTP request: %{public}@ %{public}@", head.method.rawValue, head.uri)
        state = .collecting(head: head, bodyParts: [])
    }

    // MARK: - Body

    private func handleBody(buffer: ByteBuffer) {
        guard case .collecting(let head, var parts) = state else { return }
        parts.append(buffer)
        state = .collecting(head: head, bodyParts: parts)
    }

    // MARK: - End → connect + forward

    private func handleEnd(context: ChannelHandlerContext) {
        guard case .collecting(let head, let bodyParts) = state else { return }
        state = .forwarding

        let target = Self.parseTarget(uri: head.uri, headers: head.headers)
        ProxyLogger.http.debug("Request target: %{public}@:%d", target.host, target.port)
        
        // Intercept internal endpoints
        let path = URL(string: head.uri)?.path.lowercased() ?? head.uri.lowercased()
        
        // Health check endpoint
        if path == "/health" && head.method == .GET {
            ProxyLogger.http.debug("Serving health check")
            serveHealthCheck(context: context)
            return
        }
        
        // Stats endpoint
        if path == "/stats" && head.method == .GET {
            ProxyLogger.http.debug("Serving stats")
            serveStats(context: context)
            return
        }

        // Intercept CA certificate download.
        // Any device that has this proxy configured can visit http://cert.roxproxy/
        // to download and install the CA certificate.
        if target.host.lowercased() == "cert.roxproxy" {
            ProxyLogger.http.debug("Serving CA certificate download")
            serveCACertificate(context: context)
            return
        }

        // Increment request counter for non-internal requests
        ProxyMetrics.shared.incrementRequests()

        // Pause reads while we're waiting for the upstream connection
        _ = context.channel.setOption(ChannelOptions.autoRead, value: false)
        let (bodyContent, bodySize) = RequestCapture.build(from: bodyParts)
        
        // Track bytes received
        if bodySize > 0 {
            ProxyMetrics.shared.addReceivedBytes(Int64(bodySize))
        }

        var requestHeaders: [(name: String, value: String)] = []
        for (name, value) in head.headers { requestHeaders.append((name: name, value: value)) }

        // Build the CapturedExchange (in-progress)
        var exchange = CapturedExchange(
            method: head.method.rawValue,
            url: head.uri,
            scheme: "http",
            host: target.host,
            port: target.port,
            requestHeaders: requestHeaders,
            requestBody: bodyContent,
            requestSize: bodySize,
            isHTTPS: false,
            isMITMDecrypted: false
        )

        let store = self.store
        Task { @MainActor in store.append(exchange) }

        // Map Local interception — serve a local file instead of forwarding.
        if let matcher = mapLocalMatcher, !matcher.isEmpty {
            let matchPath = URL(string: head.uri)?.path ?? "/"
            if let rule = matcher.firstMatch(method: head.method.rawValue, host: target.host, path: matchPath) {
                ProxyLogger.map.info("Map Local: rule %{public}@ matches %{public}@ %{public}@", rule.pathPattern, head.method.rawValue, head.uri)
                MapLocalHandler.serve(rule: rule, context: context, exchange: exchange, store: store) { [weak self] in
                    guard let self else { return }
                    _ = context.channel.setOption(ChannelOptions.autoRead, value: true)
                    self.state = .idle
                }
                return
            }
        }

        // Build outbound request head (absolute URI → relative)
        var outHead = head
        outHead.uri = target.relativePath
        outHead.headers.remove(name: "Proxy-Connection")
        outHead.headers.remove(name: "Proxy-Authorization")
        outHead.headers.replaceOrAdd(name: "Connection", value: "close")

        let onComplete = { [weak self] in
            guard let self else { return }
            _ = context.channel.setOption(ChannelOptions.autoRead, value: true)
            self.state = .idle
        }

        // Connect to upstream on the same event loop
        ClientBootstrap(group: context.eventLoop)
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(
                        OutboundHTTPHandler(
                            inboundContext: context,
                            store: store,
                            exchange: exchange,
                            onComplete: onComplete
                        )
                    )
                }
            }
            .connect(host: target.host, port: target.port)
            .whenComplete { result in
                switch result {
                case .success(let upstreamChannel):
                    ProxyLogger.http.debug("Upstream connection established to %{public}@:%d", target.host, target.port)
                    upstreamChannel.write(NIOAny(HTTPClientRequestPart.head(outHead)), promise: nil)
                    for buf in bodyParts {
                        upstreamChannel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil)
                    }
                    upstreamChannel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

                case .failure(let error):
                    ProxyLogger.error.error("Upstream connection failed to %{public}@:%d: %{public}@", target.host, target.port, error.localizedDescription)
                    ProxyMetrics.shared.incrementErrors()
                    exchange.state   = CapturedExchange.ExchangeState.failed(friendlyConnectionError(error, host: target.host))
                    exchange.endTime = Date()
                    Task { @MainActor in store.update(exchange) }
                    self.sendResponse(context: context, status: .badGateway)
                    onComplete()
                }
            }
    }

    // MARK: - CONNECT

    private func handleCONNECT(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let target = Self.parseCONNECTTarget(authority: head.uri)
        ProxyLogger.http.debug("HTTPS CONNECT to %{public}@:%d", target.host, target.port)
        
        // Increment CONNECT request counter
        ProxyMetrics.shared.incrementConnectRequests()

        // Decide: MITM (TLS interception) or blind tunnel.
        // Map Local rules can only apply to HTTPS after decryption, so any
        // host with a matching rule forces MITM interception.
        let hasMapLocalRule = mapLocalMatcher?.hasPossibleMatch(host: target.host) ?? false
        let hasDomainRule = domainRules.contains(where: { $0.matches(host: target.host) })
        let shouldMITM = httpsInterceptionEnabled
            && domainCertCache != nil
            && (hasDomainRule || hasMapLocalRule)

        if hasMapLocalRule && !httpsInterceptionEnabled {
            ProxyLogger.map.default("Map Local rule exists for %{public}@ but HTTPS interception is disabled — rule will not apply", target.host)
        }

        if shouldMITM {
            ProxyLogger.tls.info("MITM decryption enabled for %{public}@", target.host)
            ProxyMetrics.shared.incrementMITMRequests()
            establishMITM(context: context, head: head, host: target.host, port: target.port)
        } else {
            ProxyLogger.tls.debug("Blind tunnel for %{public}@ (no MITM rule)", target.host)
            ProxyMetrics.shared.incrementTunnelRequests()
            connectAndTunnel(context: context, head: head, host: target.host, port: target.port)
        }
    }

    // MARK: - Blind tunnel (non-MITM HTTPS)

    private func connectAndTunnel(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        host: String,
        port: Int
    ) {
        let store = self.store

        let exchange = CapturedExchange(
            method: "CONNECT",
            url: "https://\(head.uri)",
            scheme: "https",
            host: host,
            port: port,
            requestHeaders: head.headers.map { (name: $0.name, value: $0.value) },
            requestBody: nil,
            requestSize: 0,
            isHTTPS: true,
            isMITMDecrypted: false
        )
        Task { @MainActor in store.append(exchange) }

        _ = context.channel.setOption(ChannelOptions.autoRead, value: false)

        ClientBootstrap(group: context.eventLoop)
            .connect(host: host, port: port)
            .whenComplete { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let upstreamChannel):
                    ProxyLogger.http.debug("Tunnel established to %{public}@:%d", host, port)
                    self.establishTunnel(context: context, upstreamChannel: upstreamChannel, exchange: exchange, store: store)
                case .failure(let error):
                    ProxyLogger.error.error("Tunnel connection failed to %{public}@:%d: %{public}@", host, port, error.localizedDescription)
                    ProxyMetrics.shared.incrementErrors()
                    var failed = exchange
                    failed.state = CapturedExchange.ExchangeState.failed(friendlyConnectionError(error, host: host))
                    failed.endTime = Date()
                    Task { @MainActor in store.update(failed) }
                    self.sendResponse(context: context, status: .badGateway)
                }
            }
    }

    private func establishTunnel(context: ChannelHandlerContext, upstreamChannel: Channel, exchange: CapturedExchange, store: BridgeSessionStore) {
        let inboundTunnel  = TunnelHandler()
        let outboundTunnel = TunnelHandler()

        inboundTunnel.peer  = upstreamChannel
        outboundTunnel.peer = context.channel

        upstreamChannel.pipeline.addHandler(outboundTunnel).whenComplete { _ in }

        sendConnectEstablished(context: context)

        context.pipeline.removeHandler(name: "HTTPProxyHandler")
            .flatMap { context.pipeline.removeHandler(name: "HTTPResponseEncoder") }
            .flatMap { context.pipeline.removeHandler(name: "HTTPRequestDecoder") }
            .flatMap { context.pipeline.addHandler(inboundTunnel) }
            .whenComplete { result in
                switch result {
                case .success:
                    _ = context.channel.setOption(ChannelOptions.autoRead, value: true)
                    // Tunnel established — mark exchange as completed
                    var tunneled = exchange
                    tunneled.state   = .completed
                    tunneled.endTime = Date()
                    Task { @MainActor in store.update(tunneled) }
                case .failure:
                    // Pipeline manipulation failed — close both sides to avoid stuck connection
                    upstreamChannel.close(promise: nil)
                    context.close(promise: nil)
                    var failed = exchange
                    failed.state   = CapturedExchange.ExchangeState.failed("Tunnel setup failed")
                    failed.endTime = Date()
                    Task { @MainActor in store.update(failed) }
                }
            }
    }

    // MARK: - MITM TLS interception

    private func establishMITM(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        host: String,
        port: Int
    ) {
        guard let cache = domainCertCache else {
            ProxyLogger.tls.error("MITM requested but domainCertCache is nil, falling back to blind tunnel")
            connectAndTunnel(context: context, head: head, host: host, port: port)
            return
        }

        ProxyLogger.tls.info("Generating domain certificate for %{public}@", host)
        _ = context.channel.setOption(ChannelOptions.autoRead, value: false)

        // Synchronous certificate fetch from the lock-based cache
        let cert: NIOSSLCertificate
        let key: NIOSSLPrivateKey
        do {
            (cert, key) = try cache.certificate(for: host)
            ProxyLogger.tls.debug("Domain certificate generated for %{public}@", host)
        } catch {
            ProxyLogger.tls.error("Failed to generate domain certificate for %{public}@: %{public}@", host, error.localizedDescription)
            sendResponse(context: context, status: .badGateway)
            return
        }

        // Build server-side TLS context with the forged domain certificate
        let sslContext: NIOSSLContext
        do {
            let tlsConfig = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(cert)],
                privateKey: .privateKey(key)
            )
            sslContext = try NIOSSLContext(configuration: tlsConfig)
            ProxyLogger.tls.debug("TLS context created for MITM")
        } catch {
            ProxyLogger.tls.error("Failed to create TLS context: %{public}@", error.localizedDescription)
            sendResponse(context: context, status: .internalServerError)
            return
        }

        ProxyLogger.tls.info("MITM TLS interception setup complete for %{public}@:%d", host, port)
        let sslHandler   = NIOSSLServerHandler(context: sslContext)
        let setupHandler = MITMSetupHandler(
            host: host, port: port, store: store, mapLocalMatcher: mapLocalMatcher
        )

        // Send 200 OK FIRST while HTTP encoder is still in pipeline
        self.sendConnectEstablished(context: context)

        // THEN reconfigure pipeline
        _ = context.channel.setOption(ChannelOptions.autoRead, value: false)
        context.pipeline.removeHandler(name: "HTTPProxyHandler")
            .flatMap { context.pipeline.removeHandler(name: "HTTPResponseEncoder") }
            .flatMap { context.pipeline.removeHandler(name: "HTTPRequestDecoder") }
            .flatMap { context.pipeline.addHandler(sslHandler, name: "MITMSSLServerHandler") }
            .flatMap { context.pipeline.addHandler(setupHandler, name: "MITMSetupHandler") }
            .whenComplete { result in
                switch result {
                case .success:
                    // Re-enable autoRead so NIOSSLServerHandler can read TLS data
                    _ = context.channel.setOption(ChannelOptions.autoRead, value: true)
                case .failure:
                    context.close(promise: nil)
                }
            }
    }

    // MARK: - Health Check Endpoint

    /// Serves a simple health check response at `/health`.
    /// Returns 200 OK with JSON indicating the proxy is running.
    private func serveHealthCheck(context: ChannelHandlerContext) {
        ProxyLogger.http.debug("Health check: proxy is running")
        
        let responseJSON = [
            "status": "running",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: responseJSON, options: [.prettyPrinted])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"status\":\"running\"}"
            
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Content-Length", value: "\(jsonString.utf8.count)")
            headers.add(name: "Connection", value: "close")
            
            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            
            var buffer = context.channel.allocator.buffer(capacity: jsonString.utf8.count)
            buffer.writeString(jsonString)
            
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        } catch {
            ProxyLogger.error.error("Failed to serialize health check response: %{public}@", error.localizedDescription)
            sendResponse(context: context, status: .internalServerError)
        }
        
        state = .idle
    }

    // MARK: - Stats Endpoint

    /// Serves proxy statistics at `/stats`.
    /// Returns JSON with request counts, error counts, bytes transferred, and uptime.
    private func serveStats(context: ChannelHandlerContext) {
        ProxyLogger.http.debug("Serving proxy stats")
        
        let metrics = ProxyMetrics.shared
        let responseJSON = metrics.toJSON()
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: responseJSON, options: [.prettyPrinted, .sortedKeys])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Content-Length", value: "\(jsonString.utf8.count)")
            headers.add(name: "Connection", value: "close")
            
            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            
            var buffer = context.channel.allocator.buffer(capacity: jsonString.utf8.count)
            buffer.writeString(jsonString)
            
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        } catch {
            ProxyLogger.error.error("Failed to serialize stats response: %{public}@", error.localizedDescription)
            sendResponse(context: context, status: .internalServerError)
        }
        
        state = .idle
    }

    // MARK: - CA certificate download endpoint

    /// Serves the CA certificate DER file in response to requests for `http://cert.roxproxy/`.
    /// The device must already have this proxy configured so the request is routed here.
    private func serveCACertificate(context: ChannelHandlerContext) {
        ProxyLogger.certificate.debug("Serving CA certificate for download")
        guard let ca = certificateAuthority else {
            ProxyLogger.certificate.error("Cannot serve CA certificate: certificateAuthority is nil")
            sendResponse(context: context, status: .notFound)
            state = .idle
            return
        }

        let certData = ca.caCertificateDER()
        ProxyLogger.certificate.debug("CA certificate size: %d bytes", certData.count)
        var body = context.channel.allocator.buffer(capacity: certData.count)
        body.writeBytes(certData)

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/x-x509-ca-cert")
        headers.add(name: "Content-Disposition", value: #"attachment; filename="RoxProxy-CA.crt""#)
        headers.add(name: "Content-Length", value: "\(certData.count)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        state = .idle
    }

    // MARK: - Shared helpers

    private func sendConnectEstablished(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "0")
        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    static func parseCONNECTTarget(authority: String) -> (host: String, port: Int) {
        let parts = authority.split(separator: ":", maxSplits: 1)
        let host  = String(parts.first ?? "localhost")
        let port  = parts.count > 1 ? Int(parts[1]) ?? 443 : 443
        return (host: host, port: port)
    }

    // MARK: - Helpers

    private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "0")
        headers.add(name: "Connection", value: "close")
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    /// Parses an absolute HTTP proxy URI (e.g. `http://example.com:8080/path?q=1`)
    /// and returns the host, port, and relative path.
    static func parseTarget(
        uri: String,
        headers: HTTPHeaders
    ) -> (host: String, port: Int, relativePath: String) {

        if let url = URL(string: uri), let host = url.host {
            let port = url.port ?? (url.scheme == "https" ? 443 : 80)
            var path = url.path.isEmpty ? "/" : url.path
            if let query = url.query { path += "?" + query }
            if let fragment = url.fragment { path += "#" + fragment }
            return (host: host, port: port, relativePath: path)
        }

        // Fallback: parse from Host header (for malformed absolute URIs)
        let hostHeader = headers.first(name: "host") ?? "localhost"
        let parts = hostHeader.split(separator: ":", maxSplits: 1)
        let host  = String(parts.first ?? "localhost")
        let port  = parts.count > 1 ? Int(parts[1]) ?? 80 : 80
        return (host: host, port: port, relativePath: uri)
    }
}
