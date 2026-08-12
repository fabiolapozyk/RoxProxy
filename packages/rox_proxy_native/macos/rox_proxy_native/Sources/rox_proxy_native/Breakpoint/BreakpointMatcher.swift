import Foundation

/// Centralizes the breakpoint trigger conditions (RF1.3).
///
/// Rules are user-configurable (host/path globs + method + target).
/// Breakpoints are active only when at least one *enabled* rule matches:
/// with zero rules (or all disabled) nothing is intercepted.
struct BreakpointMatcher: Sendable {

    private let rules: [BreakpointRule]
    private let regexCache = BreakpointRegexCache()

    init(rules: [BreakpointRule]) {
        self.rules = rules
    }

    private var enabledRules: [BreakpointRule] {
        rules.filter(\.isEnabled)
    }

    // MARK: - Matching

    func shouldBreakpointRequest(method: String, host: String, path: String) -> Bool {
        enabledRules.contains {
            (($0.target == .request || $0.target == .both)
                && matchesRule($0, method: method, host: host, path: path))
        }
    }

    func shouldBreakpointResponse(method: String, host: String, path: String) -> Bool {
        enabledRules.contains {
            (($0.target == .response || $0.target == .both)
                && matchesRule($0, method: method, host: host, path: path))
        }
    }

    // MARK: - Rule matching

    private func matchesRule(_ rule: BreakpointRule, method: String, host: String, path: String) -> Bool {
        matchesMethod(rule: rule, method: method)
            && matchesHost(rule: rule, host: host)
            && matchesPath(rule: rule, path: path)
    }

    private func matchesMethod(rule: BreakpointRule, method: String) -> Bool {
        let ruleMethod = rule.httpMethod.trimmingCharacters(in: .whitespaces)
        if ruleMethod.isEmpty || ruleMethod.caseInsensitiveCompare("ANY") == .orderedSame {
            return true
        }
        return ruleMethod.caseInsensitiveCompare(method) == .orderedSame
    }

    /// Case-insensitive host matching: exact names and `*.domain.com`.
    private func matchesHost(rule: BreakpointRule, host: String) -> Bool {
        let pattern = rule.hostPattern.trimmingCharacters(in: .whitespaces)
        if pattern.isEmpty || pattern == "*" { return true }
        let lowerHost = host.lowercased()
        let lowerPattern = pattern.lowercased()
        if lowerPattern.hasPrefix("*.") {
            let suffix = String(lowerPattern.dropFirst(2))
            return lowerHost == suffix || lowerHost.hasSuffix("." + suffix)
        }
        return lowerHost == lowerPattern
    }

    /// Path glob matching (`*` = any chars but `/`, `**` = any chars),
    /// case-sensitive like Map Local.
    private func matchesPath(rule: BreakpointRule, path: String) -> Bool {
        let pattern = rule.pathPattern
        if pattern.isEmpty { return true }
        guard let regex = regexCache.regex(for: pattern) else { return false }
        let range = NSRange(location: 0, length: (path as NSString).length)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }
}

/// Thread-safe cache of compiled glob regexes (same contract as Map Local's).
private final class BreakpointRegexCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: NSRegularExpression] = [:]

    func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] { return cached }
        guard let compiled = try? NSRegularExpression(
            pattern: MapLocalMatcher.globToRegex(pattern)
        ) else {
            return nil
        }
        cache[pattern] = compiled
        return compiled
    }
}
