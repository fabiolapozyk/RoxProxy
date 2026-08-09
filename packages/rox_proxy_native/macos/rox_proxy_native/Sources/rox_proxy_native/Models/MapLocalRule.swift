import Foundation

/// A "Map Local" rule: intercept matching HTTP(S) requests and respond
/// with the contents of a local file instead of forwarding them upstream.
struct MapLocalRule: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var hostPattern: String
    var pathPattern: String
    var httpMethod: String
    var filePath: String
    var statusCode: Int
    var contentType: String?
    var customHeaders: [String: String]
    var isEnabled: Bool
    var isCaseSensitive: Bool
    var useRegex: Bool

    init(
        id: UUID = UUID(),
        hostPattern: String = "*",
        pathPattern: String = "**",
        httpMethod: String = "ANY",
        filePath: String = "",
        statusCode: Int = 200,
        contentType: String? = nil,
        customHeaders: [String: String] = [:],
        isEnabled: Bool = true,
        isCaseSensitive: Bool = true,
        useRegex: Bool = false
    ) {
        self.id = id
        self.hostPattern = hostPattern
        self.pathPattern = pathPattern
        self.httpMethod = httpMethod
        self.filePath = filePath
        self.statusCode = statusCode
        self.contentType = contentType
        self.customHeaders = customHeaders
        self.isEnabled = isEnabled
        self.isCaseSensitive = isCaseSensitive
        self.useRegex = useRegex
    }

    /// Parses a rule dictionary coming from the Flutter MethodChannel.
    static func fromDictionary(_ dict: [String: Any]) -> MapLocalRule? {
        guard let idStr = dict["id"] as? String,
              let id = UUID(uuidString: idStr),
              let pathPattern = dict["pathPattern"] as? String,
              let filePath = dict["filePath"] as? String else { return nil }
        return MapLocalRule(
            id: id,
            hostPattern: dict["hostPattern"] as? String ?? "*",
            pathPattern: pathPattern,
            httpMethod: dict["httpMethod"] as? String ?? "ANY",
            filePath: filePath,
            statusCode: dict["statusCode"] as? Int ?? 200,
            contentType: dict["contentType"] as? String,
            customHeaders: dict["customHeaders"] as? [String: String] ?? [:],
            isEnabled: dict["isEnabled"] as? Bool ?? true,
            isCaseSensitive: dict["isCaseSensitive"] as? Bool ?? true,
            useRegex: dict["useRegex"] as? Bool ?? false
        )
    }
}
