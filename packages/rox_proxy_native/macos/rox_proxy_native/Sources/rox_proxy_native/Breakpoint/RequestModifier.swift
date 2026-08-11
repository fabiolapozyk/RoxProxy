import Foundation
import NIOCore
import NIOHTTP1

/// Applies the user's breakpoint modifications (RF4) to an HTTP request
/// before it is forwarded upstream. Pure NIO, unit-testable.
enum RequestModifier {

    struct Result {
        var head: HTTPRequestHead
        var bodyParts: [ByteBuffer]
        /// Upstream target after the decision (host never changes in v1).
        var host: String
        var port: Int
        /// Path + query sent upstream.
        var relativePath: String
        /// Exchange updated to reflect the modified request.
        var exchange: CapturedExchange
    }

    /// Applies method, URL (path/query), headers and body modifications.
    ///
    /// Host changes are never applied in v1 (RF4.3): with `fixedHost` set
    /// (MITM) the host is pinned; otherwise a different host in the modified
    /// URL is logged and ignored. Only the path/query part of the URL is used.
    static func apply(
        response: BreakpointResponse,
        originalHead: HTTPRequestHead,
        bodyParts: [ByteBuffer],
        originalHost: String,
        originalPort: Int,
        originalRelativePath: String,
        exchange: CapturedExchange,
        allocator: ByteBufferAllocator,
        fixedHost: String? = nil
    ) -> Result {
        var head = originalHead
        var newBodyParts = bodyParts
        var relativePath = originalRelativePath
        let host = fixedHost ?? originalHost
        let port = originalPort

        // Method — never allow CONNECT through the modified path.
        if let method = response.modifiedMethod?
            .trimmingCharacters(in: .whitespaces),
           !method.isEmpty, method.uppercased() != "CONNECT" {
            head.method = HTTPMethod(rawValue: method)
        }

        // URL — path/query only; host/port changes are rejected. The head URI
        // is rewritten to the (possibly modified) path so the outbound
        // forwarder always sends the version the user chose.
        if let urlString = response.modifiedUrl, let url = URL(string: urlString) {
            var path = url.path.isEmpty ? "/" : url.path
            if let query = url.query { path += "?" + query }
            relativePath = path
            head.uri = path
            if let urlHost = url.host, !urlHost.isEmpty,
               urlHost.lowercased() != host.lowercased() || url.port != nil && url.port != port {
                ProxyLogger.breakpoint.default(
                    "Breakpoint: host/port change in %{public}@ ignored (not supported in v1)",
                    urlString
                )
            }
        }

        // Headers — replace the whole list, protecting protocol-critical ones.
        if let modifiedHeaders = response.modifiedHeaders {
            let protected = Set([
                "host", "content-length", "transfer-encoding",
                "connection", "proxy-connection", "proxy-authorization",
            ])
            var newHeaders = HTTPHeaders()
            for (name, value) in modifiedHeaders
            where !protected.contains(name.lowercased()) {
                newHeaders.add(name: name, value: value)
            }
            head.headers = newHeaders
            head.headers.replaceOrAdd(name: "Host", value: host)
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
        }

        var updated = exchange
        updated.isBreakpoint = true
        updated.method = head.method.rawValue
        updated.url = Self.absoluteURL(scheme: exchange.scheme, host: host, port: port, path: relativePath)
        updated.path = relativePath
        updated.requestHeaders = head.headers.map { (name: $0.name, value: $0.value) }
        if let bodyString = response.modifiedBody {
            updated.requestBody = bodyString.isEmpty ? .empty : .data(Data(bodyString.utf8))
            updated.requestSize = bodyString.utf8.count
        }

        return Result(
            head: head,
            bodyParts: newBodyParts,
            host: host,
            port: port,
            relativePath: relativePath,
            exchange: updated
        )
    }

    /// Rebuilds an absolute URL for the exchange record.
    private static func absoluteURL(scheme: String, host: String, port: Int, path: String) -> String {
        var url = "\(scheme)://\(host)"
        let defaultPort = scheme == "https" ? 443 : 80
        if port != defaultPort { url += ":\(port)" }
        return url + path
    }
}
