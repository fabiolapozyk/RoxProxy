import Foundation
import XCTest

final class BodyStoreTests: XCTestCase {

    func testStoreAndFetchBodies() {
        let store = BodyStore()
        var exchange = CapturedExchange(
            method: "POST",
            url: "http://example.com/api",
            host: "example.com",
            requestHeaders: [("Content-Type", "application/json")]
        )
        exchange.requestBody = .data(Data("request body".utf8))
        exchange.responseBody = .data(Data("response body".utf8))

        let refs = store.store(exchange: exchange)
        XCTAssertNotNil(refs.request)
        XCTAssertNotNil(refs.response)

        XCTAssertEqual(store.fetch(ref: refs.request!), Data("request body".utf8))
        XCTAssertEqual(store.fetch(ref: refs.response!), Data("response body".utf8))
    }

    func testEmptyBodiesProduceNilRefs() {
        let store = BodyStore()
        var exchange = CapturedExchange(method: "GET", url: "http://example.com/", host: "example.com")
        exchange.requestBody = .empty

        let refs = store.store(exchange: exchange)
        XCTAssertNil(refs.request)
        XCTAssertNil(refs.response)
    }

    func testReleaseAndFetch() {
        let store = BodyStore()
        var exchange = CapturedExchange(method: "GET", url: "http://example.com/", host: "example.com")
        exchange.responseBody = .data(Data("payload".utf8))

        let refs = store.store(exchange: exchange)
        let ref = refs.response!
        XCTAssertNotNil(store.fetch(ref: ref))

        store.release(ref: ref)
        XCTAssertNil(store.fetch(ref: ref))
    }

    func testReleaseAll() {
        let store = BodyStore()
        var exchange = CapturedExchange(method: "GET", url: "http://example.com/", host: "example.com")
        exchange.responseBody = .data(Data("payload".utf8))

        let refs = store.store(exchange: exchange)
        store.releaseAll()
        XCTAssertNil(store.fetch(ref: refs.response!))
    }

    // MARK: - Imported bodies (session reopen, issue #13)

    func testStoreBodyReturnsRefAndIsFetchable() {
        let store = BodyStore()
        let ref = store.storeBody(data: Data("imported".utf8))

        XCTAssertNotNil(ref)
        XCTAssertEqual(store.fetch(ref: ref!), Data("imported".utf8))
    }

    func testStoreBodyRejectsEmptyData() {
        let store = BodyStore()
        XCTAssertNil(store.storeBody(data: Data()))
    }

    func testImportedBodyIsReleasedWithReleaseAll() {
        let store = BodyStore()
        let ref = store.storeBody(data: Data("imported".utf8))!

        // Opening another session / clearing the list must not leak imported bodies.
        store.releaseAll()
        XCTAssertNil(store.fetch(ref: ref))
    }
}
