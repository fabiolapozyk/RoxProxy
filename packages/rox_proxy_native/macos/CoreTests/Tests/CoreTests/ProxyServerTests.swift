import Foundation
import XCTest

@MainActor
final class ProxyServerTests: XCTestCase {

    private var portCounter = 21000

    private func nextPort() -> Int {
        portCounter += 1
        return portCounter
    }

    private func makeStore() -> BridgeSessionStore {
        BridgeSessionStore(
            streamHandler: ExchangeStreamHandler(),
            bodyStore: BodyStore()
        )
    }

    // MARK: - Lifecycle

    func testServerStartsAndStops() async throws {
        let server = ProxyServer(port: nextPort(), store: makeStore())
        try await server.start()
        await stop(server)
    }

    func testServerBindsAndServesHealthEndpoint() async throws {
        let port = nextPort()
        let server = ProxyServer(port: port, store: makeStore())
        try await server.start()

        let response = try await requestTo(
            port: port,
            request: "GET http://127.0.0.1:\(port)/health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200"), "Expected 200, got: \(response)")
        XCTAssertTrue(response.contains("\"running\""), "Expected running status, got: \(response)")
        await stop(server)
    }

    func testServerServesStatsEndpoint() async throws {
        let port = nextPort()
        let server = ProxyServer(port: port, store: makeStore())
        try await server.start()

        let response = try await requestTo(
            port: port,
            request: "GET http://127.0.0.1:\(port)/stats HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200"), "Expected 200, got: \(response)")
        XCTAssertTrue(response.contains("status"), "Expected stats JSON, got: \(response)")
        await stop(server)
    }

    func testServerFailsToStartOnOccupiedPort() async throws {
        let port = nextPort()
        let server1 = ProxyServer(port: port, store: makeStore())
        try await server1.start()

        let server2 = ProxyServer(port: port, store: makeStore())
        do {
            try await server2.start()
            XCTFail("Expected start to fail on occupied port \(port)")
        } catch ProxyServer.ProxyError.bindFailed(let failedPort, _) {
            XCTAssertEqual(failedPort, port)
        }
        await stop(server1)
    }

    func testStartFailureThrowsAndCleansUpGroup() async throws {
        let port = nextPort()
        let server1 = ProxyServer(port: port, store: makeStore())
        try await server1.start()

        let server2 = ProxyServer(port: port, store: makeStore())
        do {
            try await server2.start()
            XCTFail("Expected bind failure")
        } catch {
            // Nothing to assert here beyond the throw (covered by the dedicated test).
        }

        // After releasing the port, a new server must be able to start:
        // the failed bind must not leak sockets or event loops.
        await stop(server1)
        let server3 = ProxyServer(port: port, store: makeStore())
        do {
            try await server3.start()
        } catch {
            XCTFail("Expected server3 to start on released port, got \(error)")
        }
        await stop(server3)
    }

    // MARK: - Metrics

    func testMetricsResetOnStart() async throws {
        ProxyMetrics.shared.reset()
        let server = ProxyServer(port: nextPort(), store: makeStore())
        try await server.start()

        XCTAssertEqual(ProxyMetrics.shared.requestCount, 0)
        XCTAssertEqual(ProxyMetrics.shared.errorCount, 0)
        XCTAssertNotNil(ProxyMetrics.shared.startTime)
        await stop(server)
    }

    // MARK: - Helpers

    private func stop(_ server: ProxyServer) async {
        try? await server.stop()
    }

    // MARK: - Helpers

    /// Opens a raw TCP connection to the proxy port, sends the given raw request
    /// and returns the raw response received from the proxy.
    private func requestTo(port: Int, request: String) async throws -> String {
        let socket = try await makeConnectedSocket(port: port)
        try socket.write(Data(request.utf8))

        var all = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let n = try socket.read(into: &buffer, count: buffer.count)
            if n > 0 {
                all.append(contentsOf: buffer.prefix(n))
            } else if n == 0 {
                break
            }
        }
        return String(data: all, encoding: .utf8) ?? ""
    }

    private func makeConnectedSocket(port: Int) async throws -> SocketHelper {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                do {
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
                    // Read timeout so tests never hang on a silent server.
                    var tv = timeval(tv_sec: 2, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                    cont.resume(returning: SocketHelper(fd: fd))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

/// Minimal wrapper around a POSIX socket fd for raw connectivity checks.
final class SocketHelper {
    let fd: Int32

    init(fd: Int32) {
        self.fd = fd
    }

    func read(into buffer: inout [UInt8], count: Int) throws -> Int {
        let n = buffer.withUnsafeMutableBytes { ptr in
            Darwin.read(fd, ptr.baseAddress, count)
        }
        // Timeout (EAGAIN) means "no more data" for our purposes.
        if n < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK { return 0 }
            throw NSError(domain: "test", code: Int(errno))
        }
        return n
    }

    func write(_ data: Data) throws {
        let rc = data.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress, data.count)
        }
        if rc < 0 { throw NSError(domain: "test", code: Int(errno)) }
    }

    deinit {
        close(fd)
    }
}
