import Foundation
import NIOCore
import NIOHTTP1

/// Errors that can occur while serving a Map Local file.
enum MapLocalFileError: Error {
    case fileNotFound(String)
    case unreadable(String)
}

/// Serves local files for Map Local rules.
///
/// File reads happen on a background dispatch queue so the NIO event loop is
/// never blocked; the result is then scheduled back onto the caller's event
/// loop.
enum MapLocalHandler {

    /// A fully built HTTP response for a matched rule.
    struct BuiltResponse {
        let statusCode: Int
        let headers: [(name: String, value: String)]
        let body: Data
    }

    // MARK: - Serving

    /// Reads the mapped file off the event loop, then writes the response to
    /// the client channel and records the exchange as a completed Map Local
    /// exchange. `onComplete` mirrors the handler's own completion semantics
    /// (restore state, resume reads).
    static func serve(
        rule: MapLocalRule,
        context: ChannelHandlerContext,
        exchange: CapturedExchange,
        store: BridgeSessionStore,
        onComplete: @escaping () -> Void
    ) {
        ProxyMetrics.shared.incrementRequests()

        let eventLoop = context.eventLoop
        buildResponse(rule: rule, eventLoop: eventLoop) { result in
            switch result {
            case .success(let built):
                ProxyLogger.map.info(
                    "Map Local: serving %{public}@ (%d bytes, status %d) from %{public}@",
                    exchange.url, built.body.count, built.statusCode, rule.filePath
                )
                ProxyMetrics.shared.addSentBytes(Int64(built.body.count))

                var completed = exchange
                completed.isMapLocal = true
                completed.statusCode = built.statusCode
                completed.statusMessage = HTTPResponseStatus(statusCode: built.statusCode).reasonPhrase
                completed.responseHeaders = built.headers
                completed.responseSize = built.body.count
                completed.endTime = Date()
                if built.body.count > BodyContent.maxInMemorySize {
                    completed.responseBody = .truncated(built.body.prefix(BodyContent.maxInMemorySize), totalSize: built.body.count)
                } else {
                    completed.responseBody = .data(built.body)
                }
                completed.state = .completed
                store.updateOnActor(completed)

                var headers = HTTPHeaders()
                for (name, value) in built.headers { headers.add(name: name, value: value) }
                headers.add(name: "Connection", value: "close")
                let head = HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: built.statusCode), headers: headers)

                var buffer = context.channel.allocator.buffer(capacity: built.body.count)
                buffer.writeBytes(built.body)
                context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
                context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
                context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
                onComplete()

            case .failure(let error):
                let (status, message): (Int, String)
                switch error {
                case .fileNotFound(let path):
                    status = 404
                    message = "Map Local: file not found: \(path)"
                case .unreadable(let detail):
                    status = 500
                    message = "Map Local: cannot read file: \(detail)"
                }
                ProxyLogger.map.error("%{public}@", message)
                ProxyMetrics.shared.incrementErrors()

                var failed = exchange
                failed.isMapLocal = true
                failed.state = .failed(message)
                failed.endTime = Date()
                store.updateOnActor(failed)

                var headers = HTTPHeaders()
                headers.add(name: "Content-Type", value: "application/json")
                headers.add(name: "Content-Length", value: "0")
                headers.add(name: "Connection", value: "close")
                let head = HTTPResponseHead(version: .http1_1, status: HTTPResponseStatus(statusCode: status), headers: headers)
                context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
                context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
                onComplete()
            }
        }
    }

    // MARK: - Response building

    /// Reads the file asynchronously (global queue) and completes on the given
    /// event loop with a built response.
    static func buildResponse(
        rule: MapLocalRule,
        eventLoop: EventLoop,
        completion: @escaping (Result<BuiltResponse, MapLocalFileError>) -> Void
    ) {
        let filePath = rule.filePath
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<BuiltResponse, MapLocalFileError>
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
                let data = try Data(contentsOf: URL(fileURLWithPath: filePath), options: .mappedIfSafe)
                let modificationDate = attrs[.modificationDate] as? Date
                result = .success(buildResponseSync(rule: rule, fileData: data, modificationDate: modificationDate))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                result = .failure(.fileNotFound(filePath))
            } catch {
                result = .failure(.unreadable(error.localizedDescription))
            }
            eventLoop.execute { completion(result) }
        }
    }

    /// Pure response construction (no I/O) — used by `buildResponse` and by
    /// unit tests.
    static func buildResponseSync(
        rule: MapLocalRule,
        fileData: Data,
        modificationDate: Date?
    ) -> BuiltResponse {
        var headers: [(name: String, value: String)] = []

        let customContentType = rule.contentType?.trimmingCharacters(in: .whitespaces)
        if let customContentType, !customContentType.isEmpty {
            headers.append((name: "Content-Type", value: customContentType))
        } else if let detected = contentType(forFile: rule.filePath) {
            headers.append((name: "Content-Type", value: detected))
        }

        headers.append((name: "Content-Length", value: "\(fileData.count)"))

        if let modificationDate {
            headers.append((name: "Last-Modified", value: httpDate(modificationDate)))
        }

        headers.append((name: "Cache-Control", value: "no-cache"))

        // Custom headers last so they can override the defaults, except for
        // protocol-critical ones that the proxy must control.
        let protected = Set(["content-length", "connection", "transfer-encoding", "proxy-connection"])
        for (name, value) in rule.customHeaders {
            if protected.contains(name.lowercased()) { continue }
            headers.append((name: name, value: value))
        }

        return BuiltResponse(
            statusCode: (100...599).contains(rule.statusCode) ? rule.statusCode : 200,
            headers: headers,
            body: fileData
        )
    }

    // MARK: - Content type detection

    /// Content type auto-detected from the file extension.
    static func contentType(forFile path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "log", "csv":        return "text/plain; charset=utf-8"
        case "json":                     return "application/json"
        case "xml":                      return "application/xml"
        case "html", "htm":              return "text/html; charset=utf-8"
        case "css":                      return "text/css; charset=utf-8"
        case "js", "mjs":                return "application/javascript"
        case "png":                      return "image/png"
        case "jpg", "jpeg":              return "image/jpeg"
        case "gif":                      return "image/gif"
        case "svg":                      return "image/svg+xml"
        case "webp":                     return "image/webp"
        case "ico":                      return "image/x-icon"
        case "bmp":                      return "image/bmp"
        case "avif":                     return "image/avif"
        case "pdf":                      return "application/pdf"
        case "zip":                      return "application/zip"
        case "gz":                       return "application/gzip"
        case "wasm":                     return "application/wasm"
        case "woff":                     return "font/woff"
        case "woff2":                    return "font/woff2"
        case "ttf":                      return "font/ttf"
        case "otf":                      return "font/otf"
        case "eot":                      return "application/vnd.ms-fontobject"
        case "mp4", "m4v":               return "video/mp4"
        case "webm":                     return "video/webm"
        case "mp3":                      return "audio/mpeg"
        case "wav":                      return "audio/wav"
        case "ogg":                      return "audio/ogg"
        case "webmanifest":              return "application/manifest+json"
        case "map":                      return "application/json"
        case "md":                       return "text/markdown; charset=utf-8"
        case "yaml", "yml":              return "application/yaml"
        default:                         return nil
        }
    }

    // MARK: - HTTP date

    /// Formats a date as an HTTP-date (RFC 9110, IMF-fixdate).
    static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}

private extension BridgeSessionStore {
    /// Same as `update` but callable from any thread (hops to MainActor).
    func updateOnActor(_ exchange: CapturedExchange) {
        Task { @MainActor in update(exchange) }
    }
}
