import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
import Logging

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

    let store: ProxySessionStore
    let settingsStore: SettingsStore
    let certificateAuthority: CertificateAuthority?
    let domainCertCache: DomainCertificateCache?
    let domainRules: [DomainRule]
    let webSocketServer: WebSocketServer?
    private let logger: Logger

    init(
        store: ProxySessionStore,
        settingsStore: SettingsStore,
        certificateAuthority: CertificateAuthority? = nil,
        domainCertCache: DomainCertificateCache? = nil,
        domainRules: [DomainRule] = [],
        webSocketServer: WebSocketServer? = nil,
        logger: Logger = Logger(label: "com.roxproxy.HTTPProxyHandler")
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.certificateAuthority = certificateAuthority
        self.domainCertCache = domainCertCache
        self.domainRules = domainRules
        self.webSocketServer = webSocketServer
        self.logger = logger
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

        // Pause reads while we're waiting for the upstream connection
        _ = context.channel.setOption(ChannelOptions.autoRead, value: false)

        let target  = Self.parseTarget(uri: head.uri, headers: head.headers)
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

        // Check if we should trigger a breakpoint for this request
        if let webSocketServer = self.webSocketServer, shouldBreakpointRequest(head: head) {
            return handleBreakpoint(context: context, head: head, bodyParts: bodyParts, exchange: exchange, target: target)
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
                    exchange.state   = .failed(error.localizedDescription)
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
        let shouldMITM = domainCertCache != nil
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
                    failed.state = .failed(error.localizedDescription)
                    failed.endTime = Date()
                    Task { @MainActor in store.update(failed) }
                    self.sendResponse(context: context, status: .badGateway)
                }
            }
    }

    private func establishTunnel(context: ChannelHandlerContext, upstreamChannel: Channel, exchange: CapturedExchange, store: ProxySessionStore) {
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
            host: host, port: port, store: store, settingsStore: settingsStore
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

    // MARK: - Breakpoint Support

    private func shouldBreakpointRequest(head: HTTPRequestHead) -> Bool {
        // For now, breakpoint on all requests for testing
        // In production, you might want to add filters based on URL patterns, methods, etc.
        return true
    }

    private func handleBreakpoint(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        bodyParts: [ByteBuffer],
        exchange: CapturedExchange,
        target: (host: String, port: Int, relativePath: String)
    ) {
        guard let webSocketServer = self.webSocketServer else {
            // No WebSocket server available, proceed normally
            return proceedWithRequest(context: context, head: head, bodyParts: bodyParts, exchange: exchange, target: target)
        }

        // Convert headers to dictionary
        var headersDict: [String: String] = [:]
        for (name, value) in head.headers {
            headersDict[name] = value
        }

        // Convert body to string
        let bodyString: String?
        if let bodyData = exchange.requestBody?.data, let bodyStr = String(data: bodyData, encoding: .utf8) {
            bodyString = bodyStr
        } else {
            bodyString = nil
        }

        // Create breakpoint request
        let breakpointRequest = BreakpointRequest(
            exchangeId: exchange.id,
            type: .request,
            method: head.method.rawValue,
            url: head.uri,
            headers: headersDict,
            body: bodyString,
            isRequest: true
        )

        // Register handler for response
        let promise = context.eventLoop.makePromise(of: BreakpointResponse.self)
        
        webSocketServer.registerBreakpointHandler(breakpointRequest.id) { response in
            promise.succeed(response)
        }

        // Send breakpoint request to Flutter (we'll need to implement this)
        // For now, we'll simulate a WebSocket connection
        
        // Wait for user response with timeout
        let timeoutTask = context.eventLoop.scheduleTask(in: .seconds(30)) {
            promise.fail(BreakpointError.timeout)
        }

        promise.futureResult.whenComplete { result in
            timeoutTask.cancel()
            
            switch result {
            case .success(let response):
                self.handleBreakpointResponse(context: context, head: head, bodyParts: bodyParts, exchange: exchange, target: target, response: response)
            case .failure(let error):
                self.logger.error("Breakpoint failed: \(error)")
                // Proceed with original request on timeout/error
                self.proceedWithRequest(context: context, head: head, bodyParts: bodyParts, exchange: exchange, target: target)
            }
        }
    }

    private func handleBreakpointResponse(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        bodyParts: [ByteBuffer],
        exchange: CapturedExchange,
        target: (host: String, port: Int, relativePath: String),
        response: BreakpointResponse
    ) {
        switch response.action {
        case .proceed:
            // Apply modifications and proceed
            let modifiedHead = applyModifications(to: head, response: response)
            proceedWithRequest(context: context, head: modifiedHead, bodyParts: bodyParts, exchange: exchange, target: target)
        case .cancel:
            // Cancel the request
            sendResponse(context: context, status: .badRequest)
            state = .idle
        }
    }

    private func applyModifications(to head: HTTPRequestHead, response: BreakpointResponse) -> HTTPRequestHead {
        var modifiedHead = head
        
        if let method = response.modifiedMethod {
            modifiedHead.method = HTTPMethod(rawValue: method) ?? head.method
        }
        
        if let url = response.modifiedUrl, let target = Self.parseTarget(uri: url, headers: modifiedHead.headers) {
            modifiedHead.uri = target.relativePath
            // Update Host header if URL changed
            modifiedHead.headers.replaceOrAdd(name: "Host", value: "\(target.host):\(target.port)")
        }
        
        if let headers = response.modifiedHeaders {
            for (name, value) in headers {
                modifiedHead.headers.replaceOrAdd(name: name, value: value)
            }
        }
        
        return modifiedHead
    }

    private func proceedWithRequest(
        context: ChannelHandlerContext,
        head: HTTPRequestHead,
        bodyParts: [ByteBuffer],
        exchange: CapturedExchange,
        target: (host: String, port: Int, relativePath: String)
    ) {
        state = .forwarding

        // Pause reads while we're waiting for the upstream connection
        _ = context.channel.setOption(ChannelOptions.autoRead, value: false)

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
                    var failed = exchange
                    failed.state   = .failed(error.localizedDescription)
                    failed.endTime = Date()
                    Task { @MainActor in store.update(failed) }
                    self.sendResponse(context: context, status: .badGateway)
                    onComplete()
                }
            }
    }

    private enum BreakpointError: Error {
        case timeout
        case websocketNotAvailable
    }
}
