import Foundation
import XCTest

final class DomainRuleTests: XCTestCase {

    // MARK: - Exact matching

    func testExactMatchWorks() {
        let rule = DomainRule(domain: "api.example.com")
        XCTAssertTrue(rule.matches(host: "api.example.com"))
        XCTAssertFalse(rule.matches(host: "example.com"))
        XCTAssertFalse(rule.matches(host: "other.com"))
    }

    // MARK: - Wildcard matching

    func testWildcardMatchWorks() {
        let rule = DomainRule(domain: "*.example.com")
        XCTAssertTrue(rule.matches(host: "api.example.com"))
        XCTAssertTrue(rule.matches(host: "sub.api.example.com"))
        XCTAssertTrue(rule.matches(host: "example.com"))
        XCTAssertFalse(rule.matches(host: "notexample.com"))
    }

    func testWildcardMatchesMultiLevelSubdomains() {
        let rule = DomainRule(domain: "*.example.com")
        XCTAssertTrue(rule.matches(host: "a.b.c.example.com"))
        XCTAssertTrue(rule.matches(host: "deep.nested.sub.example.com"))
    }

    func testWildcardDoesNotMatchParentDomain() {
        let rule = DomainRule(domain: "*.sub.example.com")
        XCTAssertTrue(rule.matches(host: "api.sub.example.com"))
        XCTAssertTrue(rule.matches(host: "sub.example.com"))
        XCTAssertFalse(rule.matches(host: "example.com"))
        XCTAssertFalse(rule.matches(host: "notsub.example.com"))
    }

    // MARK: - Edge cases

    func testDisabledRuleDoesNotMatch() {
        let rule = DomainRule(domain: "api.example.com", isEnabled: false)
        XCTAssertFalse(rule.matches(host: "api.example.com"))
    }

    func testEmptyDomainNeverMatches() {
        let rule = DomainRule(domain: "")
        XCTAssertFalse(rule.matches(host: "example.com"))
    }

    func testCaseSensitiveMatching() {
        let rule = DomainRule(domain: "API.Example.COM")
        XCTAssertTrue(rule.matches(host: "API.Example.COM"))
        XCTAssertFalse(rule.matches(host: "api.example.com"))
    }

    func testPortInHostDoesNotAffectMatching() {
        let rule = DomainRule(domain: "api.example.com")
        XCTAssertTrue(rule.matches(host: "api.example.com"))
        XCTAssertFalse(rule.matches(host: "api.example.com:8080"))
    }
}
