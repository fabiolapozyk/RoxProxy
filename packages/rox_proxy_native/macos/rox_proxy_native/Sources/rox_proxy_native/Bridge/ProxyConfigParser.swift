import Foundation

/// Result of parsing a proxy configuration payload.
///
/// `config` always contains the rules that could be parsed; `errors` lists the
/// entries that were rejected. Callers decide the policy:
/// - `startProxy` is lenient (log and keep going, so a stale invalid rule does
///   not prevent the proxy from starting);
/// - `updateProxyConfig` is strict (reject the whole update if `errors` is not
///   empty, so the UI and the runtime never diverge).
struct ProxyConfigParseResult {
    let config: ProxyConfig
    let errors: [String]
}

/// Parses the hot-reloadable part of the configuration from the method-channel
/// payload. Port and connection timeout are intentionally not handled here:
/// they require a server restart.
enum ProxyConfigParser {

    static func parse(_ args: [String: Any]) -> ProxyConfigParseResult {
        var errors: [String] = []

        let domainRules = parseDomainRules(args["domainRules"], errors: &errors)
        let mapLocalRules = parseMapLocalRules(args["mapLocalRules"], errors: &errors)
        let breakpointRules = parseBreakpointRules(args["breakpointRules"], errors: &errors)

        let mapLocalMatcher = MapLocalMatcher(rules: mapLocalRules)
        mapLocalMatcher.precompile()

        let breakpointMatcher = BreakpointMatcher(rules: breakpointRules)
        breakpointMatcher.precompile()

        let config = ProxyConfig(
            domainRules: domainRules,
            mapLocalMatcher: mapLocalMatcher,
            breakpointMatcher: breakpointMatcher,
            breakpointEnabled: args["breakpointEnabled"] as? Bool ?? false,
            httpsInterceptionEnabled: args["httpsInterceptionEnabled"] as? Bool ?? true,
            version: 0
        )
        return ProxyConfigParseResult(config: config, errors: errors)
    }

    // MARK: - Rule parsing

    private static func parseDomainRules(
        _ raw: Any?,
        errors: inout [String]
    ) -> [DomainRule] {
        let entries = raw as? [[String: Any]] ?? []
        var rules: [DomainRule] = []
        rules.reserveCapacity(entries.count)
        for (index, dict) in entries.enumerated() {
            guard let idString = dict["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let domain = dict["domain"] as? String,
                  !domain.trimmingCharacters(in: .whitespaces).isEmpty else {
                errors.append("domainRules[\(index)]: invalid id or domain")
                continue
            }
            rules.append(
                DomainRule(
                    id: id,
                    domain: domain,
                    isEnabled: dict["isEnabled"] as? Bool ?? true
                )
            )
        }
        return rules
    }

    private static func parseMapLocalRules(
        _ raw: Any?,
        errors: inout [String]
    ) -> [MapLocalRule] {
        let entries = raw as? [[String: Any]] ?? []
        var rules: [MapLocalRule] = []
        rules.reserveCapacity(entries.count)
        for (index, dict) in entries.enumerated() {
            guard let rule = MapLocalRule.fromDictionary(dict) else {
                errors.append("mapLocalRules[\(index)]: invalid rule")
                continue
            }
            if rule.useRegex, !rule.pathPattern.isEmpty {
                let options: NSRegularExpression.Options =
                    rule.isCaseSensitive ? [] : [.caseInsensitive]
                if (try? NSRegularExpression(pattern: rule.pathPattern, options: options)) == nil {
                    errors.append("mapLocalRules[\(index)]: invalid regex pattern")
                }
            }
            rules.append(rule)
        }
        return rules
    }

    private static func parseBreakpointRules(
        _ raw: Any?,
        errors: inout [String]
    ) -> [BreakpointRule] {
        let entries = raw as? [[String: Any]] ?? []
        var rules: [BreakpointRule] = []
        rules.reserveCapacity(entries.count)
        for (index, dict) in entries.enumerated() {
            guard let rule = BreakpointRule.fromDictionary(dict) else {
                errors.append("breakpointRules[\(index)]: invalid rule")
                continue
            }
            rules.append(rule)
        }
        return rules
    }
}
