import Foundation
import Compression
import XCTest

final class GzipDecompressorTests: XCTestCase {

    // MARK: - Helpers

    /// Apple's `.zlib` compression algorithm is actually raw DEFLATE (RFC 1951),
    /// so this returns the deflate payload with no wrapper.
    private func rawDeflate(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .zlib) as Data
    }

    /// Builds a real zlib stream (RFC 1950): 2-byte header + deflate + Adler-32.
    private func zlibData(_ data: Data) throws -> Data {
        var zlib = Data([0x78, 0x9c])
        zlib.append(try rawDeflate(data))
        zlib.append(adler32(data))
        return zlib
    }

    /// Builds a real gzip stream: 10-byte header + raw deflate + CRC32 + ISIZE.
    private func gzipData(_ data: Data) throws -> Data {
        var gzip = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff])
        gzip.append(try rawDeflate(data))
        gzip.append(crc32(data))
        gzip.append(contentsOf: withUnsafeBytes(of: UInt32(data.count).littleEndian) { Data($0) })
        return gzip
    }

    private func crc32(_ data: Data) -> Data {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
            }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        crc ^= 0xFFFFFFFF
        return withUnsafeBytes(of: crc.littleEndian) { Data($0) }
    }

    private func adler32(_ data: Data) -> Data {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let value = (b << 16) | a
        return withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    // MARK: - Tests

    func testDecompressGzip() throws {
        let original = Data("Hello RoxProxy".utf8)
        let decompressed = try GzipDecompressor.decompress(gzip: gzipData(original))
        XCTAssertEqual(decompressed, original)
    }

    func testDecompressZlib() throws {
        let original = Data("zlib wrapped body".utf8)
        let decompressed = try GzipDecompressor.decompress(zlib: zlibData(original))
        XCTAssertEqual(decompressed, original)
    }

    func testDecodeByContentEncoding() throws {
        let original = Data("encoded body".utf8)
        let gz = try gzipData(original)
        XCTAssertEqual(GzipDecompressor.decode(data: gz, contentEncoding: "gzip"), original)
        XCTAssertEqual(GzipDecompressor.decode(data: gz, contentEncoding: "GZIP"), original)
    }

    func testDecodeDeflateFallsBackToRaw() throws {
        let original = Data("deflate body".utf8)
        let z = try zlibData(original)
        XCTAssertEqual(GzipDecompressor.decode(data: z, contentEncoding: "deflate"), original)
    }

    func testDecodeIdentityPassthrough() {
        let data = Data("plain".utf8)
        XCTAssertEqual(GzipDecompressor.decode(data: data, contentEncoding: "identity"), data)
        XCTAssertEqual(GzipDecompressor.decode(data: data, contentEncoding: ""), data)
    }

    func testUnsupportedEncodingReturnsNil() {
        let data = Data("x".utf8)
        XCTAssertNil(GzipDecompressor.decode(data: data, contentEncoding: "br"))
        XCTAssertNil(GzipDecompressor.decode(data: data, contentEncoding: "garbage"))
    }

    func testDecompressRejectsTooSmallInput() {
        XCTAssertThrowsError(try GzipDecompressor.decompress(gzip: Data("short".utf8)))
    }
}
