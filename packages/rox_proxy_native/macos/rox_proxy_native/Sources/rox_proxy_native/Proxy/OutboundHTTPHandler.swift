import Foundation
import NIOCore
import NIOHTTP1

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
    private let breakpoints: [Breakpoint]
    private weak var methodHandler: ProxyMethodHandler?
    private var exchange: CapturedExchange
    private let responseCapture = RequestCapture()
    private var responseStarted = false
    private let onComplete: () -> Void

    // MARK: - Init

    init(
        inboundContext: ChannelHandlerContext,
        store: BridgeSessionStore,
        exchange: CapturedExchange,
        breakpoints: [Breakpoint] = [],
        methodHandler: ProxyMethodHandler? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.inboundContext = inboundContext
        self.store = store
        self.breakpoints = breakpoints
        self.methodHandler = methodHandler
        self.exchange = exchange
        self.onComplete = onComplete
    }

    // MARK: - Breakpoint helpers

    private func shouldBreakForResponse() -> Bool {
        return breakpoints.contains { $0.matches(url: exchange.url) && ($0.trigger == .response || $0.trigger == .both) }
    }

    private func handleBreakpoint(
        exchange: CapturedExchange,
        isRequest: Bool,
        context: ChannelHandlerContext,
        responseHead: HTTPResponseHead,
        completion: @escaping (Bool, [String: Any]?) -> Void
    ) {
        // Send breakpoint event to Flutter
        print("DEBUG: BREAKPOINT HIT: \(isRequest ? "Request" : "Response") to \(exchange.url)")
        print("DEBUG: Exchange ID: \(exchange.id.uuidString)")
        print("DEBUG: Status Code: \(exchange.statusCode ?? 0)")
        
        // Check if methodHandler is available
        if methodHandler == nil {
            print("DEBUG: ERROR: methodHandler is nil in OutboundHTTPHandler! Cannot send breakpoint event to Flutter.")
            context.eventLoop.scheduleTask(in: .seconds(1)) {
                print("DEBUG: Continuing without breakpoint dialog due to missing methodHandler")
                completion(true, nil)
            }
            return
        }
        
        // Convert exchange to dictionary for sending to Flutter
        let exchangeData: [String: Any] = [
            "id": exchange.id,
            "method": exchange.method,
            "url": exchange.url,
            "scheme": exchange.scheme,
            "host": exchange.host,
            "port": exchange.port,
            "path": exchange.path,
            "requestHeaders": exchange.requestHeaders.map { ["name": $0.name, "value": $0.value] },
            "statusCode": exchange.statusCode ?? 0,
            "statusMessage": exchange.statusMessage ?? "",
            "responseHeaders": exchange.responseHeaders?.map { ["name": $0.name, "value": $0.value] } ?? [],
            "isHTTPS": exchange.isHTTPS,
            "isMITMDecrypted": exchange.isMITMDecrypted
        ]
        
        print("DEBUG: Sending breakpoint event to Flutter...")
        
        // Send event to Flutter
        methodHandler?.sendBreakpointEvent(
            exchangeId: exchange.id.uuidString,
            url: exchange.url,
            isRequest: isRequest,
            exchangeData: exchangeData
        )
        
        // Wait for resolution from Flutter
        // For now, we'll continue after a delay to simulate the full flow
        // In a complete implementation, we would wait for the actual response
        context.eventLoop.scheduleTask(in: .seconds(5)) {
            print("DEBUG: BREAKPOINT TIMEOUT: Continuing execution after waiting for Flutter response")
            completion(true, nil)
        }
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

            // Check if we should break for this response
            if shouldBreakForResponse() {
                // Store the response head for later use
                let responseHead = HTTPResponseHead(
                    version: head.version,
                    status: head.status,
                    headers: head.headers
                )
                
                // Handle breakpoint - pause execution
                handleBreakpoint(
                    exchange: exchange,
                    isRequest: false,
                    context: context,
                    responseHead: responseHead,
                    completion: { shouldContinue, modifications in
                        if shouldContinue {
                            // Forward response head to client
                            self.inboundContext.write(
                                NIOAny(HTTPServerResponsePart.head(responseHead)),
                                promise: nil
                            )
                        } else {
                            // User cancelled - close the connection
                            print("BREAKPOINT CANCELLED: Response from \(self.exchange.url)")
                            context.close(promise: nil)
                        }
                    }
                )
            } else {
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
            }

        case .body(let buffer):
            responseCapture.append(buffer)
            // Forward body chunk to client (read before capture consumes nothing — readableBytesView is non-consuming)
            inboundContext.write(
                NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))),
                promise: nil
            )

        case .end(let trailers):
            finalizeAndForward(trailers: trailers)
            context.close(promise: nil)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        // Upstream closed connection without a proper HTTP end (e.g. Connection: close)
        if exchange.state == .inProgress && responseStarted {
            finalizeAndForward(trailers: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
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
