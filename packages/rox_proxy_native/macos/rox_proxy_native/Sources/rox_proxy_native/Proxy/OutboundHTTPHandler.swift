import Foundation
import NIOCore
import NIOHTTP1
import os.log

/// Handles the upstream (server-side) connection for a plain HTTP proxy request.
///
/// Receives ``HTTPClientResponsePart`` from the upstream server, captures the response
/// into the ``CapturedExchange``, and forwards each part back to the downstream client
/// via the saved inbound ``ChannelHandlerContext``.
///
/// When a response breakpoint matches, the response is held back (head + body
/// buffered) until the user decides: Proceed → forward as-is; Cancel → close
/// the client connection. Timeout/shutdown auto-proceed (shared engine).
final class OutboundHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart

    // MARK: - State

    private let inboundContext: ChannelHandlerContext
    private let store: BridgeSessionStore
    private var exchange: CapturedExchange
    private let responseCapture = RequestCapture()
    private var responseStarted = false
    private let onComplete: () -> Void
    private let breakpointHandler: BreakpointHandler?

    /// Response held back between `.head` and `.end` while waiting to decide.
    private struct SuspendedResponse {
        let head: HTTPResponseHead
        var bodyParts: [ByteBuffer] = []
        var trailers: HTTPHeaders?
    }

    private var suspended: SuspendedResponse?
    /// `.end` arrived and the decision is pending (channelInactive must not
    /// auto-proceed while we wait — the data is already complete).
    private var awaitingDecision = false

    // MARK: - Init

    init(
        inboundContext: ChannelHandlerContext,
        store: BridgeSessionStore,
        exchange: CapturedExchange,
        onComplete: @escaping () -> Void,
        breakpointHandler: BreakpointHandler? = nil
    ) {
        self.inboundContext = inboundContext
        self.store = store
        self.exchange = exchange
        self.onComplete = onComplete
        self.breakpointHandler = breakpointHandler
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

            ProxyLogger.http.debug("Received upstream response: %d %{public}@", head.status.code, head.status.reasonPhrase ?? "")

            // Response breakpoint — hold the response back.
            if shouldBreakpointResponse() {
                exchange.isBreakpoint = true
                exchange.isResponseBreakpoint = true
                suspended = SuspendedResponse(head: head)
                ProxyLogger.breakpoint.info(
                    "Response breakpoint: %{public}@ %{public}@ -> %d suspended",
                    exchange.method, exchange.url, head.status.code
                )
                return
            }

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
            // Track bytes sent
            ProxyMetrics.shared.addSentBytes(Int64(buffer.readableBytes))

            if var s = suspended {
                s.bodyParts.append(buffer)
                suspended = s
                return
            }
            // Forward body chunk to client (read before capture consumes nothing — readableBytesView is non-consuming)
            inboundContext.write(
                NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))),
                promise: nil
            )

        case .end(let trailers):
            ProxyLogger.http.debug("Upstream response complete")
            if var s = suspended {
                s.trailers = trailers
                suspended = nil
                suspendAndWait(s, context: context)
                // The response is fully buffered: the upstream is no longer
                // needed and its TLS shutdown must not disturb the decision
                // (closing here also avoids spurious close errors).
                context.close(promise: nil)
                return
            }
            finalizeAndForward(trailers: trailers)
            context.close(promise: nil)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        // Upstream closed connection without a proper HTTP end (e.g. Connection: close)
        if awaitingDecision { return }
        if let s = suspended {
            // Truncated response during suspension: proceed with what we have.
            suspended = nil
            resume(s, context: context)
            return
        }
        if exchange.state == .inProgress && responseStarted {
            ProxyLogger.http.debug("Upstream connection closed without proper HTTP end")
            finalizeAndForward(trailers: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ProxyLogger.error.error("Upstream error: %{public}@", error.localizedDescription)

        // The response is fully buffered and a decision is pending: an
        // upstream error (typically during the server's TLS close) must not
        // abort the suspended response or the client connection.
        if awaitingDecision {
            context.close(promise: nil)
            return
        }

        ProxyMetrics.shared.incrementErrors()

        if suspended != nil {
            // Mid-stream failure before `.end`: mark failed and abort the
            // client side.
            suspended = nil
            if exchange.state == .inProgress {
                exchange.state   = CapturedExchange.ExchangeState.failed(error.localizedDescription)
                exchange.endTime = Date()
                let snapshot = exchange
                let store    = self.store
                Task { @MainActor in store.update(snapshot) }
                onComplete()
            }
            inboundContext.close(promise: nil)
            context.close(promise: nil)
            return
        }

        if exchange.state == .inProgress {
            exchange.state   = CapturedExchange.ExchangeState.failed(error.localizedDescription)
            exchange.endTime = Date()
            let snapshot = exchange
            let store    = self.store
            Task { @MainActor in store.update(snapshot) }
            onComplete()
        }
        context.close(promise: nil)
    }

    // MARK: - Response breakpoint

    private func shouldBreakpointResponse() -> Bool {
        guard let handler = breakpointHandler else { return false }
        return handler.matcher.shouldBreakpointResponse(
            method: exchange.method, host: exchange.host, path: exchange.path
        )
    }

    private func suspendAndWait(_ s: SuspendedResponse, context: ChannelHandlerContext) {
        guard let handler = breakpointHandler else {
            resume(s, context: context)
            return
        }
        let payload = ResponseBreakpoint(
            id: UUID().uuidString,
            exchangeId: exchange.id.uuidString,
            method: exchange.method,
            url: exchange.url,
            statusCode: Int(s.head.status.code),
            statusMessage: s.head.status.reasonPhrase,
            headers: s.head.headers.map { (name: $0.name, value: $0.value) },
            body: responseCapture.bodyContent?.asString(),
            timestamp: Date()
        )
        let didSuspend = handler.suspend(
            response: payload,
            eventLoop: context.eventLoop
        ) { [weak self] decision in
            guard let self else { return }
            self.handleDecision(decision, suspended: s, context: context)
        }
        if didSuspend {
            awaitingDecision = true
        } else {
            // UI unavailable → forward immediately (RF3.3).
            resume(s, context: context)
        }
    }

    /// Proceed → forward the buffered response; Cancel → close the client
    /// connection and mark the exchange cancelled.
    private func handleDecision(
        _ decision: BreakpointResponse,
        suspended: SuspendedResponse,
        context: ChannelHandlerContext
    ) {
        awaitingDecision = false
        switch decision.action {
        case .cancel:
            ProxyLogger.breakpoint.info(
                "Response breakpoint cancelled: %{public}@ %{public}@", exchange.method, exchange.url
            )
            exchange.state   = .failed("Response cancelled by user (breakpoint)")
            exchange.endTime = Date()
            let snapshot = exchange
            let store    = self.store
            Task { @MainActor in store.update(snapshot) }
            inboundContext.close(promise: nil)
            onComplete()
            context.close(promise: nil)

        case .proceed:
            // Apply the user modifications (status/headers/body) and forward.
            let modified = ResponseModifier.apply(
                response: decision,
                originalHead: suspended.head,
                bodyParts: suspended.bodyParts,
                exchange: exchange,
                allocator: inboundContext.channel.allocator
            )
            resume(
                head: modified.head,
                bodyParts: modified.bodyParts,
                trailers: suspended.trailers,
                exchange: modified.exchange,
                context: context
            )
        }
    }

    /// Forwards the (possibly modified) head/body/end and finalizes the
    /// exchange. When the response body was not modified it is filled from the
    /// capture; otherwise `exchange` already carries the modified body.
    private func resume(
        head: HTTPResponseHead,
        bodyParts: [ByteBuffer],
        trailers: HTTPHeaders?,
        exchange: CapturedExchange,
        context: ChannelHandlerContext
    ) {
        var finalExchange = exchange
        guard finalExchange.state == .inProgress else { return }
        if finalExchange.responseBody == nil {
            finalExchange.responseBody = responseCapture.bodyContent
            finalExchange.responseSize = responseCapture.totalBytes
        }
        finalExchange.endTime = Date()
        finalExchange.state = .completed

        ProxyLogger.http.debug("Exchange completed: %{public}@ %{public}@ -> %d", finalExchange.method, finalExchange.url, finalExchange.statusCode ?? 0)

        let snapshot = finalExchange
        let store    = self.store
        Task { @MainActor in store.update(snapshot) }

        inboundContext.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
        for buf in bodyParts {
            inboundContext.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
        }
        inboundContext.writeAndFlush(NIOAny(HTTPServerResponsePart.end(trailers)), promise: nil)
        onComplete()
        context.close(promise: nil)
    }

    /// Forwards the buffered response as-is (used by auto-proceed paths).
    private func resume(_ s: SuspendedResponse, context: ChannelHandlerContext) {
        resume(
            head: s.head,
            bodyParts: s.bodyParts,
            trailers: s.trailers,
            exchange: exchange,
            context: context
        )
    }

    // MARK: - Private

    private func finalizeAndForward(trailers: HTTPHeaders?) {
        guard exchange.state == .inProgress else { return }

        exchange.responseBody = responseCapture.bodyContent
        exchange.responseSize = responseCapture.totalBytes
        exchange.endTime      = Date()
        exchange.state        = .completed
        
        ProxyLogger.http.debug("Exchange completed: %{public}@ %{public}@ -> %d", exchange.method, exchange.url, exchange.statusCode ?? 0)

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
