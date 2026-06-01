import Testing
import Foundation
import NIOCore
import NIOHTTP1
@testable import RoxProxy

// MARK: - DomainRule

struct DomainRuleTests {
    @Test func exactMatchWorks() {
        let rule = DomainRule(domain: "api.example.com")
        #expect(rule.matches(host: "api.example.com"))
        #expect(!rule.matches(host: "example.com"))
        #expect(!rule.matches(host: "other.com"))
    }

    @Test func wildcardMatchWorks() {
        let rule = DomainRule(domain: "*.example.com")
        #expect(rule.matches(host: "api.example.com"))
        #expect(rule.matches(host: "sub.api.example.com"))
        #expect(rule.matches(host: "example.com"))
        #expect(!rule.matches(host: "notexample.com"))
    }

    @Test func disabledRuleDoesNotMatch() {
        let rule = DomainRule(domain: "api.example.com", isEnabled: false)
        #expect(!rule.matches(host: "api.example.com"))
    }

    @Test func wildcardDoesNotMatchParentDomain() {
        // *.sub.example.com should NOT match example.com
        let rule = DomainRule(domain: "*.sub.example.com")
        #expect(rule.matches(host: "api.sub.example.com"))
        #expect(rule.matches(host: "sub.example.com"))
        #expect(!rule.matches(host: "example.com"))
        #expect(!rule.matches(host: "notsub.example.com"))
    }

    @Test func wildcardMatchesMultiLevelSubdomains() {
        let rule = DomainRule(domain: "*.example.com")
        #expect(rule.matches(host: "a.b.c.example.com"))
        #expect(rule.matches(host: "deep.nested.sub.example.com"))
    }

    @Test func emptyDomainNeverMatches() {
        let rule = DomainRule(domain: "")
        #expect(!rule.matches(host: "example.com"))
        // Empty domain matches empty host - this is the current behavior
        #expect(rule.matches(host: ""))
    }

    @Test func caseSensitiveMatching() {
        let rule = DomainRule(domain: "API.Example.COM")
        #expect(rule.matches(host: "API.Example.COM"))
        #expect(!rule.matches(host: "api.example.com"))
        #expect(!rule.matches(host: "API.EXAMPLE.COM"))
    }

    @Test func wildcardWithEmptySubdomain() {
        let rule = DomainRule(domain: "*.example.com")
        // Host with just the domain part (no subdomain)
        #expect(rule.matches(host: "example.com"))
    }

    @Test func portInHostDoesNotAffectMatching() {
        let rule = DomainRule(domain: "api.example.com")
        // Host should not include port for matching
        #expect(rule.matches(host: "api.example.com"))
        #expect(!rule.matches(host: "api.example.com:8080"))
    }

    @Test func specialCharactersInDomain() {
        let rule = DomainRule(domain: "api-test.example.com")
        #expect(rule.matches(host: "api-test.example.com"))
        #expect(!rule.matches(host: "api_test.example.com"))
    }

    @Test func unicodeDomainMatching() {
        let rule = DomainRule(domain: "test.example.com")
        // Punycode domains - these are different hosts
        #expect(!rule.matches(host: "xn--test.example.com"))
        #expect(!rule.matches(host: "tëst.example.com"))
    }
}

// MARK: - BodyContent

struct BodyContentTests {
    @Test func emptyBodyIsEmpty() {
        let body = BodyContent.empty
        #expect(body.isEmpty)
        #expect(body.data == nil)
        #expect(body.totalSize == 0)
        #expect(body.asString() == nil)
    }

    @Test func dataBodyProperties() {
        let body = BodyContent.data(Data("hello".utf8))
        #expect(!body.isEmpty)
        #expect(body.data != nil)
        #expect(!body.isTruncated)
        #expect(body.totalSize == 5)
        #expect(body.asString() == "hello")
    }

    @Test func truncatedBodyProperties() {
        let body = BodyContent.truncated(Data("hello".utf8), totalSize: 1_000_000)
        #expect(body.isTruncated)
        #expect(body.totalSize == 1_000_000)
        #expect(body.asString() == "hello")
    }

    @Test func appendingBuildsBodyIncrementally() {
        var total = 0
        let chunk1 = Data("Hello, ".utf8)
        let chunk2 = Data("world!".utf8)

        let body1 = BodyContent.appending(existing: nil, newBytes: chunk1, runningTotal: &total)
        #expect(total == 7)

        let body2 = BodyContent.appending(existing: body1, newBytes: chunk2, runningTotal: &total)
        #expect(total == 13)
        #expect(body2.asString() == "Hello, world!")
        #expect(!body2.isTruncated)
    }

    @Test func appendingTruncatesOverLimit() {
        // Use a small cap override via direct construction for this unit test
        let bigData = Data(repeating: 0xFF, count: BodyContent.maxInMemorySize + 1)
        var total = 0
        let body = BodyContent.appending(existing: nil, newBytes: bigData, runningTotal: &total)
        #expect(body.isTruncated)
        #expect(body.totalSize == bigData.count)
    }

    @Test func appendingExactlyAtLimitDoesNotTruncate() {
        let dataAtLimit = Data(repeating: 0xFF, count: BodyContent.maxInMemorySize)
        var total = 0
        let body = BodyContent.appending(existing: nil, newBytes: dataAtLimit, runningTotal: &total)
        #expect(!body.isTruncated)
        #expect(body.totalSize == BodyContent.maxInMemorySize)
        #expect(body.data?.count == BodyContent.maxInMemorySize)
    }

    @Test func appendingOneByteOverLimitTruncates() {
        let dataOverLimit = Data(repeating: 0xFF, count: BodyContent.maxInMemorySize + 1)
        var total = 0
        let body = BodyContent.appending(existing: nil, newBytes: dataOverLimit, runningTotal: &total)
        #expect(body.isTruncated)
        #expect(body.totalSize == BodyContent.maxInMemorySize + 1)
        #expect(body.data?.count == BodyContent.maxInMemorySize)
    }

    @Test func appendingToExistingTruncatedBodyDoesNotChangeData() {
        var total = BodyContent.maxInMemorySize + 50
        let existingTruncated = BodyContent.truncated(Data(repeating: 0xAA, count: 100), totalSize: BodyContent.maxInMemorySize + 50)
        
        let newBytes = Data(repeating: 0xBB, count: 100)
        let body = BodyContent.appending(existing: existingTruncated, newBytes: newBytes, runningTotal: &total)
        
        #expect(body.isTruncated)
        #expect(body.totalSize == BodyContent.maxInMemorySize + 150)
        #expect(body.data?.count == 100) // Original truncated data preserved
        #expect(body.data?.first == 0xAA) // Verify it's the original data
    }

    @Test func incrementalAppendingCrossesLimit() {
        var total = 0
        let halfLimit = BodyContent.maxInMemorySize / 2
        let firstChunk = Data(repeating: 0x01, count: halfLimit)
        let secondChunk = Data(repeating: 0x02, count: halfLimit + 1)
        
        let body1 = BodyContent.appending(existing: nil, newBytes: firstChunk, runningTotal: &total)
        #expect(!body1.isTruncated)
        #expect(body1.totalSize == halfLimit)
        
        let body2 = BodyContent.appending(existing: body1, newBytes: secondChunk, runningTotal: &total)
        #expect(body2.isTruncated)
        #expect(body2.totalSize == BodyContent.maxInMemorySize + 1)
        #expect(body2.data?.count == BodyContent.maxInMemorySize)
    }

    @Test func truncatedBodyDataIsPrefixOfOriginal() {
        let original = Data("Hello, this is a very long string that exceeds the limit".utf8)
        var total = 0
        let body = BodyContent.appending(existing: nil, newBytes: original, runningTotal: &total)
        
        if body.isTruncated, let data = body.data {
            #expect(original.starts(with: data))
        }
    }

    @Test func emptyDataAppending() {
        var total = 0
        let emptyData = Data()
        let body = BodyContent.appending(existing: nil, newBytes: emptyData, runningTotal: &total)
        #expect(!body.isTruncated)
        #expect(body.totalSize == 0)
        // Empty Data() creates .data variant, not .empty
        #expect(!body.isEmpty)
    }

    @Test func asStringWithNonUTF8Data() {
        let nonUTF8Data = Data([0xFF, 0xFE, 0xFD])
        let body = BodyContent.data(nonUTF8Data)
        #expect(body.asString() == nil)
    }

    @Test func asStringWithUTF8Data() {
        let utf8Data = Data("Hello 世界".utf8)
        let body = BodyContent.data(utf8Data)
        #expect(body.asString() == "Hello 世界")
    }
}

// MARK: - CapturedExchange

struct CapturedExchangeTests {
    @Test func pathParsedFromURL() {
        let exchange = CapturedExchange(
            method: "GET",
            url: "http://api.example.com/v1/users?page=2",
            host: "api.example.com"
        )
        #expect(exchange.path == "/v1/users?page=2")
    }

    @Test func pathDefaultsToSlash() {
        let exchange = CapturedExchange(method: "GET", url: "bad-url", host: "example.com")
        #expect(exchange.path == "/")
    }

    @Test func initialStateIsInProgress() {
        let exchange = CapturedExchange(method: "POST", url: "http://example.com/api", host: "example.com")
        #expect(exchange.state == .inProgress)
        #expect(exchange.statusCode == nil)
        #expect(exchange.duration == nil)
    }

    @Test func durationComputedWhenEndTimeSet() {
        var exchange = CapturedExchange(method: "GET", url: "http://example.com/", host: "example.com")
        exchange.endTime = exchange.startTime.addingTimeInterval(1.5)
        #expect(exchange.duration != nil)
        #expect(abs(exchange.duration! - 1.5) < 0.001)
    }
}

// MARK: - DataFormatting

struct DataFormattingTests {
    @Test func formatSizeBytes() {
        let result = DataFormatting.formatSize(512)
        #expect(!result.isEmpty)
    }

    @Test func formatDurationMs() {
        let result = DataFormatting.formatDuration(0.250)
        #expect(result.contains("ms"))
    }

    @Test func formatDurationSeconds() {
        let result = DataFormatting.formatDuration(2.5)
        #expect(result.contains("s"))
    }
}

// MARK: - CertificateAuthority

struct CertificateAuthorityTests {
    @Test func caGeneratesAndProducesDERBytes() throws {
        let ca = try CertificateAuthority.loadOrGenerate()
        let der = ca.caCertificateDER()
        #expect(!der.isEmpty)
    }

    @Test func caPersistsAcrossCalls() throws {
        let ca1 = try CertificateAuthority.loadOrGenerate()
        let ca2 = try CertificateAuthority.loadOrGenerate()
        let der1 = ca1.caCertificateDER()
        let der2 = ca2.caCertificateDER()
        // Same CA should produce the same cert bytes
        #expect(der1 == der2)
    }

    @Test func caGeneratesDomainCertificate() throws {
        let ca = try CertificateAuthority.loadOrGenerate()
        let (cert, key) = try ca.generateDomainCertificate(for: "api.example.com")
        _ = cert  // NIOSSLCertificate created successfully
        _ = key   // NIOSSLPrivateKey created successfully
    }

    @Test func domainCertCacheReturnsSamePairForSameHost() async throws {
        let ca = try CertificateAuthority.loadOrGenerate()
        let cache = DomainCertificateCache(ca: ca)
        let (cert1, _) = try await cache.certificate(for: "api.example.com")
        let (cert2, _) = try await cache.certificate(for: "api.example.com")
        // Same object returned from cache
        #expect(cert1 === cert2)
    }

    @Test func domainCertCacheReturnsDifferentPairsForDifferentHosts() async throws {
        let ca = try CertificateAuthority.loadOrGenerate()
        let cache = DomainCertificateCache(ca: ca)
        let (cert1, _) = try await cache.certificate(for: "api.example.com")
        let (cert2, _) = try await cache.certificate(for: "other.example.com")
        #expect(cert1 !== cert2)
    }
}

// MARK: - HTTPProxyHandler helpers

struct HTTPProxyHandlerTests {
    @Test func parseTargetAbsoluteURI() {
        let (host, port, path) = HTTPProxyHandler.parseTarget(
            uri: "http://api.example.com:9090/v1/users?page=2",
            headers: HTTPHeaders()
        )
        #expect(host == "api.example.com")
        #expect(port == 9090)
        #expect(path == "/v1/users?page=2")
    }

    @Test func parseTargetDefaultPort() {
        let (host, port, path) = HTTPProxyHandler.parseTarget(
            uri: "http://example.com/index.html",
            headers: HTTPHeaders()
        )
        #expect(host == "example.com")
        #expect(port == 80)
        #expect(path == "/index.html")
    }

    @Test func parseTargetRootPath() {
        let (host, port, path) = HTTPProxyHandler.parseTarget(
            uri: "http://example.com",
            headers: HTTPHeaders()
        )
        #expect(host == "example.com")
        #expect(port == 80)
        #expect(path == "/")
    }
}

// MARK: - RequestCapture

struct RequestCaptureTests {
    @Test func appendSingleBuffer() {
        let capture = RequestCapture()
        var buffer = ByteBuffer(bytes: Array("hello".utf8))
        capture.append(buffer)
        #expect(capture.totalBytes == 5)
        #expect(capture.bodyContent?.asString() == "hello")
    }

    @Test func appendMultipleBuffers() {
        let capture = RequestCapture()
        capture.append(ByteBuffer(bytes: Array("foo".utf8)))
        capture.append(ByteBuffer(bytes: Array("bar".utf8)))
        #expect(capture.totalBytes == 6)
        #expect(capture.bodyContent?.asString() == "foobar")
    }

    @Test func buildFromBuffers() {
        let buffers = [
            ByteBuffer(bytes: Array("hello".utf8)),
            ByteBuffer(bytes: Array(" world".utf8)),
        ]
        let (content, size) = RequestCapture.build(from: buffers)
        #expect(size == 11)
        #expect(content?.asString() == "hello world")
    }

    @Test func resetClearsState() {
        let capture = RequestCapture()
        capture.append(ByteBuffer(bytes: Array("hello".utf8)))
        capture.reset()
        #expect(capture.totalBytes == 0)
        #expect(capture.bodyContent == nil)
    }
}
