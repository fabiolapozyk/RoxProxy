// MARK: - Breakpoint Rule Model

struct BreakpointRule: Codable {
    let id: String
    let urlPattern: String
    let isEnabled: Bool
    let interceptRequest: Bool
    let interceptResponse: Bool
    
    func matches(url: String) -> Bool {
        let normalizedUrl = url.lowercased()
        let pattern = urlPattern.lowercased()
        
        // Remove protocol for comparison (simple version without Regex)
        let cleanUrl = removeProtocol(from: normalizedUrl)
        let cleanPattern = removeProtocol(from: pattern)
        
        // Exact match (including trailing slash)
        if cleanPattern == cleanUrl { return true }
        
        // Match root path only (httpforever.com matches httpforever.com/ but not httpforever.com/js/...)
        if !cleanPattern.contains("/") && cleanUrl == "\(cleanPattern)/" { return true }
        
        // Wildcard match (*.example.com)
        if cleanPattern.hasPrefix("*.") {
            let suffix = String(cleanPattern.dropFirst(2))
            return cleanUrl == suffix || cleanUrl.hasPrefix("\(suffix)/") || cleanUrl == suffix
        }
        
        // Path wildcard (example.com/*)
        if cleanPattern.hasSuffix("/*") {
            let base = String(cleanPattern.dropLast(2))
            return cleanUrl.hasPrefix("\(base)/")
        }
        
        return false
    }

    /// Simple protocol removal without Regex
    private func removeProtocol(from url: String) -> String {
        for prefix in ["http://", "https://", "ftp://"] {
            if url.hasPrefix(prefix) {
                return String(url.dropFirst(prefix.count))
            }
        }
        return url
    }
}


