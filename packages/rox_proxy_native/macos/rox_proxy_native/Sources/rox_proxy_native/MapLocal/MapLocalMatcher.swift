import Foundation

/// Matches incoming HTTP requests against Map Local rules.
/// Rules are evaluated in declaration order — the first matching enabled
/// rule wins (priority by list position).
struct MapLocalMatcher: Sendable {

    /// Only enabled rules are considered.
    private let rules: [MapLocalRule]

    /// Compiled regex cache keyed by "\(pattern)\u{0}\(caseSensitive)".
    /// Guarded by a lock because the matcher is shared across NIO threads.
    private let regexCache = RegexCache()

    init(rules: [MapLocalRule]) {
        self.rules = rules.filter { $0.isEnabled }
    }

    var isEmpty: Bool { rules.isEmpty }

    /// Returns the first enabled rule matching method + host + path, or nil.
    func firstMatch(method: String, host: String, path: String) -> MapLocalRule? {
        for rule in rules where ruleMatches(rule: rule, method: method, host: host, path: path) {
            return rule
        }
        return nil
    }

    /// True if any enabled rule could apply to the given host (regardless of
    /// path). Used at CONNECT time to decide whether HTTPS must be
    /// MITM-intercepted so path-based Map Local rules can apply.
    func hasPossibleMatch(host: String) -> Bool {
        rules.contains { matchesHost(rule: $0, host: host) }
    }

    // MARK: - Matching

    private func ruleMatches(rule: MapLocalRule, method: String, host: String, path: String) -> Bool {
        matchesMethod(rule: rule, method: method)
            && matchesHost(rule: rule, host: host)
            && matchesPath(rule: rule, path: path)
    }

    private func matchesMethod(rule: MapLocalRule, method: String) -> Bool {
        let ruleMethod = rule.httpMethod.trimmingCharacters(in: .whitespaces)
        if ruleMethod.isEmpty || ruleMethod.caseInsensitiveCompare("ANY") == .orderedSame {
            return true
        }
        return ruleMethod.caseInsensitiveCompare(method) == .orderedSame
    }

    /// Case-insensitive host matching. Supports exact names and `*.domain.com`.
    func matchesHost(rule: MapLocalRule, host: String) -> Bool {
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

    /// Path matching: glob patterns (`*` = any chars but `/`, `**` = any chars)
    /// or regular expressions when `useRegex` is enabled.
    private func matchesPath(rule: MapLocalRule, path: String) -> Bool {
        let pattern = rule.pathPattern
        if pattern.isEmpty { return true }

        if rule.useRegex {
            guard let regex = regexCache.regex(for: pattern, caseSensitive: rule.isCaseSensitive) else {
                ProxyLogger.map.error("Map Local: invalid regex pattern %{public}@, skipping rule", pattern)
                return false
            }
            let range = NSRange(location: 0, length: (path as NSString).length)
            return regex.firstMatch(in: path, options: [], range: range) != nil
        }

        let nsString = path as NSString
        let resultRange = nsString.range(
            of: MapLocalMatcher.globToRegex(pattern),
            options: rule.isCaseSensitive ? .regularExpression : [.regularExpression, .caseInsensitive]
        )
        return resultRange.location != NSNotFound
    }

    /// Converts a glob pattern to a regex string:
    /// - `**` matches any character sequence (including `/`)
    /// - `*` matches any character sequence except `/`
    /// - other regex metacharacters are escaped
    /// A leading `*` leaves the start unanchored (suffix matching), so
    /// `*.json` matches any path ending in `.json`.
    static func globToRegex(_ pattern: String) -> String {
        var out = pattern.first == "*" ? "" : "^"
        out.reserveCapacity(pattern.count + 8)
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let char = pattern[index]
            if char == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    out += ".*"
                    index = pattern.index(after: next)
                } else {
                    out += "[^/]*"
                    index = next
                }
            } else {
                if "\\^$.|?+()[]{}".contains(char) {
                    out += "\\"
                }
                out.append(char)
                index = pattern.index(after: index)
            }
        }
        out += "$"
        return out
    }
}

/// Thread-safe cache of compiled regular expressions.
private final class RegexCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: NSRegularExpression] = [:]

    func regex(for pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        let key = pattern + "\u{0}" + (caseSensitive ? "1" : "0")
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        cache[key] = compiled
        return compiled
    }
}
