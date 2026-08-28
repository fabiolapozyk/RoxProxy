import Foundation

/// A "Map Local" rule: intercept matching HTTP(S) requests and respond
/// with the contents of a local file or an inline body instead of
/// forwarding them upstream.
struct MapLocalRule: Identifiable, Codable, Sendable, Hashable {
    static let sourceFile = "file"
    static let sourceInline = "inline"

    let id: UUID
    var hostPattern: String
    var pathPattern: String
    var httpMethod: String
    var responseSource: String
    var inlineBody: String?
    var filePath: String
    var statusCode: Int
    var contentType: String?
    var customHeaders: [String: String]
    var isEnabled: Bool
    var isCaseSensitive: Bool
    var useRegex: Bool

    var isInline: Bool { responseSource == Self.sourceInline }

    init(
        id: UUID = UUID(),
        hostPattern: String = "*",
        pathPattern: String = "**",
        httpMethod: String = "ANY",
        responseSource: String = Self.sourceFile,
        inlineBody: String? = nil,
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
        self.responseSource = responseSource
        self.inlineBody = inlineBody
        self.filePath = filePath
        self.statusCode = statusCode
        self.contentType = contentType
        self.customHeaders = customHeaders
        self.isEnabled = isEnabled
        self.isCaseSensitive = isCaseSensitive
        self.useRegex = useRegex
    }

    /// Parses a rule dictionary coming from the Flutter MethodChannel.
    /// A rule is rejected when its selected source is missing:
    /// `inline` without a non-empty body, `file` without a non-empty path.
    static func fromDictionary(_ dict: [String: Any]) -> MapLocalRule? {
        guard let idStr = dict["id"] as? String,
              let id = UUID(uuidString: idStr),
              let pathPattern = dict["pathPattern"] as? String else { return nil }
        let responseSource = dict["responseSource"] as? String ?? Self.sourceFile
        let inlineBody = dict["inlineBody"] as? String
        let filePath = dict["filePath"] as? String ?? ""
        if responseSource == Self.sourceInline {
            guard let inlineBody, !inlineBody.isEmpty else { return nil }
        } else if filePath.isEmpty {
            return nil
        }
        return MapLocalRule(
            id: id,
            hostPattern: dict["hostPattern"] as? String ?? "*",
            pathPattern: pathPattern,
            httpMethod: dict["httpMethod"] as? String ?? "ANY",
            responseSource: responseSource,
            inlineBody: inlineBody,
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
