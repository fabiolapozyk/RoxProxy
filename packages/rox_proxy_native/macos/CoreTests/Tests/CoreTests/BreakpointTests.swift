import Foundation
import XCTest
import NIOCore
import NIOEmbedded
import NIOHTTP1

// MARK: - Stubs

/// In-memory notifier recording notifications, with controllable availability.
private final class StubNotifier: BreakpointHandler.Notifier {
    var isAvailable = true
    private(set) var requests: [BreakpointRequest] = []
    private(set) var responses: [ResponseBreakpoint] = []

    func requestSuspended(_ request: BreakpointRequest) {
        requests.append(request)
    }

    func responseSuspended(_ response: ResponseBreakpoint) {
        responses.append(response)
    }
}

// MARK: - BreakpointRule

final class BreakpointRuleTests: XCTestCase {

    func testFromDictionary() {
        let dict: [String: Any] = [
            "id": "rule-1",
            "hostPattern": "*.example.com",
            "pathPattern": "/api/*",
            "httpMethod": "POST",
            "target": "both",
            "isEnabled": false,
        ]
        guard let rule = BreakpointRule.fromDictionary(dict) else {
            return XCTFail("fromDictionary should parse a valid dict")
        }
        XCTAssertEqual(rule.id, "rule-1")
        XCTAssertEqual(rule.hostPattern, "*.example.com")
        XCTAssertEqual(rule.pathPattern, "/api/*")
        XCTAssertEqual(rule.httpMethod, "POST")
        XCTAssertEqual(rule.target, .both)
        XCTAssertFalse(rule.isEnabled)
    }

    func testFromDictionaryDefaults() {
        let rule = BreakpointRule.fromDictionary(["id": "r"])
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.hostPattern, "*")
        XCTAssertEqual(rule?.pathPattern, "**")
        XCTAssertEqual(rule?.httpMethod, "ANY")
        XCTAssertEqual(rule?.target, .request)
        XCTAssertTrue(rule?.isEnabled ?? false)
    }

    func testFromDictionaryInvalid() {
        XCTAssertNil(BreakpointRule.fromDictionary([:]))
        XCTAssertNil(BreakpointRule.fromDictionary(["id": ""]))
    }
}

// MARK: - ResponseBreakpoint serialization

final class ResponseBreakpointTests: XCTestCase {

    func testToDictionary() {
        let response = ResponseBreakpoint(
            id: "bp-1",
            exchangeId: "ex-1",
            method: "GET",
            url: "https://example.com/api",
            statusCode: 404,
            statusMessage: "Not Found",
            headers: [("Content-Type", "application/json")],
            body: "{\"error\":true}",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let dict = response.toDictionary()
        XCTAssertEqual(dict["id"] as? String, "bp-1")
        XCTAssertEqual(dict["exchangeId"] as? String, "ex-1")
        XCTAssertEqual(dict["type"] as? String, "response")
        XCTAssertEqual(dict["statusCode"] as? Int, 404)
        XCTAssertEqual(dict["statusMessage"] as? String, "Not Found")
        XCTAssertEqual(dict["body"] as? String, "{\"error\":true}")
        XCTAssertNotNil(dict["timestamp"] as? String)
        let headers = dict["headers"] as? [[String: String]]
        XCTAssertEqual(headers?.first?["name"], "Content-Type")
    }

    func testToDictionaryNilBody() {
        let response = ResponseBreakpoint(
            id: "bp-2",
            exchangeId: "ex-2",
            method: "GET",
            url: "https://example.com/",
            statusCode: 200,
            statusMessage: "OK",
            headers: [],
            body: nil,
            timestamp: Date()
        )
        XCTAssertNil(response.toDictionary()["body"] as? String)
    }
}

// MARK: - BreakpointMatcher

final class BreakpointMatcherTests: XCTestCase {

    private func rule(
        host: String = "*",
        path: String = "**",
        method: String = "ANY",
        target: BreakpointTarget = .request,
        enabled: Bool = true
    ) -> BreakpointRule {
        BreakpointRule(
            hostPattern: host,
            pathPattern: path,
            httpMethod: method,
            target: target,
            isEnabled: enabled
        )
    }

    private func matcher(_ rules: [BreakpointRule]) -> BreakpointMatcher {
        BreakpointMatcher(rules: rules)
    }

    // MARK: - Empty/disabled rules = breakpoints off

    func testEmptyRulesBreakNothing() {
        let m = matcher([])
        XCTAssertFalse(m.shouldBreakpointRequest(method: "GET", host: "h", path: "/"))
        XCTAssertFalse(m.shouldBreakpointRequest(method: "POST", host: "h", path: "/api"))
        XCTAssertFalse(m.shouldBreakpointResponse(method: "GET", host: "h", path: "/"))
    }

    // MARK: - Request rules

    func testRequestRuleMatches() {
        let m = matcher([rule(host: "api.example.com", path: "/api/**", method: "POST")])
        XCTAssertTrue(m.shouldBreakpointRequest(method: "POST", host: "api.example.com", path: "/api/users"))
        XCTAssertFalse(m.shouldBreakpointRequest(method: "GET", host: "api.example.com", path: "/api/users"))
        XCTAssertFalse(m.shouldBreakpointRequest(method: "POST", host: "other.com", path: "/api/users"))
        XCTAssertFalse(m.shouldBreakpointRequest(method: "POST", host: "api.example.com", path: "/other"))
    }

    func testRequestRuleDoesNotMatchResponses() {
        let m = matcher([rule(target: .request)])
        XCTAssertFalse(m.shouldBreakpointResponse(method: "GET", host: "h", path: "/"))
    }

    // MARK: - Response rules

    func testResponseRuleMatches() {
        let m = matcher([rule(host: "api.example.com", target: .response)])
        XCTAssertTrue(m.shouldBreakpointResponse(method: "GET", host: "api.example.com", path: "/"))
        XCTAssertFalse(m.shouldBreakpointResponse(method: "GET", host: "other.com", path: "/"))
        XCTAssertFalse(m.shouldBreakpointRequest(method: "GET", host: "api.example.com", path: "/"))
    }

    func testBothRuleMatchesBoth() {
        let m = matcher([rule(target: .both)])
        XCTAssertTrue(m.shouldBreakpointRequest(method: "GET", host: "h", path: "/"))
        XCTAssertTrue(m.shouldBreakpointResponse(method: "GET", host: "h", path: "/"))
    }

    func testDisabledRulesSkipped() {
        let enabled = rule(target: .both)
        let disabled = rule(target: .both, enabled: false)
        // Only the disabled rule matches nothing here → requests must not break.
        let m = matcher([disabled])
        XCTAssertFalse(m.shouldBreakpointRequest(method: "GET", host: "h", path: "/"))
        XCTAssertFalse(m.shouldBreakpointResponse(method: "GET", host: "h", path: "/"))
        // With a second enabled rule, matching resumes.
        let m2 = matcher([disabled, enabled])
        XCTAssertTrue(m2.shouldBreakpointRequest(method: "GET", host: "h", path: "/"))
    }

    // MARK: - Host/path glob matching

    func testHostWildcard() {
        let m = matcher([rule(host: "*.example.com")])
        XCTAssertTrue(m.shouldBreakpointRequest(method: "GET", host: "api.example.com", path: "/"))
        XCTAssertTrue(m.shouldBreakpointRequest(method: "GET", host: "example.com", path: "/"))
        XCTAssertFalse(m.shouldBreakpointRequest(method: "GET", host: "example.org", path: "/"))
    }

    func testHostCaseInsensitive() {
        let m = matcher([rule(host: "API.Example.COM")])
        XCTAssertTrue(m.shouldBreakpointRequest(method: "GET", host: "api.example.com", path: "/"))
    }

    func testPathGlob() {
        let m = matcher([rule(path: "/api/*")])
        XCTAssertTrue(m.shouldBreakpointRequest(method: "GET", host: "h", path: "/api/users"))
        XCTAssertFalse(m.shouldBreakpointRequest(method: "GET", host: "h", path: "/api/users/1"))
    }

    func testMethodAnyCaseInsensitive() {
        let m = matcher([rule(method: "get")])
        XCTAssertTrue(m.shouldBreakpointRequest(method: "GET", host: "h", path: "/"))
        XCTAssertFalse(m.shouldBreakpointRequest(method: "POST", host: "h", path: "/"))
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
        // Il URI dell'head viene riscritto: il forwarder MITM lo usa così com'è.
        XCTAssertEqual(result.head.uri, "/new/path?x=2")
        XCTAssertEqual(result.exchange.path, "/new/path?x=2")
        XCTAssertEqual(result.exchange.url, "http://example.com/new/path?x=2")
        XCTAssertEqual(result.host, "example.com")
    }

    func testHostChangeApplied() {
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedUrl": "http://other.com/x?y=1"]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator
        )
        XCTAssertEqual(result.host, "other.com")
        XCTAssertEqual(result.port, 80)
        XCTAssertEqual(result.relativePath, "/x?y=1")
        // Host header follows the new target.
        XCTAssertEqual(result.head.headers.first(name: "Host"), "other.com")
        XCTAssertEqual(result.exchange.host, "other.com")
        XCTAssertEqual(result.exchange.url, "http://other.com/x?y=1")
    }

    func testPortChangeApplied() {
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedUrl": "http://example.com:8081/x"]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(),
            allocator: allocator
        )
        XCTAssertEqual(result.host, "example.com")
        XCTAssertEqual(result.port, 8081)
        XCTAssertEqual(result.exchange.url, "http://example.com:8081/x")
    }

    func testHostChangeAppliedOnMITM() {
        var httpsExchange = makeExchange()
        httpsExchange.scheme = "https"
        httpsExchange.port = 443
        httpsExchange.url = "https://example.com/a/b?q=1"
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedUrl": "https://other.com/x"]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 443,
            originalRelativePath: "/a/b?q=1",
            exchange: httpsExchange,
            allocator: allocator
        )
        XCTAssertEqual(result.host, "other.com")
        XCTAssertEqual(result.port, 443)
        XCTAssertEqual(result.exchange.url, "https://other.com/x")
    }

    func testSchemeChangeIgnored() {
        let result = RequestModifier.apply(
            response: proceedResponse(["breakpointId": "bp", "action": "proceed", "modifiedUrl": "https://other.com/x"]),
            originalHead: makeHead(),
            bodyParts: [],
            originalHost: "example.com",
            originalPort: 80,
            originalRelativePath: "/a/b?q=1",
            exchange: makeExchange(), // scheme "http"
            allocator: allocator
        )
        // https scheme on a plain HTTP exchange: host change rejected, path kept.
        XCTAssertEqual(result.host, "example.com")
        XCTAssertEqual(result.port, 80)
        XCTAssertEqual(result.relativePath, "/x")
        XCTAssertEqual(result.exchange.url, "http://example.com/x")
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
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        let request = BreakpointRequest(id: "bp-1", exchangeId: "ex-1", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        let suspended = handler.suspend(request: request, eventLoop: loop) { decisions.append($0) }

        XCTAssertTrue(suspended)
        XCTAssertEqual(notifier.requests.count, 1)
        XCTAssertEqual(notifier.requests.first?.id, "bp-1")
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
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

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
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: nil)

        let request = BreakpointRequest(id: "bp-3", exchangeId: "ex-3", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        XCTAssertFalse(handler.suspend(request: request, eventLoop: loop) { _ in })
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testSuspendFailsWhenNotifierUnavailable() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        notifier.isAvailable = false
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

        let request = BreakpointRequest(id: "bp-4", exchangeId: "ex-4", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        XCTAssertFalse(handler.suspend(request: request, eventLoop: loop) { _ in })
        XCTAssertEqual(notifier.requests.count, 0)
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testTimeoutAutoProceeds() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

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
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

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
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: nil)
        handler.resolve(breakpointId: "ghost", response: .autoProceed(breakpointId: "ghost"))
        loop.run()
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testExactlyOnce() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

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
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

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

// MARK: - Response suspension

final class BreakpointResponseSuspensionTests: XCTestCase {

    private func makeResponse() -> ResponseBreakpoint {
        ResponseBreakpoint(
            id: "rb-1",
            exchangeId: "ex-1",
            method: "GET",
            url: "https://example.com/api",
            statusCode: 200,
            statusMessage: "OK",
            headers: [("Content-Type", "application/json")],
            body: "{}",
            timestamp: Date()
        )
    }

    func testSuspendResponseNotifiesAndResolves() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        XCTAssertTrue(
            handler.suspend(response: makeResponse(), eventLoop: loop) { decisions.append($0) }
        )
        XCTAssertEqual(notifier.responses.count, 1)
        XCTAssertEqual(notifier.responses.first?.statusCode, 200)
        XCTAssertEqual(handler.pendingCount, 1)

        handler.resolve(breakpointId: "rb-1", response: .autoProceed(breakpointId: "rb-1"))
        loop.run()
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.action, .proceed)
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testSuspendResponseCancel() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        XCTAssertTrue(
            handler.suspend(response: makeResponse(), eventLoop: loop) { decisions.append($0) }
        )
        let cancel = BreakpointResponse.fromDictionary(["breakpointId": "rb-1", "action": "cancel"])!
        handler.resolve(breakpointId: "rb-1", response: cancel)
        loop.run()
        XCTAssertEqual(decisions.first?.action, .cancel)
    }

    func testSuspendResponseTimeout() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        XCTAssertTrue(
            handler.suspend(response: makeResponse(), eventLoop: loop) { decisions.append($0) }
        )
        loop.advanceTime(by: .seconds(31))
        loop.run()
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.action, .proceed)
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testSuspendResponseFailsWithoutNotifier() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: nil)
        XCTAssertFalse(
            handler.suspend(response: makeResponse(), eventLoop: loop) { _ in }
        )
        XCTAssertEqual(handler.pendingCount, 0)
    }

    func testReleaseAllReleasesMixedSuspensions() {
        let loop = EmbeddedEventLoop()
        defer { loop.shutdownGracefully { _ in } }
        let notifier = StubNotifier()
        let handler = BreakpointHandler(matcher: BreakpointMatcher(rules: []), notifier: notifier)

        var decisions: [BreakpointResponse] = []
        let request = BreakpointRequest(id: "rb-req", exchangeId: "ex-1", method: "GET", url: "https://a.com", headers: [], body: nil, timestamp: Date())
        XCTAssertTrue(handler.suspend(request: request, eventLoop: loop) { decisions.append($0) })
        XCTAssertTrue(handler.suspend(response: makeResponse(), eventLoop: loop) { decisions.append($0) })

        handler.releaseAll()
        loop.run()
        XCTAssertEqual(decisions.count, 2)
        XCTAssertTrue(decisions.allSatisfy { $0.action == .proceed })
    }
}

// MARK: - OutboundHTTPHandler response suspension (integration)

/// No-op handler used only to obtain a ChannelHandlerContext for the inbound
/// (client) side in the embedded tests.
private final class NoopHandler: ChannelInboundHandler {
    typealias InboundIn = Never
}

final class OutboundHTTPHandlerResponseTests: XCTestCase {

    private func makeStore() -> BridgeSessionStore {
        BridgeSessionStore(streamHandler: ExchangeStreamHandler(), bodyStore: BodyStore())
    }

    private func makeHandler() -> (BreakpointHandler, StubNotifier) {
        let notifier = StubNotifier()
        let handler = BreakpointHandler(
            matcher: BreakpointMatcher(rules: [
                BreakpointRule(hostPattern: "example.com", target: .response)
            ]),
            notifier: notifier
        )
        return (handler, notifier)
    }

    private func makeInboundContext(_ inbound: EmbeddedChannel) throws -> ChannelHandlerContext {
        try inbound.pipeline.addHandler(NoopHandler()).wait()
        try inbound.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
        return try inbound.pipeline.context(handlerType: NoopHandler.self).wait()
    }

    private func connectUpstream(_ upstream: EmbeddedChannel) throws {
        try upstream.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
    }

    /// Runs the pending decision on the upstream loop, then drains the
    /// (possibly hopped) writes on the inbound loop.
    private func drainDecision(upstream: EmbeddedChannel, inbound: EmbeddedChannel) {
        upstream.embeddedEventLoop.run()
        inbound.embeddedEventLoop.run()
        inbound.flush()
    }

    private func feedResponse(
        upstream: EmbeddedChannel,
        body: String = "hello"
    ) throws {
        let head = HTTPResponseHead(
            version: .http1_1,
            status: .ok,
            headers: HTTPHeaders([("Content-Length", "\(body.utf8.count)")])
        )
        try upstream.writeInbound(HTTPClientResponsePart.head(head))
        var buffer = upstream.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        try upstream.writeInbound(HTTPClientResponsePart.body(buffer))
        try upstream.writeInbound(HTTPClientResponsePart.end(nil))
    }

    func testUpstreamErrorAfterEndDoesNotCloseClientDuringSuspension() throws {
        let store = makeStore()
        let (handler, notifier) = makeHandler()
        let exchange = CapturedExchange(
            method: "GET",
            url: "https://example.com/api",
            scheme: "https",
            host: "example.com",
            port: 443,
            isHTTPS: true,
            isMITMDecrypted: true
        )

        let inbound = EmbeddedChannel()
        let upstream = EmbeddedChannel()
        defer {
            _ = try? upstream.finish()
            _ = try? inbound.finish()
        }
        let inboundContext = try makeInboundContext(inbound)
        try connectUpstream(upstream)

        var completed = false
        try upstream.pipeline.addHandler(
            OutboundHTTPHandler(
                inboundContext: inboundContext,
                store: store,
                exchange: exchange,
                onComplete: { completed = true },
                breakpointHandler: handler
            )
        ).wait()

        // Response arrives and is suspended: notified, nothing to the client.
        try feedResponse(upstream: upstream)
        XCTAssertEqual(notifier.responses.count, 1)
        XCTAssertEqual(notifier.responses.first?.statusCode, 200)
        XCTAssertTrue(inbound.isActive)
        XCTAssertNil(try inbound.readOutbound(as: HTTPServerResponsePart.self))

        // An upstream error after the complete response (typical TLS close
        // on `Connection: close`) must NOT abort the client connection.
        upstream.pipeline.fireErrorCaught(NSError(domain: "test", code: 12))
        upstream.embeddedEventLoop.run()
        inbound.embeddedEventLoop.run()
        XCTAssertTrue(inbound.isActive, "client connection must survive the upstream close error")

        // Proceed → the buffered response is forwarded to the client.
        let breakpointId = notifier.responses.first!.id
        handler.resolve(breakpointId: breakpointId, response: .autoProceed(breakpointId: breakpointId))
        drainDecision(upstream: upstream, inbound: inbound)

        XCTAssertTrue(completed)
        let head = try inbound.readOutbound(as: HTTPServerResponsePart.self)
        guard case .head(let headPart) = head else {
            return XCTFail("expected response head, got \(String(describing: head))")
        }
        XCTAssertEqual(headPart.status.code, 200)

        let body = try inbound.readOutbound(as: HTTPServerResponsePart.self)
        guard case .body(IOData.byteBuffer(let bodyBuffer)) = body else {
            return XCTFail("expected response body")
        }
        XCTAssertEqual(bodyBuffer.getString(at: 0, length: bodyBuffer.readableBytes), "hello")

        let end = try inbound.readOutbound(as: HTTPServerResponsePart.self)
        guard case .end = end else {
            return XCTFail("expected response end")
        }
    }

    func testResponseBreakpointResumesWithBufferedBody() throws {
        let store = makeStore()
        let (handler, notifier) = makeHandler()
        let exchange = CapturedExchange(
            method: "GET",
            url: "https://example.com/api",
            scheme: "https",
            host: "example.com",
            port: 443,
            isHTTPS: true,
            isMITMDecrypted: true
        )

        let inbound = EmbeddedChannel()
        let upstream = EmbeddedChannel()
        defer {
            _ = try? upstream.finish()
            _ = try? inbound.finish()
        }
        let inboundContext = try makeInboundContext(inbound)
        try connectUpstream(upstream)

        try upstream.pipeline.addHandler(
            OutboundHTTPHandler(
                inboundContext: inboundContext,
                store: store,
                exchange: exchange,
                onComplete: {},
                breakpointHandler: handler
            )
        ).wait()

        try feedResponse(upstream: upstream, body: "large body chunk")
        XCTAssertEqual(notifier.responses.count, 1)

        handler.resolve(
            breakpointId: notifier.responses.first!.id,
            response: .autoProceed(breakpointId: notifier.responses.first!.id)
        )
        drainDecision(upstream: upstream, inbound: inbound)

        let head = try inbound.readOutbound(as: HTTPServerResponsePart.self)
        guard case .head = head else {
            return XCTFail("expected response head")
        }

        let body = try inbound.readOutbound(as: HTTPServerResponsePart.self)
        guard case .body(IOData.byteBuffer(let bodyBuffer)) = body else {
            return XCTFail("expected response body")
        }
        XCTAssertEqual(bodyBuffer.getString(at: 0, length: bodyBuffer.readableBytes), "large body chunk")
    }

    func testCancelClosesClientConnection() throws {
        let store = makeStore()
        let (handler, notifier) = makeHandler()
        let exchange = CapturedExchange(
            method: "GET",
            url: "https://example.com/api",
            scheme: "https",
            host: "example.com",
            port: 443,
            isHTTPS: true,
            isMITMDecrypted: true
        )

        let inbound = EmbeddedChannel()
        let upstream = EmbeddedChannel()
        defer {
            _ = try? upstream.finish()
            _ = try? inbound.finish()
        }
        let inboundContext = try makeInboundContext(inbound)
        try connectUpstream(upstream)

        var completed = false
        try upstream.pipeline.addHandler(
            OutboundHTTPHandler(
                inboundContext: inboundContext,
                store: store,
                exchange: exchange,
                onComplete: { completed = true },
                breakpointHandler: handler
            )
        ).wait()

        try feedResponse(upstream: upstream)
        XCTAssertEqual(notifier.responses.count, 1)

        let cancel = BreakpointResponse.fromDictionary([
            "breakpointId": notifier.responses.first!.id, "action": "cancel"
        ])!
        handler.resolve(breakpointId: notifier.responses.first!.id, response: cancel)
        drainDecision(upstream: upstream, inbound: inbound)

        XCTAssertFalse(inbound.isActive, "cancel must close the client connection")
        XCTAssertTrue(completed)
    }
}
