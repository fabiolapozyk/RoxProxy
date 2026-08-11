import Foundation
import XCTest
import NIOCore
import NIOEmbedded
import NIOHTTP1

// MARK: - Stubs

/// In-memory notifier recording notifications, with controllable availability.
private final class StubNotifier: BreakpointHandler.Notifier {
    var isAvailable = true
    private(set) var notifications: [BreakpointRequest] = []

    func breakpointSuspended(_ request: BreakpointRequest) {
        notifications.append(request)
    }
}

// MARK: - BreakpointMatcher

final class BreakpointMatcherTests: XCTestCase {

    func testDisabledNeverMatches() {
        let matcher = BreakpointMatcher(isEnabled: false)
        XCTAssertFalse(matcher.shouldBreakpointRequest(method: "GET", host: "h", path: "/"))
        XCTAssertFalse(matcher.shouldBreakpointRequest(method: "POST", host: "h", path: "/api"))
    }

    func testEnabledMatchesAllMethods() {
        let matcher = BreakpointMatcher(isEnabled: true)
        XCTAssertTrue(matcher.shouldBreakpointRequest(method: "GET", host: "h", path: "/"))
        XCTAssertTrue(matcher.shouldBreakpointRequest(method: "POST", host: "h", path: "/api"))
        XCTAssertTrue(matcher.shouldBreakpointRequest(method: "DELETE", host: "h", path: "/x"))
    }

    func testMethodFilter() {
        let matcher = BreakpointMatcher(isEnabled: true, methodFilter: ["POST", "PUT"])
        XCTAssertTrue(matcher.shouldBreakpointRequest(method: "POST", host: "h", path: "/"))
        XCTAssertTrue(matcher.shouldBreakpointRequest(method: "put", host: "h", path: "/"))
        XCTAssertFalse(matcher.shouldBreakpointRequest(method: "GET", host: "h", path: "/"))
        XCTAssertFalse(matcher.shouldBreakpointRequest(method: "DELETE", host: "h", path: "/"))
    }
}

// MARK: - BreakpointRequest serialization

final class BreakpointRequestTests: XCTestCase {

    func testToDictionary() {
        let request = BreakpointRequest(
            id: "bp-1",
            exchangeId: "ex-1",
            method: "POST",
            url: "https://example.com/api",
            headers: [("Content-Type", "application/json")],
            body: "{\"ok\":true}",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let dict = request.toDictionary()
        XCTAssertEqual(dict["id"] as? String, "bp-1")
        XCTAssertEqual(dict["exchangeId"] as? String, "ex-1")
        XCTAssertEqual(dict["type"] as? String, "request")
        XCTAssertEqual(dict["method"] as? String, "POST")
        XCTAssertEqual(dict["url"] as? String, "https://example.com/api")
        XCTAssertEqual(dict["body"] as? String, "{\"ok\":true}")
        XCTAssertNotNil(dict["timestamp"] as? String)
        let headers = dict["headers"] as? [[String: String]]
        XCTAssertEqual(headers?.first?["name"], "Content-Type")
        XCTAssertEqual(headers?.first?["value"], "application/json")
    }

    func testToDictionaryNilBody() {
        let request = BreakpointRequest(
            id: "bp-2",
            exchangeId: "ex-2",
            method: "GET",
            url: "https://example.com/",
            headers: [],
            body: nil,
            timestamp: Date()
        )
        XCTAssertNil(request.toDictionary()["body"] as? String)
    }
}

// MARK: - BreakpointResponse parsing

final class BreakpointResponseTests: XCTestCase {

    func testFromDictionaryProceedWithModifications() {
        let dict: [String: Any] = [
            "breakpointId": "bp-1",
            "action": "proceed",
            "modifiedMethod": "POST",
            "modifiedUrl": "https://example.com/api",
            "modifiedHeaders": [
                ["name": "X-Test", "value": "1"],
                ["name": "Content-Type", "value": "application/json"],
            ],
            "modifiedBody": "{\"x\":1}",
            "timestamp": "2026-08-10T10:00:05Z",
        ]
        let response = BreakpointResponse.fromDictionary(dict)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.breakpointId, "bp-1")
        XCTAssertEqual(response?.action, .proceed)
        XCTAssertEqual(response?.modifiedMethod, "POST")
        XCTAssertEqual(response?.modifiedUrl, "https://example.com/api")
        XCTAssertEqual(response?.modifiedBody, "{\"x\":1}")
        XCTAssertEqual(response?.modifiedHeaders?.count, 2)
        XCTAssertEqual(response?.modifiedHeaders?.first?.name, "X-Test")
    }

    func testFromDictionaryCancel() {
        let dict: [String: Any] = ["breakpointId": "bp-2", "action": "cancel"]
        let response = BreakpointResponse.fromDictionary(dict)
        XCTAssertEqual(response?.action, .cancel)
        XCTAssertNil(response?.modifiedMethod)
        XCTAssertNil(response?.modifiedHeaders)
    }

    func testFromDictionaryInvalid() {
        XCTAssertNil(BreakpointResponse.fromDictionary([:]))
        XCTAssertNil(BreakpointResponse.fromDictionary(["breakpointId": "bp"]))
        XCTAssertNil(BreakpointResponse.fromDictionary(["breakpointId": "bp", "action": "bogus"]))
    }

    func testAutoProceed() {
        let response = BreakpointResponse.autoProceed(breakpointId: "bp-3")
        XCTAssertEqual(response.action, .proceed)
        XCTAssertEqual(response.breakpointId, "bp-3")
        XCTAssertNil(response.modifiedMethod)
        XCTAssertNil(response.modifiedUrl)
        XCTAssertNil(response.modifiedHeaders)
        XCTAssertNil(response.modifiedBody)
    }
}

// MARK: - RequestModifier

final class RequestModifierTests: XCTestCase {

    private let allocator = ByteBufferAllocator()

    private func makeHead(method: String = "GET", uri: String = "http://example.com/a/b?q=1") -> HTTPRequestHead {
        var head = HTTPRequestHead(version: .http1_1, method: HTTPMethod(rawValue: method), uri: uri)
        head.headers.add(name: "Host", value: "example.com")
        head.headers.add(name: "User-Agent", value: "test")
        head.headers.add(name: "Content-Length", value: "0")
        return head
    }

    private func makeExchange() -> CapturedExchange {
        CapturedExchange(
            method: "GET",
            url: "http://example.com/a/b?q=1",
            scheme: "http",
            host: "example.com",
            port: 80,
            requestHeaders: [("Host", "example.com")],
            requestSize: 0,
            isHTTPS: false,
            isMITMDecrypted: false
        )
    }

    private func proceedResponse(_ dict: [String: Any]) -> BreakpointResponse {
        BreakpointResponse.fromDictionary(dict)!
    }

    func testNoModificationsKeepsRequest() {
        let head = makeHead()
        let exchange = makeExchange()
        let result = RequestModifier.apply(
            response: .autoProceed(breakpointId: "bp"),
            originalHead: head,
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: exchange,
            allocator: allocator
        )
        XCTAssertEqual(result.head.method, .GET)
        XCTAssertEqual(result.head.uri, "http://example.com/a/b?q=1")
        XCTAssertEqual(result.relativePath, "/a/b?q=1")
        XCTAssertEqual(result.host, "example.com")
        XCTAssertEqual(result.bodyParts.count, 0)
    }

    func testMethodChange() {
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedMethod": "POST"]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator
        )
        XCTAssertEqual(result.head.method, .POST)
        XCTAssertEqual(result.exchange.method, "POST")
    }

    func testMethodCONNECTIgnored() {
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedMethod": "CONNECT"]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator
        )
        XCTAssertEqual(result.head.method, .GET)
    }

    func testUrlPathChange() {
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedUrl": "http://example.com/new/path?x=2"]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator
        )
        XCTAssertEqual(result.relativePath, "/new/path?x=2")
        XCTAssertEqual(result.head.uri, "http://example.com/a/b?q=1")
        XCTAssertEqual(result.exchange.path, "/new/path?x=2")
        XCTAssertEqual(result.exchange.url, "http://example.com/new/path?x=2")
        XCTAssertEqual(result.host, "example.com")
    }

    func testHostChangeIgnored() {
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedUrl": "https://evil.com/x"]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator
        )
        XCTAssertEqual(result.host, "example.com")
        XCTAssertEqual(result.port, 80)
        XCTAssertEqual(result.relativePath, "/x")
        XCTAssertEqual(result.exchange.url, "http://example.com/x")
    }

    func testHostChangeIgnoredWhenFixed() {
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedUrl": "https://evil.com/x"]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 443,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator,
            fixedHost: "example.com"
        )
        XCTAssertEqual(result.host, "example.com")
        XCTAssertEqual(result.relativePath, "/x")
    }

    func testHeadersReplacedWithHostKept() {
        let result = RequestModifier.apply(
            response: proceedResponse([
                "breakpointId": "bp", "action": "proceed",
                "modifiedHeaders": [
                    ["name": "X-New", "value": "1"],
                    ["name": "Host", "value": "spoofed.com"],
                    ["name": "Content-Length", "value": "999"],
                ],
            ]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator
        )
        XCTAssertNil(result.head.headers.first(name: "User-Agent"))
        XCTAssertEqual(result.head.headers.first(name: "X-New"), "1")
        // Host is protected: forced back to the real target.
        XCTAssertEqual(result.head.headers.first(name: "Host"), "example.com")
        // Content-Length is protected; no body change, so the original stays.
        XCTAssertEqual(result.head.headers.first(name: "Content-Length"), "0")
    }

    func testBodyChangeFixesContentLength() {
        let head = makeHead(method: "POST")
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedBody": "hello"]),
            originalHead: head,
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator
        )
        XCTAssertEqual(result.bodyParts.count, 1)
        XCTAssertEqual(result.head.headers.first(name: "Content-Length"), "5")
        XCTAssertNil(result.head.headers.first(name: "Transfer-Encoding"))
        XCTAssertEqual(result.exchange.requestSize, 5)
        XCTAssertEqual(result.exchange.requestBody?.asString(), "hello")
    }

    func testEmptyBodyChange() {
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedBody": ""]),
            originalHead: makeHead(method: "POST"),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator
        )
        XCTAssertEqual(result.head.headers.first(name: "Content-Length"), "0")
        XCTAssertEqual(result.exchange.requestBody, .empty)
    }
}

// MARK: - BreakpointHandler

final class BreakpointHandlerTests: XCTestCase {

    func testSuspendNotifiesAndResolvesProceed() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(isEnabled: true), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        let request = BreakpointRequest(id: "bp-1", exchangeId: "ex-1", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        let suspended = handler.suspend(request: request, eventLoop: loop) { decisions.append($0) }

        XCTAssertTrue(suspended)
        XCTAssertEqual(notifier.notifications.count, 1)
        XCTAssertEqual(notifier.notifications.first?.id, "bp-1")
        XCTAssertEqual(handler.pendingCount, 1)

        let decision = BreakpointResponse.fromDictionary(["breakpointId": "bp-1", "action": "cancel"])!
        handler.resolve(breakpointId: "bp-1", response: decision)
        loop.run()

        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.action, .cancel)
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testSuspendWithModifications() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(isEnabled: true), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        let request = BreakpointRequest(id: "bp-2", exchangeId: "ex-2", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        XCTAssertTrue(handler.suspend(request: request, eventLoop: loop) { decisions.append($0) })

        let decision = BreakpointResponse.fromDictionary([
            "breakpointId": "bp-2", "action": "proceed", "modifiedMethod": "POST", "modifiedBody": "x",
        ])!
        handler.resolve(breakpointId: "bp-2", response: decision)
        loop.run()

        XCTAssertEqual(decisions.first?.modifiedMethod, "POST")
        XCTAssertEqual(decisions.first?.modifiedBody, "x")
    }

    func testSuspendFailsWithoutNotifier() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let handler = BreakpointHandler(matcher: BreakpointMatcher(isEnabled: true), notifier: nil)

        let request = BreakpointRequest(id: "bp-3", exchangeId: "ex-3", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        XCTAssertFalse(handler.suspend(request: request, eventLoop: loop) { _ in })
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testSuspendFailsWhenNotifierUnavailable() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        notifier.isAvailable = false
        let handler = BreakpointHandler(matcher: BreakpointMatcher(isEnabled: true), notifier: notifier)

        let request = BreakpointRequest(id: "bp-4", exchangeId: "ex-4", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        XCTAssertFalse(handler.suspend(request: request, eventLoop: loop) { _ in })
        XCTAssertEqual(notifier.notifications.count, 0)
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testTimeoutAutoProceeds() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(isEnabled: true), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        let request = BreakpointRequest(id: "bp-5", exchangeId: "ex-5", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        XCTAssertTrue(handler.suspend(request: request, eventLoop: loop) { decisions.append($0) })

        loop.advanceTime(by: .seconds(31))
        loop.run()

        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.action, .proceed)
        XCTAssertNil(decisions.first?.modifiedMethod)
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testTimeoutCancelledByDecision() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(isEnabled: true), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        let request = BreakpointRequest(id: "bp-6", exchangeId: "ex-6", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        XCTAssertTrue(handler.suspend(request: request, eventLoop: loop) { decisions.append($0) })

        let decision = BreakpointResponse.fromDictionary(["breakpointId": "bp-6", "action": "proceed"])!
        handler.resolve(breakpointId: "bp-6", response: decision)
        loop.run()

        loop.advanceTime(by: .seconds(60))
        loop.run()
        XCTAssertEqual(decisions.count, 1, "timeout must not fire after the decision")
    }

    func testResolveUnknownIdIsNoop() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let handler = BreakpointHandler(matcher: BreakpointMatcher(isEnabled: false), notifier: nil)
        handler.resolve(breakpointId: "ghost", response: .autoProceed(breakpointId: "ghost"))
        loop.run()
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testExactlyOnce() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(isEnabled: true), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        let request = BreakpointRequest(id: "bp-7", exchangeId: "ex-7", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        XCTAssertTrue(handler.suspend(request: request, eventLoop: loop) { decisions.append($0) })

        let proceed = BreakpointResponse.autoProceed(breakpointId: "bp-7")
        handler.resolve(breakpointId: "bp-7", response: proceed)
        handler.resolve(breakpointId: "bp-7", response: .autoProceed(breakpointId: "bp-7"))
        loop.run()
        XCTAssertEqual(decisions.count, 1)
    }

    func testReleaseAllProceeds() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(isEnabled: true), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        for id in ["a", "b", "c"] {
            let request = BreakpointRequest(id: id, exchangeId: id, method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
            XCTAssertTrue(handler.suspend(request: request, eventLoop: loop) { decisions.append($0) })
        }
        XCTAssertEqual(handler.pendingCount, 3)

        handler.releaseAll()
        loop.run()

        XCTAssertEqual(decisions.count, 3)
        XCTAssertTrue(decisions.allSatisfy { $0.action == .proceed })
        XCTAssertEqual(handler.pendingCount, 0)
    }
}
