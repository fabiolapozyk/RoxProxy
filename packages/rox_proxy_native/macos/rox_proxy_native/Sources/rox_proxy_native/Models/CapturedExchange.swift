import Foundation

struct CapturedExchange: Identifiable, Sendable {
    let id: UUID
    let startTime: Date
    var endTime: Date?

    // Request
    var method: String
    var url: String
    var scheme: String          // "http" or "https"
    var host: String
    var port: Int               // target port (80, 443, or custom)
    var path: String            // path + query, parsed from URL
    var requestHeaders: [(name: String, value: String)]
    var requestBody: BodyContent?

    // Response (nil while in-flight)
    var statusCode: Int?
    var statusMessage: String?
    var responseHeaders: [(name: String, value: String)]?
    var responseBody: BodyContent?

    // Metadata
    var duration: TimeInterval? { endTime.map { $0.timeIntervalSince(startTime) } }
    var requestSize: Int
    var responseSize: Int?
    var isHTTPS: Bool
    var isMITMDecrypted: Bool
    var isMapLocal: Bool = false
    var state: ExchangeState

    enum ExchangeState: Sendable, Equatable {
        case inProgress
        case completed
        case failed(String)
    }

    init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        method: String,
        url: String,
        scheme: String = "http",
        host: String,
        port: Int = 80,
        requestHeaders: [(name: String, value: String)] = [],
        requestBody: BodyContent? = nil,
        requestSize: Int = 0,
        isHTTPS: Bool = false,
        isMITMDecrypted: Bool = false,
        isMapLocal: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.method = method
        self.url = url
        self.scheme = scheme
        self.host = host
        self.port = port
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.requestSize = requestSize
        self.isHTTPS = isHTTPS
        self.isMITMDecrypted = isMITMDecrypted
        self.isMapLocal = isMapLocal
        self.state = .inProgress

        // Parse path from URL (requires a valid absolute URL with host), fallback to "/"
        if let parsed = URL(string: url), parsed.host != nil {
            let pathStr = parsed.path.isEmpty ? "/" : parsed.path
            var full = pathStr
            if let query = parsed.query { full += "?" + query }
            self.path = full
        } else {
            self.path = "/"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - BodyContent

enum BodyContent: Sendable, Equatable {
    case data(Data)
    case truncated(Data, totalSize: Int)
    case empty

    static let maxInMemorySize = 10 * 1024 * 1024 // 10 MB

    // MARK: Convenience

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    /// The bytes stored in memory (may be partial for .truncated).
    var data: Data? {
        switch self {
        case .data(let d): return d
        case .truncated(let d, _): return d
        case .empty: return nil
        }
    }

    var isTruncated: Bool {
        if case .truncated = self { return true }
        return false
    }

    /// The actual total body size (data.count for .data, reported totalSize for .truncated).
    var totalSize: Int {
        switch self {
        case .data(let d): return d.count
        case .truncated(_, let size): return size
        case .empty: return 0
        }
    }

    /// Attempts to decode the stored bytes as a UTF-8 string (or the given encoding).
    func asString(encoding: String.Encoding = .utf8) -> String? {
        guard let bytes = data, !bytes.isEmpty else { return nil }
        return String(data: bytes, encoding: encoding)
    }

    // MARK: Builder

    /// Appends raw bytes to the body, respecting the in-memory cap.
    /// Call this repeatedly as body chunks arrive from the network.
    static func appending(existing: BodyContent?, newBytes: Data, runningTotal: inout Int) -> BodyContent {
        runningTotal += newBytes.count

        switch existing {
        case nil, .empty:
            if newBytes.count > maxInMemorySize {
                return .truncated(newBytes.prefix(maxInMemorySize), totalSize: runningTotal)
            }
            return .data(newBytes)

        case .data(var accumulated):
            accumulated.append(newBytes)
            if accumulated.count > maxInMemorySize {
                return .truncated(accumulated.prefix(maxInMemorySize), totalSize: runningTotal)
            }
            return .data(accumulated)

        case .truncated(let partial, _):
            // Already truncated — update total size only
            return .truncated(partial, totalSize: runningTotal)

        case .some(_):
            return existing ?? .empty
        }
    }
}
