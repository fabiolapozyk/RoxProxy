import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOTLS
import NIOSSL
import os.log

// MARK: - MITM Setup Handler

/// Installed on the inbound channel immediately after `NIOSSLServerHandler`.
/// Waits for the TLS handshake completion event, then swaps in HTTP codec
/// and `MITMHandler` so the decrypted traffic can be inspected.
final class MITMSetupHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer   // raw decrypted bytes before HTTP parsing

    let host: String
    let port: Int
    let store: BridgeSessionStore
    let mapLocalMatcher: MapLocalMatcher?

    init(host: String, port: Int, store: BridgeSessionStore, mapLocalMatcher: MapLocalMatcher? = nil) {
        self.host = host
        self.port = port
        self.store = store
        self.mapLocalMatcher = mapLocalMatcher
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case TLSUserEvent.handshakeCompleted = event {
            ProxyLogger.tls.info("MITM TLS handshake completed for %{public}@:%d", host, port)
            upgradePipeline(context: context)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ProxyLogger.tls.error("MITM setup handler error: %{public}@", "\(error)")
        context.close(promise: nil)
    }

    private func upgradePipeline(context: ChannelHandlerContext) {
        let pipeline = context.pipeline
        let host = self.host
        let port = self.port
        let store = self.store
        let mapLocalMatcher = self.mapLocalMatcher

        // Insert handlers after self (i.e. at .last), then remove self.
        // Pipeline after upgrade: NIOSSLServerHandler → HTTPRequestDecoder
        //   → HTTPResponseEncoder → MITMHandler
        pipeline.addHandler(
            ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)),
            name: "MITMHTTPRequestDecoder",
            position: .last
        )
        .flatMap {
            pipeline.addHandler(
                HTTPResponseEncoder(),
                name: "MITMHTTPResponseEncoder",
                position: .last
            )
        }
        .flatMap {
            pipeline.addHandler(
                MITMHandler(host: host, port: port, store: store, mapLocalMatcher: mapLocalMatcher),
                name: "MITMHandler",
                position: .last
            )
        }
        .flatMap { pipeline.removeHandler(self) }
        .whenSuccess {
            ProxyLogger.tls.info("MITM pipeline upgrade complete for %{public}@:%d", host, port)
            _ = context.channel.setOption(ChannelOptions.autoRead, value: true)
        }
    }
}

// MARK: - MITM Handler

/// Handles decrypted HTTP traffic on the client-facing channel after MITM TLS
/// interception.  For each request it opens a fresh TLS connection to the real
/// upstream server, forwards the request, and captures the exchange.
final class MITMHandler: ChannelInboundHandler {
    typealias InboundIn   = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private enum State {
        case idle
        case collecting(head: HTTPRequestHead, bodyParts: [ByteBuffer])
        case forwarding
    }

    private var state: State = .idle

    let host: String
    let port: Int
    let store: BridgeSessionStore
    let mapLocalMatcher: MapLocalMatcher?

    init(host: String, port: Int, store: BridgeSessionStore, mapLocalMatcher: MapLocalMatcher? = nil) {
        self.host = host
        self.port = port
        self.store = store
        self.mapLocalMatcher = mapLocalMatcher
    }

    // MARK: - ChannelInboundHandler

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            ProxyLogger.http.debug("MITMHandler: received .head method=%{public}@ path=%{public}@", head.method.rawValue, head.uri)
            guard case .idle = state else { 
                ProxyLogger.http.error("MITMHandler: pipelining rejected")
                context.close(promise: nil); return 
            }
            ProxyLogger.http.debug("MITM decrypted request: %{public}@ %{public}@", head.method.rawValue, head.uri)
            state = .collecting(head: head, bodyParts: [])
        case .body(let buffer):
            ProxyLogger.http.debug("MITMHandler: received .body with %{public}@ bytes", buffer.readableBytes)
            guard case .collecting(let head, var parts) = state else { return }
            parts.append(buffer)
            state = .collecting(head: head, bodyParts: parts)
        case .end:
            ProxyLogger.http.debug("MITMHandler: received .end - calling handleEnd")
            handleEnd(context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        ProxyLogger.http.debug("MITM channel inactive")
        state = .idle
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ProxyLogger.error.error("MITM handler error: %{public}@", error.localizedDescription)
        context.close(promise: nil)
    }

    // MARK: - Request dispatch

    private func handleEnd(context: ChannelHandlerContext) {
        ProxyLogger.http.debug("MITMHandler: handleEnd called, state=%{public}@", "\(state)")
        guard case .collecting(let head, let bodyParts) = state else {
            ProxyLogger.http.error("MITMHandler: handleEnd called but state is not .collecting")
            return 
        }
        ProxyLogger.http.debug("MITMHandler: handleEnd processing request with %{public}@ body parts", bodyParts.count)
        state = .forwarding

        // autoRead already managed in establishMITM, no need to disable here

        let (bodyContent, bodySize) = RequestCapture.build(from: bodyParts)
        let requestHeaders: [(name: String, value: String)] = head.headers.map {
            (name: $0.name, value: $0.value)
        }

        let url = "https://\(host)\(head.uri)"
        ProxyLogger.http.debug("MITM decrypted request end for %{public}@: %{public}@ %{public}@", host, head.method.rawValue, head.uri)
        var exchange = CapturedExchange(
            method: head.method.rawValue,
            url: url,
            scheme: "https",
            host: host,
            port: port,
            requestHeaders: requestHeaders,
            requestBody: bodyContent,
            requestSize: bodySize,
            isHTTPS: true,
            isMITMDecrypted: true
        )

        let store = self.store
        Task { @MainActor in store.append(exchange) }

        // Map Local interception — serve a local file instead of forwarding.
        if let matcher = mapLocalMatcher, !matcher.isEmpty {
            let matchPath = URL(string: head.uri)?.path ?? "/"
            if let rule = matcher.firstMatch(method: head.method.rawValue, host: host, path: matchPath) {
                ProxyLogger.map.info("Map Local (HTTPS): rule %{public}@ matches %{public}@ %{public}@", rule.pathPattern, head.method.rawValue, head.uri)
                MapLocalHandler.serve(rule: rule, context: context, exchange: exchange, store: store) { [weak self] in
                    guard let self else { return }
                    self.state = .idle
                }
                return
            }
        }

        // Normalise URI to relative path (some clients send absolute URIs)
        var outHead = head
        if outHead.uri.hasPrefix("https://") || outHead.uri.hasPrefix("http://") {
            if let parsed = URL(string: outHead.uri) {
                var path = parsed.path.isEmpty ? "/" : parsed.path
                if let q = parsed.query { path += "?" + q }
                outHead.uri = path
            }
        }
        outHead.headers.remove(name: "Proxy-Connection")
        outHead.headers.remove(name: "Proxy-Authorization")
        outHead.headers.replaceOrAdd(name: "Connection", value: "close")
        outHead.headers.replaceOrAdd(name: "Host", value: host)

        let onComplete = { [weak self] in
            guard let self else { return }
            _ = context.channel.setOption(ChannelOptions.autoRead, value: true)
            self.state = .idle
        }

        // Build upstream TLS context — no certificate verification (dev tool)
        ProxyLogger.tls.debug("Creating client TLS context (certificate verification disabled)")
        let sslContext: NIOSSLContext
        do {
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            tlsConfig.certificateVerification = .none
            sslContext = try NIOSSLContext(configuration: tlsConfig)
        } catch {
            ProxyLogger.tls.error("TLS setup failed: %{public}@", error.localizedDescription)
            exchange.state   = .failed("TLS setup: \(friendlyConnectionError(error, host: host))")
            exchange.endTime = Date()
            Task { @MainActor in store.update(exchange) }
            sendError(context: context, status: .internalServerError)
            onComplete()
            return
        }

        let host = self.host
        ClientBootstrap(group: context.eventLoop)
            .channelInitializer { channel in
                do {
                    let ssl = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                    return channel.pipeline.addHandler(ssl)
                        .flatMap { channel.pipeline.addHTTPClientHandlers() }
                        .flatMap {
                            channel.pipeline.addHandler(
                                OutboundHTTPHandler(
                                    inboundContext: context,
                                    store: store,
                                    exchange: exchange,
                                    onComplete: onComplete
                                )
                            )
                        }
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .connect(host: host, port: port)
            .whenComplete { [weak self] result in
                guard let self = self else { return }
                ProxyLogger.http.debug("MITMHandler: upstream connection result for %{public}@:%d", self.host, self.port)
                switch result {
                case .success(let upstreamChannel):
                    ProxyLogger.http.debug("MITMHandler: upstream connection established to %{public}@:%d", self.host, self.port)
                    upstreamChannel.write(NIOAny(HTTPClientRequestPart.head(outHead)), promise: nil)
                    for buf in bodyParts {
                        upstreamChannel.write(
                            NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil
                        )
                    }
                    upstreamChannel.writeAndFlush(
                        NIOAny(HTTPClientRequestPart.end(nil)), promise: nil
                    )

                case .failure(let error):
                    ProxyLogger.http.error("MITMHandler: upstream connection failed to %{public}@:%d: %{public}@", self.host, self.port, "\(error)")
                    var failed = exchange
                    failed.state   = .failed(friendlyConnectionError(error, host: host))
                    failed.endTime = Date()
                    Task { @MainActor in store.update(failed) }
                    self.sendError(context: context, status: .badGateway)
                    onComplete()
                }
            }
    }

    // MARK: - Helpers

    private func sendError(context: ChannelHandlerContext, status: HTTPResponseStatus) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "0")
        headers.add(name: "Connection", value: "close")
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
