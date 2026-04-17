import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import Logging

/// WebSocket server for handling breakpoint communication with Flutter frontend
final class WebSocketServer {
    private let group: MultiThreadedEventLoopGroup
    private let logger: Logger
    private var channel: Channel?
    private var breakpointHandlers: [UUID: (BreakpointResponse) -> Void] = [:]
    private let lock = NSLock()
    
    init(group: MultiThreadedEventLoopGroup, logger: Logger) {
        self.group = group
        self.logger = logger
    }
    
    /// Start the WebSocket server on the specified port
    func start(port: Int) throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(HTTPHandler(server: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
        
        let channel = try bootstrap.bind(host: "localhost", port: port).wait()
        self.channel = channel
        logger.info("WebSocket server started on port: \(port)")
    }
    
    /// Stop the WebSocket server
    func stop() {
        channel?.close(promise: nil)
        channel = nil
        logger.info("WebSocket server stopped")
    }
    
    /// Register a breakpoint handler to wait for user response
    func registerBreakpointHandler(_ breakpointId: UUID, handler: @escaping (BreakpointResponse) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        breakpointHandlers[breakpointId] = handler
    }
    
    /// Handle incoming breakpoint response from Flutter
    func handleBreakpointResponse(_ response: BreakpointResponse) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let handler = breakpointHandlers[response.breakpointId] else {
            logger.warning("Received response for unknown breakpoint: \(response.breakpointId)")
            return
        }
        
        // Remove handler to prevent memory leaks
        breakpointHandlers.removeValue(forKey: response.breakpointId)
        
        // Execute the handler
        handler(response)
    }
    
    /// Send a breakpoint request to Flutter
    func sendBreakpointRequest(_ request: BreakpointRequest, to websocket: WebSocket) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(request)
            
            let buffer = websocket.channel.allocator.buffer(bytes: data)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            
            websocket.send(frame, promise: nil)
            logger.debug("Sent breakpoint request: \(request.id)")
        } catch {
            logger.error("Failed to encode breakpoint request: \(error)")
        }
    }
    
    // MARK: - HTTP Handler
    
    private final class HTTPHandler: ChannelInboundHandler {
        typealias InboundIn = HTTPServerRequestPart
        
        private let server: WebSocketServer
        private let logger: Logger
        
        init(server: WebSocketServer) {
            self.server = server
            self.logger = server.logger
        }
        
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let part = unwrapInboundIn(data)
            
            switch part {
            case .head(let head):
                handleRequestHead(context: context, head: head)
            case .body:
                // Ignore body for WebSocket upgrade requests
                break
            case .end:
                break
            }
        }
        
        private func handleRequestHead(context: ChannelHandlerContext, head: HTTPRequestHead) {
            // Check if this is a WebSocket upgrade request
            if head.headers.contains(name: "Upgrade") && head.headers.contains(name: "Sec-WebSocket-Key") {
                handleWebSocketUpgrade(context: context, head: head)
            } else {
                // Regular HTTP request - respond with 404
                sendHTTPResponse(context: context, status: .notFound)
            }
        }
        
        private func handleWebSocketUpgrade(context: ChannelHandlerContext, head: HTTPRequestHead) {
            let upgradeRequest = HTTPRequestHead(
                version: head.version,
                method: head.method,
                uri: head.uri,
                headers: head.headers
            )
            
            let ws = NIOWebSocketServerUpgrader(
                shouldUpgrade: { channel, request in
                    // Accept all WebSocket connections
                    return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
                },
                upgradePipelineHandler: { channel, _ in
                    channel.pipeline.addHandler(WebSocketHandler(server: self.server))
                }
            )
            
            ws.upgrade(channel: context.channel, initialRequest: upgradeRequest)
        }
        
        private func sendHTTPResponse(context: ChannelHandlerContext, status: HTTPResponseStatus) {
            var headers = HTTPHeaders()
            headers.add(name: "Content-Length", value: "0")
            let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
    
    // MARK: - WebSocket Handler
    
    private final class WebSocketHandler: ChannelInboundHandler {
        typealias InboundIn = WebSocketFrame
        
        private let server: WebSocketServer
        private let logger: Logger
        
        init(server: WebSocketServer) {
            self.server = server
            self.logger = server.logger
        }
        
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let frame = unwrapInboundIn(data)
            
            switch frame.opcode {
            case .text:
                handleTextFrame(frame: frame, context: context)
            case .binary:
                handleBinaryFrame(frame: frame, context: context)
            case .connectionClose:
                context.close(promise: nil)
            case .ping:
                sendPong(context: context, frame: frame)
            case .pong, .continuation:
                break
            @unknown default:
                break
            }
        }
        
        private func handleTextFrame(frame: WebSocketFrame, context: ChannelHandlerContext) {
            guard let text = frame.unmaskedData else {
                logger.warning("Received empty WebSocket text frame")
                return
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let response = try decoder.decode(BreakpointResponse.self, from: text)
                
                logger.debug("Received breakpoint response: \(response.breakpointId)")
                server.handleBreakpointResponse(response)
                
            } catch {
                logger.error("Failed to decode breakpoint response: \(error)")
            }
        }
        
        private func handleBinaryFrame(frame: WebSocketFrame, context: ChannelHandlerContext) {
            logger.warning("Received unexpected binary WebSocket frame")
        }
        
        private func sendPong(context: ChannelHandlerContext, frame: WebSocketFrame) {
            var frame = frame
            frame.opcode = .pong
            context.write(wrapOutboundOut(frame), promise: nil)
        }
        
        func errorCaught(context: ChannelHandlerContext, error: Error) {
            logger.error("WebSocket error: \(error)")
            context.close(promise: nil)
        }
    }
}