import Foundation
import XCTest

final class ExchangeSerializerTests: XCTestCase {

    private func makeExchange() -> CapturedExchange {
        CapturedExchange(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            startTime: Date(timeIntervalSince1970: 1_000_000),
            method: "POST",
            url: "https://api.example.com/v1/users?active=true",
            scheme: "https",
            host: "api.example.com",
            port: 443,
            requestHeaders: [("Content-Type", "application/json")],
            requestSize: 42,
            isHTTPS: true,
            isMITMDecrypted: true
        )
    }

    func testSerializeBasicFields() {
        let exchange = makeExchange()
        let dict = ExchangeSerializer.serialize(exchange, bodyRefs: (nil, nil))

        XCTAssertEqual(dict["id"] as? String, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(dict["method"] as? String, "POST")
        XCTAssertEqual(dict["url"] as? String, "https://api.example.com/v1/users?active=true")
        XCTAssertEqual(dict["scheme"] as? String, "https")
        XCTAssertEqual(dict["host"] as? String, "api.example.com")
        XCTAssertEqual(dict["port"] as? Int, 443)
        XCTAssertEqual(dict["path"] as? String, "/v1/users?active=true")
        XCTAssertEqual(dict["isHTTPS"] as? Bool, true)
        XCTAssertEqual(dict["isMITMDecrypted"] as? Bool, true)
        XCTAssertEqual(dict["state"] as? String, "inProgress")
    }

    func testSerializeWithBodyRefs() {
        let exchange = makeExchange()
        let dict = ExchangeSerializer.serialize(exchange, bodyRefs: ("req-ref", "res-ref"))

        XCTAssertEqual(dict["requestBodyRef"] as? String, "req-ref")
        XCTAssertEqual(dict["responseBodyRef"] as? String, "res-ref")
    }

    func testSerializeHeaders() {
        let exchange = makeExchange()
        let dict = ExchangeSerializer.serialize(exchange, bodyRefs: (nil, nil))

        let headers = dict["requestHeaders"] as? [[String: String]]
        XCTAssertEqual(headers?.first?["name"], "Content-Type")
        XCTAssertEqual(headers?.first?["value"], "application/json")
    }

    func testSerializeFailedStateIncludesError() {
        var exchange = makeExchange()
        exchange.state = .failed("Connection refused")
        exchange.endTime = Date()
        exchange.statusCode = nil

        let dict = ExchangeSerializer.serialize(exchange, bodyRefs: (nil, nil))
        XCTAssertEqual(dict["state"] as? String, "failed")
        XCTAssertEqual(dict["errorMessage"] as? String, "Connection refused")
        XCTAssertNotNil(dict["endTime"])
    }

    func testSerializeCompletedState() {
        var exchange = makeExchange()
        exchange.state = .completed
        exchange.statusCode = 200
        exchange.statusMessage = "OK"

        let dict = ExchangeSerializer.serialize(exchange, bodyRefs: (nil, nil))
        XCTAssertEqual(dict["state"] as? String, "completed")
        XCTAssertEqual(dict["statusCode"] as? Int, 200)
        XCTAssertEqual(dict["errorMessage"] as? String, nil)
    }
}
