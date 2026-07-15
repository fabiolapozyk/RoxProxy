import Foundation
import NIOCore
import NIOHTTP1
import os.log

/// Handles the upstream (server-side) connection for a plain HTTP proxy request.
///
/// Receives ``HTTPClientResponsePart`` from the upstream server, captures the response
/// into the ``CapturedExchange``, and forwards each part back to the downstream client
/// via the saved inbound ``ChannelHandlerContext``.
final class OutboundHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart

    // MARK: - State

    private let inboundContext: ChannelHandlerContext
    private let store: BridgeSessionStore
    private var exchange: CapturedExchange
    private let responseCapture = RequestCapture()
    private var responseStarted = false
    private let onComplete: () -> Void

    // MARK: - Init

    init(
        inboundContext: ChannelHandlerContext,
        store: BridgeSessionStore,
        exchange: CapturedExchange,
        onComplete: @escaping () -> Void
    ) {
        self.inboundContext = inboundContext
        self.store = store
        self.exchange = exchange
        self.onComplete = onComplete
    }

    // MARK: - ChannelInboundHandler

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            responseStarted = true
            exchange.statusCode    = Int(head.status.code)
            exchange.statusMessage = head.status.reasonPhrase
            exchange.responseHeaders = head.headers.map { (name: $0.name, value: $0.value) }
            
            ProxyLogger.http.debug("Received upstream response: %d %@", head.status.code, head.status.reasonPhrase ?? "")

            // Forward response head to client
            let responseHead = HTTPResponseHead(
                version: head.version,
                status: head.status,
                headers: head.headers
            )
            inboundContext.write(
                NIOAny(HTTPServerResponsePart.head(responseHead)),
                promise: nil
            )

        case .body(let buffer):
            responseCapture.append(buffer)
            // Forward body chunk to client (read before capture consumes nothing — readableBytesView is non-consuming)
            inboundContext.write(
                NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))),
                promise: nil
            )

        case .end(let trailers):
            ProxyLogger.http.debug("Upstream response complete")
            finalizeAndForward(trailers: trailers)
            context.close(promise: nil)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        // Upstream closed connection without a proper HTTP end (e.g. Connection: close)
        if exchange.state == .inProgress && responseStarted {
            ProxyLogger.http.debug("Upstream connection closed without proper HTTP end")
            finalizeAndForward(trailers: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ProxyLogger.error.error("Upstream error: %@", error.localizedDescription)
        if exchange.state == .inProgress {
            exchange.state   = .failed(error.localizedDescription)
            exchange.endTime = Date()
            let snapshot = exchange
            let store    = self.store
            Task { @MainActor in store.update(snapshot) }
            onComplete()
        }
        context.close(promise: nil)
    }

    // MARK: - Private

    private func finalizeAndForward(trailers: HTTPHeaders?) {
        guard exchange.state == .inProgress else { return }

        exchange.responseBody = responseCapture.bodyContent
        exchange.responseSize = responseCapture.totalBytes
        exchange.endTime      = Date()
        exchange.state        = .completed
        
        ProxyLogger.http.debug("Exchange completed: %@ %@ -> %d", exchange.method, exchange.url, exchange.statusCode ?? 0)

        let snapshot = exchange
        let store    = self.store
        Task { @MainActor in store.update(snapshot) }

        inboundContext.writeAndFlush(
            NIOAny(HTTPServerResponsePart.end(trailers)),
            promise: nil
        )
        onComplete()
    }
}
