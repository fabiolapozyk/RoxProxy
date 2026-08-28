import Foundation
import XCTest

final class MapLocalMatcherTests: XCTestCase {

    // MARK: - Glob to regex

    func testGlobToRegex() {
        XCTAssertEqual(MapLocalMatcher.globToRegex("/api/users"), "^/api/users$")
        XCTAssertEqual(MapLocalMatcher.globToRegex("/api/*"), "^/api/[^/]*$")
        XCTAssertEqual(MapLocalMatcher.globToRegex("**"), ".*$")
        XCTAssertEqual(MapLocalMatcher.globToRegex("/api/**"), "^/api/.*$")
        // Leading `*` leaves the start unanchored (suffix matching)
        XCTAssertEqual(MapLocalMatcher.globToRegex("*.json"), "[^/]*\\.json$")
        XCTAssertEqual(MapLocalMatcher.globToRegex("/a.b"), "^/a\\.b$")
    }

    // MARK: - Host matching

    func testHostExactMatch() {
        let matcher = matcher([rule(host: "api.example.com")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "api.example.com", path: "/"))
        XCTAssertNil(matcher.firstMatch(method: "GET", host: "other.example.com", path: "/"))
    }

    func testHostCaseInsensitive() {
        let matcher = matcher([rule(host: "API.Example.COM")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "api.example.com", path: "/"))
    }

    func testHostWildcard() {
        let matcher = matcher([rule(host: "*.example.com")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "api.example.com", path: "/"))
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "sub.api.example.com", path: "/"))
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "example.com", path: "/"))
        XCTAssertNil(matcher.firstMatch(method: "GET", host: "example.org", path: "/"))
        XCTAssertNil(matcher.firstMatch(method: "GET", host: "notexample.com", path: "/"))
    }

    func testHostEmptyPatternMatchesEverything() {
        let matcher = matcher([rule(host: "")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "anything.org", path: "/"))
    }

    func testHostStarMatchesEverything() {
        let matcher = matcher([rule(host: "*")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "anything.org", path: "/"))
    }

    // MARK: - Path matching

    func testPathExact() {
        let matcher = matcher([rule(path: "/api/users")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/users"))
        XCTAssertNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/users/1"))
        XCTAssertNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/Users"))
    }

    func testPathSingleSegmentWildcard() {
        let matcher = matcher([rule(path: "/api/*")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/users"))
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/123"))
        // `*` does not cross `/`
        XCTAssertNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/users/1"))
    }

    func testPathDoubleStarWildcard() {
        let matcher = matcher([rule(path: "/api/**")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/users"))
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/users/1/details"))
        XCTAssertNil(matcher.firstMatch(method: "GET", host: "h", path: "/other"))
    }

    func testPathSuffixWildcard() {
        let shallow = matcher([rule(path: "*.json")])
        // Leading `*` → suffix match: any path ending in `.json`
        XCTAssertNotNil(shallow.firstMatch(method: "GET", host: "h", path: "/users.json"))
        XCTAssertNotNil(shallow.firstMatch(method: "GET", host: "h", path: "/data/users.json"))
        XCTAssertNil(shallow.firstMatch(method: "GET", host: "h", path: "/users.jsonx"))

        let deep = matcher([rule(path: "**.json")])
        XCTAssertNotNil(deep.firstMatch(method: "GET", host: "h", path: "/data/users.json"))
        XCTAssertNil(deep.firstMatch(method: "GET", host: "h", path: "/data/users.jsonx"))
    }

    func testPathCaseSensitivity() {
        let sensitive = matcher([rule(path: "/API/Users", caseSensitive: true)])
        XCTAssertNil(sensitive.firstMatch(method: "GET", host: "h", path: "/api/users"))

        let insensitive = matcher([rule(path: "/API/Users", caseSensitive: false)])
        XCTAssertNotNil(insensitive.firstMatch(method: "GET", host: "h", path: "/api/users"))
    }

    func testEmptyPathPatternMatchesEverything() {
        let matcher = matcher([rule(path: "")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/whatever"))
    }

    // MARK: - Method matching

    func testMethodAny() {
        let matcher = matcher([rule(method: "ANY")])
        for m in ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"] {
            XCTAssertNotNil(matcher.firstMatch(method: m, host: "h", path: "/"))
        }
    }

    func testMethodExactCaseInsensitive() {
        let matcher = matcher([rule(method: "get")])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/"))
        XCTAssertNil(matcher.firstMatch(method: "POST", host: "h", path: "/"))
    }

    // MARK: - Priority & enabled

    func testFirstMatchWins() {
        let first = rule(path: "/api/*")
        let second = rule(path: "/api/users")
        let matcher = matcher([first, second])
        // /api/users matches both; first rule must win
        let matched = matcher.firstMatch(method: "GET", host: "h", path: "/api/users")
        XCTAssertEqual(matched?.id, first.id)
    }

    func testDisabledRulesSkipped() {
        let enabled = rule(path: "/api/users")
        let disabled = rule(path: "/api/*", enabled: false)
        let matcher = matcher([disabled, enabled])
        XCTAssertEqual(matcher.firstMatch(method: "GET", host: "h", path: "/api/users")?.id, enabled.id)
    }

    func testHasPossibleMatch() {
        let matcher = matcher([rule(host: "*.example.com", path: "/api/**")])
        XCTAssertTrue(matcher.hasPossibleMatch(host: "api.example.com"))
        XCTAssertFalse(matcher.hasPossibleMatch(host: "other.org"))
    }

    // MARK: - Regex support

    func testRegexMatching() {
        let matcher = matcher([rule(path: #"^/api/v\d+/.*$"#, useRegex: true)])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/v1/users"))
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/v42/users/7"))
        XCTAssertNil(matcher.firstMatch(method: "GET", host: "h", path: "/api/v/users"))
    }

    func testRegexCaseInsensitive() {
        let matcher = matcher([rule(path: #"^/api/users$"#, caseSensitive: false, useRegex: true)])
        XCTAssertNotNil(matcher.firstMatch(method: "GET", host: "h", path: "/API/Users"))
    }

    func testInvalidRegexSkipped() {
        let matcher = matcher([rule(path: "[unclosed", useRegex: true)])
        // Invalid regex never matches (and is logged) instead of crashing
        XCTAssertNil(matcher.firstMatch(method: "GET", host: "h", path: "/api"))
    }

    // MARK: - Rule parsing

    func testFromDictionary() {
        let id = UUID()
        let dict: [String: Any] = [
            "id": id.uuidString,
            "hostPattern": "*.example.com",
            "pathPattern": "/api/*",
            "httpMethod": "POST",
            "filePath": "/tmp/response.json",
            "statusCode": 201,
            "contentType": "application/json",
            "customHeaders": ["X-Test": "1"],
            "isEnabled": false,
            "isCaseSensitive": false,
            "useRegex": true,
        ]
        guard let rule = MapLocalRule.fromDictionary(dict) else {
            return XCTFail("fromDictionary should parse a valid dict")
        }
        XCTAssertEqual(rule.id, id)
        XCTAssertEqual(rule.hostPattern, "*.example.com")
        XCTAssertEqual(rule.pathPattern, "/api/*")
        XCTAssertEqual(rule.httpMethod, "POST")
        XCTAssertEqual(rule.filePath, "/tmp/response.json")
        XCTAssertEqual(rule.statusCode, 201)
        XCTAssertEqual(rule.contentType, "application/json")
        XCTAssertEqual(rule.customHeaders, ["X-Test": "1"])
        XCTAssertFalse(rule.isEnabled)
        XCTAssertFalse(rule.isCaseSensitive)
        XCTAssertTrue(rule.useRegex)
    }

    func testFromDictionaryDefaults() {
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "pathPattern": "/",
            "filePath": "/tmp/a.txt",
        ]
        let rule = MapLocalRule.fromDictionary(dict)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.httpMethod, "ANY")
        XCTAssertEqual(rule?.statusCode, 200)
        XCTAssertTrue(rule?.isEnabled ?? false)
        XCTAssertTrue(rule?.isCaseSensitive ?? false)
        XCTAssertFalse(rule?.useRegex ?? true)
        XCTAssertEqual(rule?.hostPattern, "*")
    }

    func testFromDictionaryInvalid() {
        XCTAssertNil(MapLocalRule.fromDictionary(["pathPattern": "/"]))
        XCTAssertNil(MapLocalRule.fromDictionary(["id": "not-a-uuid", "pathPattern": "/", "filePath": "/tmp/a"]))
    }

    func testFromDictionaryInline() {
        let id = UUID()
        let dict: [String: Any] = [
            "id": id.uuidString,
            "hostPattern": "*.example.com",
            "pathPattern": "/api/*",
            "httpMethod": "POST",
            "responseSource": "inline",
            "inlineBody": "{\"ok\":true}",
            "statusCode": 201,
        ]
        guard let rule = MapLocalRule.fromDictionary(dict) else {
            return XCTFail("fromDictionary should parse a valid inline dict")
        }
        XCTAssertTrue(rule.isInline)
        XCTAssertEqual(rule.inlineBody, "{\"ok\":true}")
        XCTAssertEqual(rule.filePath, "")
        XCTAssertEqual(rule.statusCode, 201)
    }

    func testFromDictionaryInlineRejectsEmptyBody() {
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "pathPattern": "/",
            "responseSource": "inline",
        ]
        XCTAssertNil(MapLocalRule.fromDictionary(dict))

        let whitespace: [String: Any] = [
            "id": UUID().uuidString,
            "pathPattern": "/",
            "responseSource": "inline",
            "inlineBody": "   ",
        ]
        XCTAssertNotNil(MapLocalRule.fromDictionary(whitespace))
    }

    func testFromDictionaryFileRejectsEmptyPath() {
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "pathPattern": "/",
            "responseSource": "file",
        ]
        XCTAssertNil(MapLocalRule.fromDictionary(dict))
    }

    func testFromDictionaryFileDefaultsWhenSourceMissing() {
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "pathPattern": "/",
            "filePath": "/tmp/a.txt",
        ]
        let rule = MapLocalRule.fromDictionary(dict)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.responseSource, "file")
        XCTAssertNil(rule?.inlineBody)
    }

    // MARK: - Response building

    func testBuildResponseDefaults() {
        let rule = rule(path: "/api", filePath: "/tmp/response.json")
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data("{\"ok\":true}".utf8), modificationDate: nil)
        XCTAssertEqual(built.statusCode, 200)
        XCTAssertEqual(String(data: built.body, encoding: .utf8), "{\"ok\":true}")
        let headers = Dictionary(uniqueKeysWithValues: built.headers.map { ($0.name.lowercased(), $0.value) })
        XCTAssertEqual(headers["content-type"], "application/json")
        XCTAssertEqual(headers["content-length"], "11")
        XCTAssertEqual(headers["cache-control"], "no-cache")
        XCTAssertNil(headers["last-modified"])
    }

    func testBuildResponseCustomStatusAndContentType() {
        let rule = rule(path: "/api", filePath: "/tmp/data.bin", statusCode: 418, contentType: "application/octet-stream")
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data([0x01, 0x02]), modificationDate: nil)
        XCTAssertEqual(built.statusCode, 418)
        let headers = Dictionary(uniqueKeysWithValues: built.headers.map { ($0.name.lowercased(), $0.value) })
        XCTAssertEqual(headers["content-type"], "application/octet-stream")
        XCTAssertEqual(headers["content-length"], "2")
    }

    func testBuildResponseAutoDetectFallback() {
        let rule = rule(path: "/api", filePath: "/tmp/unknown.xyz")
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data(), modificationDate: nil)
        let headers = Dictionary(uniqueKeysWithValues: built.headers.map { ($0.name.lowercased(), $0.value) })
        XCTAssertNil(headers["content-type"])
    }

    func testBuildResponseLastModified() {
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let rule = rule(path: "/api", filePath: "/tmp/a.txt")
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data(), modificationDate: date)
        let headers = Dictionary(uniqueKeysWithValues: built.headers.map { ($0.name.lowercased(), $0.value) })
        XCTAssertEqual(headers["last-modified"], "Sun, 13 Sep 2020 12:26:40 GMT")
    }

    func testBuildResponseCustomHeadersAndSanitization() {
        let rule = rule(path: "/api", filePath: "/tmp/a.txt", customHeaders: [
            "X-Custom": "value",
            "Content-Length": "999",
            "Connection": "keep-alive",
            "x-extra": "1",
        ])
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data("hello".utf8), modificationDate: nil)
        let headers = Dictionary(uniqueKeysWithValues: built.headers.map { ($0.name, $0.value) })
        XCTAssertEqual(headers["X-Custom"], "value")
        XCTAssertEqual(headers["x-extra"], "1")
        // Protocol-critical headers must not be overridden
        XCTAssertEqual(headers["Content-Length"], "5")
        XCTAssertNil(headers["Connection"])
    }

    func testBuildResponseInvalidStatusCodeFallsBackTo200() {
        let rule = rule(path: "/api", filePath: "/tmp/a.txt", statusCode: 9999)
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data(), modificationDate: nil)
        XCTAssertEqual(built.statusCode, 200)
    }

    // MARK: - Inline response building

    func testBuildResponseInlineDefaults() {
        let rule = inlineRule(path: "/api", body: "{\"ok\":true}")
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data("{\"ok\":true}".utf8), modificationDate: nil)
        XCTAssertEqual(built.statusCode, 200)
        XCTAssertEqual(String(data: built.body, encoding: .utf8), "{\"ok\":true}")
        let headers = Dictionary(uniqueKeysWithValues: built.headers.map { ($0.name.lowercased(), $0.value) })
        XCTAssertEqual(headers["content-type"], "application/json")
        XCTAssertEqual(headers["content-length"], "11")
        XCTAssertEqual(headers["cache-control"], "no-cache")
        XCTAssertNil(headers["last-modified"])
    }

    func testBuildResponseInlineCustomContentTypeOverridesDefault() {
        let rule = inlineRule(path: "/api", body: "<p>hi</p>", contentType: "text/html; charset=utf-8")
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data("<p>hi</p>".utf8), modificationDate: nil)
        let headers = Dictionary(uniqueKeysWithValues: built.headers.map { ($0.name.lowercased(), $0.value) })
        XCTAssertEqual(headers["content-type"], "text/html; charset=utf-8")
    }

    func testBuildResponseInlineIgnoresModificationDate() {
        let rule = inlineRule(path: "/api", body: "{}")
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data("{}".utf8), modificationDate: date)
        let headers = Dictionary(uniqueKeysWithValues: built.headers.map { ($0.name.lowercased(), $0.value) })
        XCTAssertNil(headers["last-modified"])
    }

    func testBuildResponseInlineEmptyBodyData() {
        let rule = inlineRule(path: "/api", body: "")
        let built = MapLocalHandler.buildResponseSync(rule: rule, fileData: Data(), modificationDate: nil)
        let headers = Dictionary(uniqueKeysWithValues: built.headers.map { ($0.name.lowercased(), $0.value) })
        XCTAssertEqual(headers["content-type"], "application/json")
        XCTAssertEqual(headers["content-length"], "0")
    }

    // MARK: - Content type detection

    func testContentTypeDetection() {
        XCTAssertEqual(MapLocalHandler.contentType(forFile: "/tmp/x.json"), "application/json")
        XCTAssertEqual(MapLocalHandler.contentType(forFile: "/tmp/x.html"), "text/html; charset=utf-8")
        XCTAssertEqual(MapLocalHandler.contentType(forFile: "/tmp/x.PNG"), "image/png")
        XCTAssertEqual(MapLocalHandler.contentType(forFile: "/tmp/x.pdf"), "application/pdf")
        XCTAssertNil(MapLocalHandler.contentType(forFile: "/tmp/x.unknownext"))
    }

    // MARK: - Helpers

    private func rule(
        host: String = "*",
        path: String = "**",
        method: String = "ANY",
        filePath: String = "/tmp/response.txt",
        statusCode: Int = 200,
        contentType: String? = nil,
        customHeaders: [String: String] = [:],
        enabled: Bool = true,
        caseSensitive: Bool = true,
        useRegex: Bool = false
    ) -> MapLocalRule {
        MapLocalRule(
            hostPattern: host,
            pathPattern: path,
            httpMethod: method,
            filePath: filePath,
            statusCode: statusCode,
            contentType: contentType,
            customHeaders: customHeaders,
            isEnabled: enabled,
            isCaseSensitive: caseSensitive,
            useRegex: useRegex
        )
    }

    private func inlineRule(
        host: String = "*",
        path: String = "**",
        method: String = "ANY",
        body: String,
        statusCode: Int = 200,
        contentType: String? = nil,
        customHeaders: [String: String] = [:],
        enabled: Bool = true,
        caseSensitive: Bool = true,
        useRegex: Bool = false
    ) -> MapLocalRule {
        MapLocalRule(
            hostPattern: host,
            pathPattern: path,
            httpMethod: method,
            responseSource: MapLocalRule.sourceInline,
            inlineBody: body,
            statusCode: statusCode,
            contentType: contentType,
            customHeaders: customHeaders,
            isEnabled: enabled,
            isCaseSensitive: caseSensitive,
            useRegex: useRegex
        )
    }

    private func matcher(_ rules: [MapLocalRule]) -> MapLocalMatcher {
        MapLocalMatcher(rules: rules)
    }
}
