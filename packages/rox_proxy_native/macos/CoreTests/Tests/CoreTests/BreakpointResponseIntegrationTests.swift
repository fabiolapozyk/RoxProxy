import Foundation
import XCTest
import NIOCore
import NIOPosix
import NIOHTTP1

// MARK: - Stubs

private final class IntegrationNotifier: BreakpointHandler.Notifier, @unchecked Sendable {
    var isAvailable = true
    private let lock = NSLock()
    private var _responses: [ResponseBreakpoint] = []
    private var _requests: [BreakpointRequest] = []

    var responses: [ResponseBreakpoint] {
        lock.lock()
        defer { lock.unlock() }
        return _responses
    }

    var requests: [BreakpointRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func requestSuspended(_ request: BreakpointRequest) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
    }

    func responseSuspended(_ response: ResponseBreakpoint) {
        lock.lock()
        _responses.append(response)
        lock.unlock()
    }

    func released(breakpointId: String) {}
}

/// Minimal upstream HTTP server returning a fixed response.
private final class FixedResponseHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let status: HTTPResponseStatus
    private let headers: HTTPHeaders
    private let body: Data
    private var buffer: ByteBuffer!

    init(status: HTTPResponseStatus = .ok, headers: HTTPHeaders, body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    func handlerAdded(context: ChannelHandlerContext) {
        buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        guard case .end = part else { return }
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        if !body.isEmpty {
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

/// Raw socket client helper (blocking reads on a background queue).
private final class RawSocket {
    let fd: Int32

    init(fd: Int32) { self.fd = fd }

    static func open(port: Int) async throws -> RawSocket {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = in_port_t(port).bigEndian
                addr.sin_addr.s_addr = inet_addr("127.0.0.1")
                let rc = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saddr in
                        connect(fd, saddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                guard rc == 0 else {
                    close(fd)
                    cont.resume(throwing: NSError(domain: "test", code: Int(errno)))
                    return
                }
                var tv = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                cont.resume(returning: RawSocket(fd: fd))
            }
        }
    }

    func write(_ string: String) throws {
        let data = Data(string.utf8)
        let rc = data.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress, data.count)
        }
        if rc < 0 { throw NSError(domain: "test", code: Int(errno)) }
    }

    /// Reads until EOF (or the receive timeout).
    func readAll() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                var all = Data()
                var buf = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = buf.withUnsafeMutableBytes { Darwin.read(self.fd, $0.baseAddress, 4096) }
                    if n > 0 {
                        all.append(contentsOf: buf.prefix(n))
                    } else if n == 0 {
                        break
                    } else if errno == EAGAIN || errno == EWOULDBLOCK {
                        break
                    } else {
                        cont.resume(throwing: NSError(domain: "test", code: Int(errno)))
                        return
                    }
                }
                cont.resume(returning: all)
            }
        }
    }

    deinit { close(fd) }
}

private func splitResponse(_ raw: Data) -> (head: String, body: Data) {
    let separator = Data("\r\n\r\n".utf8)
    guard let range = raw.range(of: separator) else {
        return (String(data: raw, encoding: .utf8) ?? "", Data())
    }
    let head = String(data: raw[..<range.lowerBound], encoding: .utf8) ?? ""
    let body = Data(raw[range.upperBound...])
    return (head, body)
}

// MARK: - Tests

@MainActor
final class BreakpointResponseIntegrationTests: XCTestCase {

    private var portCounter = 23000

    private func nextPort() -> Int {
        portCounter += 1
        return portCounter
    }

    private func makeStore() -> BridgeSessionStore {
        BridgeSessionStore(streamHandler: ExchangeStreamHandler(), bodyStore: BodyStore())
    }

    private func makeConfig() -> ProxyConfig {
        ProxyConfig(
            domainRules: [],
            mapLocalMatcher: MapLocalMatcher(rules: []),
            breakpointMatcher: BreakpointMatcher(rules: [
                BreakpointRule(hostPattern: "127.0.0.1", pathPattern: "/gzip", target: .response)
            ]),
            breakpointEnabled: true,
            httpsInterceptionEnabled: true,
            version: 0
        )
    }

    /// Starts a one-shot upstream server and returns its port.
    private func startUpstream(
        headers: HTTPHeaders,
        body: Data
    ) async throws -> (Int, MultiThreadedEventLoopGroup, Channel) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { ch in
                ch.pipeline
                    .addHandler(ByteToMessageHandler(HTTPRequestDecoder()))
                    .flatMap { ch.pipeline.addHandler(HTTPResponseEncoder()) }
                    .flatMap {
                        ch.pipeline.addHandler(
                            FixedResponseHandler(headers: headers, body: body)
                        )
                    }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        return (channel.localAddress!.port!, group, channel)
    }

    private func waitForResponse(
        _ notifier: IntegrationNotifier,
        timeout: TimeInterval = 5
    ) async throws -> ResponseBreakpoint {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = notifier.responses.first { return response }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "response breakpoint notification not received",
        ])
    }

    /// Regression: the dialog always sends the full header list back, including
    /// Content-Encoding. When the user edits the body, the response must be sent
    /// as identity (no Content-Encoding) with the new Content-Length.
    func testModifiedGzipResponseIsSentAsIdentity() async throws {
        let gzipBody = Data(base64Encoded: "H4sIAGIZ7moC/6tWyk0tLk5MT1WyUspIzcnJV0ivyixQqgUA1s45kxgAAAA=")!
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "\(gzipBody.count)")
        headers.add(name: "Content-Encoding", value: "gzip")
        headers.add(name: "Content-Type", value: "application/json")

        let (upstreamPort, group, upstreamChannel) = try await startUpstream(
            headers: headers, body: gzipBody
        )
        addTeardownBlock {
            try? await upstreamChannel.close().get()
            try? await group.shutdownGracefully()
        }

        let notifier = IntegrationNotifier()
        let breakpointHandler = BreakpointHandler(notifier: notifier)
        let proxyPort = nextPort()
        let server = ProxyServer(
            port: proxyPort,
            store: makeStore(),
            configStore: ProxyConfigStore(initial: makeConfig()),
            breakpointHandler: breakpointHandler
        )
        try await server.start()
        addTeardownBlock { try? await server.stop() }

        let client = try await RawSocket.open(port: proxyPort)
        try client.write(
            "GET http://127.0.0.1:\(upstreamPort)/gzip?x=1 HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )

        let suspended = try await waitForResponse(notifier)
        // The UI must receive the decoded body, not the raw gzip bytes.
        XCTAssertEqual(suspended.body, #"{"message":"hello gzip"}"#)

        // Mimic the dialog: send the original headers back plus the edited body.
        let decision = BreakpointResponse.fromDictionary([
            "breakpointId": suspended.id,
            "action": "proceed",
            "modifiedHeaders": suspended.headers.map { ["name": $0.name, "value": $0.value] },
            "modifiedBody": #"{"message":"edited"}"#,
        ])!
        breakpointHandler.resolve(breakpointId: suspended.id, response: decision)

        let raw = try await client.readAll()
        let (head, body) = splitResponse(raw)
        XCTAssertFalse(
            head.lowercased().contains("content-encoding: gzip"),
            "modified body must not be labelled as gzip:\n\(head)"
        )
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"message":"edited"}"#)
        XCTAssertTrue(
            head.lowercased().contains("content-length: 20"),
            "Content-Length must match the edited body:\n\(head)"
        )
    }

    /// When the body is not edited, the original compressed bytes must be
    /// forwarded untouched (Content-Encoding preserved).
    func testUnmodifiedGzipResponseKeepsEncoding() async throws {
        let gzipBody = Data(base64Encoded: "H4sIAGIZ7moC/6tWyk0tLk5MT1WyUspIzcnJV0ivyixQqgUA1s45kxgAAAA=")!
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "\(gzipBody.count)")
        headers.add(name: "Content-Encoding", value: "gzip")
        headers.add(name: "Content-Type", value: "application/json")

        let (upstreamPort, group, upstreamChannel) = try await startUpstream(
            headers: headers, body: gzipBody
        )
        addTeardownBlock {
            try? await upstreamChannel.close().get()
            try? await group.shutdownGracefully()
        }

        let notifier = IntegrationNotifier()
        let breakpointHandler = BreakpointHandler(notifier: notifier)
        let proxyPort = nextPort()
        let server = ProxyServer(
            port: proxyPort,
            store: makeStore(),
            configStore: ProxyConfigStore(initial: makeConfig()),
            breakpointHandler: breakpointHandler
        )
        try await server.start()
        addTeardownBlock { try? await server.stop() }

        let client = try await RawSocket.open(port: proxyPort)
        try client.write(
            "GET http://127.0.0.1:\(upstreamPort)/gzip?x=1 HTTP/1.1\r\n"
            + "Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )

        let suspended = try await waitForResponse(notifier)
        let decision = BreakpointResponse.fromDictionary([
            "breakpointId": suspended.id,
            "action": "proceed",
            "modifiedHeaders": suspended.headers.map { ["name": $0.name, "value": $0.value] },
        ])!
        breakpointHandler.resolve(breakpointId: suspended.id, response: decision)

        let raw = try await client.readAll()
        let (head, body) = splitResponse(raw)
        XCTAssertTrue(
            head.lowercased().contains("content-encoding: gzip"),
            "unmodified body must keep its encoding:\n\(head)"
        )
        XCTAssertTrue(
            head.lowercased().contains("content-length: \(gzipBody.count)"),
            "unmodified body must keep its Content-Length:\n\(head)"
        )
        XCTAssertEqual(body, gzipBody, "unmodified body must be forwarded byte-for-byte")
    }
}
