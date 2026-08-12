import Foundation

/// User decision for a suspended request (RF3.2). Parsed from the dictionary
/// sent over the MethodChannel `breakpointDecision` method.
struct BreakpointResponse: Sendable {
    enum Action: String, Sendable {
        case proceed
        case cancel
    }

    let breakpointId: String
    let action: Action
    let modifiedMethod: String?
    let modifiedUrl: String?
    let modifiedHeaders: [(name: String, value: String)]?
    let modifiedBody: String?
    /// Response breakpoint only: desired HTTP status code (100-599).
    let modifiedStatus: Int?

    /// Synthetic decision used for timeout (RF5.2) and shutdown (RNF2):
    /// proceed with the original request, no modifications.
    static func autoProceed(breakpointId: String) -> BreakpointResponse {
        BreakpointResponse(
            breakpointId: breakpointId,
            action: .proceed,
            modifiedMethod: nil,
            modifiedUrl: nil,
            modifiedHeaders: nil,
            modifiedBody: nil,
            modifiedStatus: nil
        )
    }

    /// Parses the dictionary produced by the Dart `breakpoint_response.toMap()`.
    static func fromDictionary(_ dict: [String: Any]) -> BreakpointResponse? {
        guard let breakpointId = dict["breakpointId"] as? String,
              let actionRaw = dict["action"] as? String,
              let action = Action(rawValue: actionRaw) else {
            return nil
        }

        var modifiedHeaders: [(name: String, value: String)]?
        if let rawHeaders = dict["modifiedHeaders"] as? [[String: Any]] {
            modifiedHeaders = rawHeaders.compactMap { header in
                guard let name = header["name"] as? String,
                      let value = header["value"] as? String else { return nil }
                return (name: name, value: value)
            }
        }

        return BreakpointResponse(
            breakpointId: breakpointId,
            action: action,
            modifiedMethod: dict["modifiedMethod"] as? String,
            modifiedUrl: dict["modifiedUrl"] as? String,
            modifiedHeaders: modifiedHeaders,
            modifiedBody: dict["modifiedBody"] as? String,
            modifiedStatus: dict["modifiedStatus"] as? Int
        )
    }
}
