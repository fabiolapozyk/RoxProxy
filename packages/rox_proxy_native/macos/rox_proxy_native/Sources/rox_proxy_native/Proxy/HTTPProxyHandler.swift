import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

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
    private var breakpointRules: [BreakpointRule]

    init(
        store: BridgeSessionStore,
        certificateAuthority: CertificateAuthority? = nil,
        domainCertCache: DomainCertificateCache? = nil,
        domainRules: [DomainRule] = [],
        httpsInterceptionEnabled: Bool = true,
        breakpointRules: [BreakpointRule] = []
    ) {
        self.store = store
        self.certificateAuthority = certificateAuthority
        self.domainCertCache = domainCertCache
        self.domainRules = domainRules
        self.httpsInterceptionEnabled = httpsInterceptionEnabled
        self.breakpointRules = breakpointRules
    }

    // MARK: - ChannelInboundHandler

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            handleHead(context: context, head: head)
        case .body(let buffer):
            handleBody(buffer: buffer)
        case .end:
            handleEnd(context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        state = .idle
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    // MARK: - Breakpoint Management

    func updateBreakpointRules(_ rules: [BreakpointRule]) {
        breakpointRules = rules
    }

    private func shouldPauseRequest(url: String) -> BreakpointRule? {
        for rule in breakpointRules {
            if !rule.isEnabled { continue }
            if rule.matches(url: url) && rule.interceptRequest {
                return rule
            }
        }
        return nil
    }

    // MARK: - Head

    private func handleHead(context: ChannelHandlerContext, head: HTTPRequestHead) {
        guard case .idle = state else {
            // Pipelining not fully supported in v1 — close
            context.close(promise: nil)
            return
        }

        if head.method == .CONNECT {
            // HTTPS tunnel — Step 6 / Step 7
            handleCONNECT(context: context, head: head)
            return
        }

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

        // Intercept CA certificate download.
        // Any device that has this proxy configured can visit http://cert.roxproxy/
        // to download and install the CA certificate.
        if target.host.lowercased() == "cert.roxproxy" {
            serveCACertificate(context: context)
            return
        }

        // Pause reads while we're waiting for the upstream connection
        _ = context.channel.setOption(ChannelOptions.autoRead, value: false)
        let (bodyContent, bodySize) = RequestCapture.build(from: bodyParts)

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

        // Check if this request should be paused for breakpoint
        if let matchingRule = shouldPauseRequest(url: head.uri) {
            print("⏸️  Breakpoint hit for request: \(head.uri)")
            
            // Pause the exchange and notify Flutter
            let bodyData = bodyContent?.data
            pauseExchange(exchange: exchange, context: context, head: head, target: target, 
                         bodyContent: bodyData, bodySize: bodySize, requestHeaders: requestHeaders)
            return
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
                    upstreamChannel.write(NIOAny(HTTPClientRequestPart.head(outHead)), promise: nil)
                    for buf in bodyParts {
                        upstreamChannel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil)
                    }
                    upstreamChannel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

                case .failure(let error):
                    exchange.state   = .failed(friendlyConnectionError(error, host: target.host))
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

        // Decide: MITM (TLS interception) or blind tunnel
        let shouldMITM = httpsInterceptionEnabled
            && domainCertCache != nil
            && domainRules.contains(where: { $0.matches(host: target.host) })

        if shouldMITM {
            establishMITM(context: context, head: head, host: target.host, port: target.port)
        } else {
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
                    self.establishTunnel(context: context, upstreamChannel: upstreamChannel, exchange: exchange, store: store)
                case .failure(let error):
                    var failed = exchange
                    failed.state = .failed(friendlyConnectionError(error, host: host))
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
                    failed.state   = .failed("Tunnel setup failed")
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
            connectAndTunnel(context: context, head: head, host: host, port: port)
            return
        }

        _ = context.channel.setOption(ChannelOptions.autoRead, value: false)

        // Synchronous certificate fetch from the lock-based cache
        let cert: NIOSSLCertificate
        let key: NIOSSLPrivateKey
        do {
            (cert, key) = try cache.certificate(for: host)
        } catch {
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
        } catch {
            sendResponse(context: context, status: .internalServerError)
            return
        }

        let sslHandler   = NIOSSLServerHandler(context: sslContext)
        let setupHandler = MITMSetupHandler(
            host: host, port: port, store: store
        )

        // Tell the client the tunnel is ready, then swap in TLS on this channel
        sendConnectEstablished(context: context)

        context.pipeline.removeHandler(name: "HTTPProxyHandler")
            .flatMap { context.pipeline.removeHandler(name: "HTTPResponseEncoder") }
            .flatMap { context.pipeline.removeHandler(name: "HTTPRequestDecoder") }
            .flatMap { context.pipeline.addHandler(sslHandler,   name: "MITMSSLServerHandler") }
            .flatMap { context.pipeline.addHandler(setupHandler, name: "MITMSetupHandler") }
            .whenComplete { result in
                switch result {
                case .success:
                    _ = context.channel.setOption(ChannelOptions.autoRead, value: true)
                case .failure:
                    context.close(promise: nil)
                }
            }
    }

    // MARK: - CA certificate download endpoint

    /// Serves the CA certificate DER file in response to requests for `http://cert.roxproxy/`.
    /// The device must already have this proxy configured so the request is routed here.
    private func serveCACertificate(context: ChannelHandlerContext) {
        guard let ca = certificateAuthority else {
            sendResponse(context: context, status: .notFound)
            state = .idle
            return
        }

        let certData = ca.caCertificateDER()
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

    // MARK: - Breakpoint Pausing

    private func pauseExchange(
        exchange: CapturedExchange,
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        target: (host: String, port: Int, relativePath: String),
        bodyContent: Data?,
        bodySize: Int,
        requestHeaders: [(name: String, value: String)]
    ) {
        // Store the paused exchange state
        let pausedState = PausedExchangeState(
            context: context,
            head: head,
            target: target,
            bodyContent: bodyContent,
            bodySize: bodySize,
            requestHeaders: requestHeaders
        )

        // Notify Flutter about the breakpoint hit
        notifyFlutterBreakpointHit(exchangeId: exchange.id.uuidString)

        print("⏸️  Exchange paused: \(exchange.id), waiting for Flutter response...")
    }

    private func notifyFlutterBreakpointHit(exchangeId: String) {
        // This would use the existing Flutter channel to notify Flutter
        // For now, we'll just print a message
        print("📬 Notifying Flutter: breakpoint hit for exchange \(exchangeId)")
        
        // In the actual implementation, you would:
        // 1. Get a reference to the Flutter method channel
        // 2. Call a method like "onBreakpointHit" with the exchangeId
        // 3. Flutter would show the breakpoint dialog
        // 4. When user clicks Resume/Cancel, Flutter calls resumeExchange/cancelExchange
    }

    // MARK: - Resume/Cancel Handling

    func resumeExchange(exchangeId: String, modifications: [String: Any]?) {
        print("▶️  Resuming exchange \(exchangeId) with modifications: \(modifications ?? [:])")
        // Implementation would:
        // 1. Find the paused exchange
        // 2. Apply modifications
        // 3. Continue with the original flow
    }

    func cancelExchange(exchangeId: String) {
        print("⏹️  Cancelling exchange \(exchangeId)")
        // Implementation would:
        // 1. Find the paused exchange
        // 2. Close the connection
        // 3. Clean up
    }
}

// MARK: - Paused Exchange State

private struct PausedExchangeState {
    let context: ChannelHandlerContext
    let head: HTTPRequestHead
    let target: (host: String, port: Int, relativePath: String)
    let bodyContent: Data?
    let bodySize: Int
    let requestHeaders: [(name: String, value: String)]
}
