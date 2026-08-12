import Foundation

/// Which traffic a breakpoint rule applies to.
enum BreakpointTarget: String, Sendable {
    case request
    case response
    case both
}

/// A user-configurable breakpoint rule (RF1.3 — phase 2).
/// Matching fields are glob patterns like Map Local rules; host matching is
/// case-insensitive, path matching is case-sensitive.
struct BreakpointRule: Sendable {
    let id: String
    var name: String?
    var hostPattern: String
    var pathPattern: String
    var httpMethod: String
    var target: BreakpointTarget
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String? = nil,
        hostPattern: String = "*",
        pathPattern: String = "**",
        httpMethod: String = "ANY",
        target: BreakpointTarget = .request,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.hostPattern = hostPattern
        self.pathPattern = pathPattern
        self.httpMethod = httpMethod
        self.target = target
        self.isEnabled = isEnabled
    }

    /// Parses the dictionary produced by the Dart `BreakpointRule.toMap()`.
    static func fromDictionary(_ dict: [String: Any]) -> BreakpointRule? {
        guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
        let targetRaw = dict["target"] as? String
        let target = BreakpointTarget(rawValue: targetRaw ?? "") ?? .request
        return BreakpointRule(
            id: id,
            name: dict["name"] as? String,
            hostPattern: dict["hostPattern"] as? String ?? "*",
            pathPattern: dict["pathPattern"] as? String ?? "**",
            httpMethod: dict["httpMethod"] as? String ?? "ANY",
            target: target,
            isEnabled: dict["isEnabled"] as? Bool ?? true
        )
    }
}
