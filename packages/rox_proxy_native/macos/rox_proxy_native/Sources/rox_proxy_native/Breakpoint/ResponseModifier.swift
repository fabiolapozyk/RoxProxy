import Foundation
import NIOCore
import NIOHTTP1

/// Applies the user's breakpoint modifications (status/headers/body) to a
/// suspended response before it is forwarded to the client. Pure NIO,
/// unit-testable.
enum ResponseModifier {

    struct Result {
        var head: HTTPResponseHead
        var bodyParts: [ByteBuffer]
        /// Exchange updated to reflect the modified response.
        var exchange: CapturedExchange
    }

    /// Applies status, headers and body changes.
    ///
    /// When the body is not modified, `exchange.responseBody`/`responseSize`
    /// are left nil so the caller fills them from its own capture.
    static func apply(
        response: BreakpointResponse,
        originalHead: HTTPResponseHead,
        bodyParts: [ByteBuffer],
        exchange: CapturedExchange,
        allocator: ByteBufferAllocator
    ) -> Result {
        var head = originalHead
        var newBodyParts = bodyParts
        var updated = exchange

        // Status — valid codes only; the original status is kept otherwise.
        if let status = response.modifiedStatus, (100...599).contains(status) {
            head = HTTPResponseHead(
                version: originalHead.version,
                status: HTTPResponseStatus(statusCode: status),
                headers: originalHead.headers
            )
            updated.statusCode = status
            updated.statusMessage = HTTPResponseStatus(statusCode: status).reasonPhrase
        }

        // Headers — replace the whole list, protecting protocol-critical ones.
        if let modifiedHeaders = response.modifiedHeaders {
            let protected = Set([
                "content-length", "transfer-encoding",
                "connection", "proxy-connection", "keep-alive",
            ])
            var newHeaders = HTTPHeaders()
            for (name, value) in modifiedHeaders
            where !protected.contains(name.lowercased()) {
                newHeaders.add(name: name, value: value)
            }
            head.headers = newHeaders
            // Body is unchanged: restore the framing headers that were
            // stripped as protected.
            if response.modifiedBody == nil {
                if let length = originalHead.headers.first(name: "Content-Length") {
                    head.headers.add(name: "Content-Length", value: length)
                } else if let encoding = originalHead.headers.first(name: "Transfer-Encoding") {
                    head.headers.add(name: "Transfer-Encoding", value: encoding)
                }
            }
        }

        // Body — rebuild the buffer and fix Content-Length.
        if let bodyString = response.modifiedBody {
            var buffer = allocator.buffer(capacity: bodyString.utf8.count)
            buffer.writeString(bodyString)
            newBodyParts = [buffer]
            head.headers.remove(name: "Content-Length")
            head.headers.remove(name: "Transfer-Encoding")
            head.headers.add(name: "Content-Length", value: "\(bodyString.utf8.count)")
            updated.responseBody = bodyString.isEmpty ? .empty : .data(Data(bodyString.utf8))
            updated.responseSize = bodyString.utf8.count
        }

        updated.isBreakpoint = true
        updated.responseHeaders = head.headers.map { (name: $0.name, value: $0.value) }

        return Result(head: head, bodyParts: newBodyParts, exchange: updated)
    }
}
