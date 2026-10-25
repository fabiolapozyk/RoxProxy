import Foundation
import XCTest

private func makeConfig(
    domainCount: Int = 0,
    breakpointEnabled: Bool = false,
    httpsInterceptionEnabled: Bool = true
) -> ProxyConfig {
    let domains = (0..<domainCount).map {
        DomainRule(domain: "host\($0).example.com")
    }
    return ProxyConfig(
        domainRules: domains,
        mapLocalMatcher: MapLocalMatcher(rules: []),
        breakpointMatcher: BreakpointMatcher(rules: []),
        breakpointEnabled: breakpointEnabled,
        httpsInterceptionEnabled: httpsInterceptionEnabled,
        version: 0
    )
}

final class ProxyConfigStoreTests: XCTestCase {

    func testApplyAssignsMonotonicVersion() {
        let store = ProxyConfigStore(initial: makeConfig())
        XCTAssertEqual(store.current().version, 0)

        let first = store.apply(makeConfig(domainCount: 1))
        XCTAssertEqual(first.version, 1)
        XCTAssertEqual(first.domainRules.count, 1)

        let second = store.apply(makeConfig(domainCount: 2))
        XCTAssertEqual(second.version, 2)
        XCTAssertEqual(store.current().version, 2)
        XCTAssertEqual(store.current().domainRules.count, 2)
    }

    /// A captured snapshot is a value: a later apply must not mutate it.
    /// This is what guarantees that an in-flight request keeps its config.
    func testCapturedSnapshotIsImmutableAcrossApply() {
        let store = ProxyConfigStore(initial: makeConfig(domainCount: 1))
        let snapshot = store.current()
        XCTAssertEqual(snapshot.version, 0)

        _ = store.apply(makeConfig(domainCount: 3))

        XCTAssertEqual(snapshot.version, 0)
        XCTAssertEqual(snapshot.domainRules.count, 1)
        XCTAssertEqual(store.current().version, 1)
        XCTAssertEqual(store.current().domainRules.count, 3)
    }

    /// Concurrent readers must always observe a consistent snapshot: the
    /// domain count is encoded in the version by the writer below.
    func testConcurrentReadsNeverSeeTornConfig() {
        final class Failure: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            func mark() { lock.lock(); value = true; lock.unlock() }
            func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
        }

        let store = ProxyConfigStore(initial: makeConfig(domainCount: 0))
        let failure = Failure()
        let writes = 500

        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            if worker == 0 {
                for i in 0..<writes {
                    // version becomes i+1 and domain count matches it
                    _ = store.apply(makeConfig(domainCount: i + 1))
                }
            } else {
                for _ in 0..<writes {
                    let config = store.current()
                    if config.domainRules.count != config.version {
                        failure.mark()
                    }
                }
            }
        }

        XCTAssertFalse(failure.get(), "Reader observed a partially applied configuration")
    }
}

final class ProxyConfigParserTests: XCTestCase {

    func testParseValidPayload() {
        let payload: [String: Any] = [
            "domainRules": [[
                "id": UUID().uuidString,
                "domain": "*.example.com",
                "isEnabled": true,
            ]],
            "mapLocalRules": [[
                "id": UUID().uuidString,
                "hostPattern": "api.example.com",
                "pathPattern": "/api/**",
                "httpMethod": "GET",
                "filePath": "/tmp/mock.json",
                "isEnabled": true,
            ]],
            "breakpointEnabled": true,
            "breakpointRules": [[
                "id": "bp-1",
                "hostPattern": "api.example.com",
                "pathPattern": "/api/**",
                "httpMethod": "GET",
                "target": "request",
                "isEnabled": true,
            ]],
            "httpsInterceptionEnabled": false,
        ]

        let result = ProxyConfigParser.parse(payload)

        XCTAssertTrue(result.errors.isEmpty, result.errors.joined(separator: "; "))
        XCTAssertEqual(result.config.domainRules.count, 1)
        XCTAssertTrue(result.config.breakpointEnabled)
        XCTAssertFalse(result.config.httpsInterceptionEnabled)
        XCTAssertTrue(result.config.mapLocalMatcher.hasPossibleMatch(host: "api.example.com"))
        XCTAssertTrue(
            result.config.breakpointMatcher.shouldBreakpointRequest(
                method: "GET", host: "api.example.com", path: "/api/users"
            )
        )
    }

    func testEmptyPayloadUsesSafeDefaults() {
        let result = ProxyConfigParser.parse([:])
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(result.config.domainRules.isEmpty)
        XCTAssertTrue(result.config.mapLocalMatcher.isEmpty)
        XCTAssertFalse(result.config.breakpointEnabled)
        XCTAssertTrue(result.config.httpsInterceptionEnabled)
    }

    func testInvalidDomainRuleIsReported() {
        let result = ProxyConfigParser.parse([
            "domainRules": [
                ["id": "not-a-uuid", "domain": "example.com"],
            ],
        ])
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].contains("domainRules[0]"))
        XCTAssertTrue(result.config.domainRules.isEmpty)
    }

    func testInvalidMapLocalRuleIsReported() {
        let result = ProxyConfigParser.parse([
            "mapLocalRules": [
                ["id": UUID().uuidString, "pathPattern": "/api"],
            ],
        ])
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].contains("mapLocalRules[0]"))
    }

    func testInvalidMapLocalRegexIsReported() {
        let result = ProxyConfigParser.parse([
            "mapLocalRules": [[
                "id": UUID().uuidString,
                "hostPattern": "api.example.com",
                "pathPattern": "/api/[",
                "httpMethod": "GET",
                "filePath": "/tmp/mock.json",
                "useRegex": true,
            ]],
        ])
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].contains("invalid regex"))
    }

    func testInvalidBreakpointRuleIsReported() {
        let result = ProxyConfigParser.parse([
            "breakpointRules": [
                ["hostPattern": "example.com"],
            ],
        ])
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].contains("breakpointRules[0]"))
    }
}
