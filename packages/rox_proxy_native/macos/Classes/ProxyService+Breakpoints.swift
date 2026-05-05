import Foundation
import Cocoa

// MARK: - Breakpoint Management

extension ProxyService {
    
    /// Store active breakpoint rules
    private var breakpointRules: [BreakpointRule] = []
    
    /// Track paused exchanges waiting for user action
    private var pausedExchanges: [String: PausedExchange] = [:]
    
    // MARK: - Breakpoint Rule Management
    
    /// Set breakpoint rules from Flutter
    func setBreakpointRules(_ rules: [BreakpointRule]) {
        breakpointRules = rules
        print("✅ Breakpoint rules updated: \(rules.count) rules")
    }
    
    /// Check if a URL matches any breakpoint rule
    func shouldPauseExchange(url: String, isRequest: Bool) -> BreakpointRule? {
        for rule in breakpointRules {
            if !rule.isEnabled { continue }
            
            if rule.matches(url: url) {
                // Check if we should intercept request or response
                if (isRequest && rule.interceptRequest) {
                    return rule
                } else if (!isRequest && rule.interceptResponse) {
                    return rule
                }
            }
        }
        return nil
    }
    
    // MARK: - Exchange Pausing/Resuming
    
    /// Pause an exchange and wait for user action
    func pauseExchange(exchangeId: String, exchange: CapturedExchange) {
        let paused = PausedExchange(exchange: exchange)
        pausedExchanges[exchangeId] = paused
        
        print("⏸️  Exchange paused: \(exchangeId), waiting for user action...")
        
        // Notify Flutter that a breakpoint was hit
        notifyBreakpointHit(exchangeId: exchangeId)
    }
    
    /// Resume a paused exchange with optional modifications
    func resumeExchange(exchangeId: String, modifications: [String: Any]?) {
        guard let paused = pausedExchanges[exchangeId] else {
            print("❌ Exchange not found: \(exchangeId)")
            return
        }
        
        // Apply modifications if provided
        if let mods = modifications {
            applyModifications(to: paused.exchange, modifications: mods)
        }
        
        // Resume the exchange
        paused.resume()
        pausedExchanges.removeValue(forKey: exchangeId)
        
        print("▶️  Exchange resumed: \(exchangeId)")
        
        // Log the event
        logBreakpointEvent(exchangeId: exchangeId, action: "resume", modifications: modifications)
    }
    
    /// Cancel a paused exchange
    func cancelExchange(exchangeId: String) {
        guard let paused = pausedExchanges[exchangeId] else {
            print("❌ Exchange not found: \(exchangeId)")
            return
        }
        
        // Cancel the exchange
        paused.cancel()
        pausedExchanges.removeValue(forKey: exchangeId)
        
        print("⏹️  Exchange cancelled: \(exchangeId)")
        
        // Log the event
        logBreakpointEvent(exchangeId: exchangeId, action: "cancel", modifications: nil)
    }
    
    /// Apply modifications to an exchange
    private func applyModifications(to exchange: CapturedExchange, modifications: [String: Any]) {
        if let method = modifications["method"] as? String {
            exchange.method = method
        }
        
        if let url = modifications["url"] as? String {
            exchange.url = url
        }
        
        if let headers = modifications["headers"] as? [[String: String]] {
            exchange.requestHeaders = headers
        }
        
        if let body = modifications["body"] as? Data {
            exchange.requestBody = body
        }
        
        print("✏️  Modifications applied to exchange \(exchange.id)")
    }
    
    /// Log breakpoint event for debugging
    private func logBreakpointEvent(exchangeId: String, action: String, modifications: [String: Any]?) {
        var logMessage = "[Breakpoint] \(action): \(exchangeId)"
        if let mods = modifications {
            logMessage += ", modifications: \(mods)"
        }
        print(logMessage)
        
        // In a real app, you might want to write this to a file or send to analytics
    }
    
    // MARK: - Flutter Communication
    
    /// Notify Flutter that a breakpoint was hit
    private func notifyBreakpointHit(exchangeId: String) {
        // This will be called when an exchange is paused
        // Flutter will show the breakpoint dialog
        print("📬 Notifying Flutter about breakpoint hit: \(exchangeId)")
        
        // In the actual implementation, you would use your existing Flutter channel
        // to send an event like:
        // channel.invokeMethod("onBreakpointHit", arguments: ["exchangeId": exchangeId])
    }
    
    // MARK: - Window Management
    
    /// Bring the main window to front
    func bringWindowToFront() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Activate the app
            NSApp.activate(ignoringOtherApps: true)
            
            // Bring the main window to front
            if let window = self.viewController?.view.window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            
            print("🪟 Window brought to front")
        }
    }
}

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
        
        // Remove protocol for comparison
        let cleanUrl = normalizedUrl.replacingOccurrences(of: Regex("^[a-z]+://"), with: "")
        let cleanPattern = pattern.replacingOccurrences(of: Regex("^[a-z]+://"), with: "")
        
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
}

// MARK: - Paused Exchange

class PausedExchange {
    let exchange: CapturedExchange
    private var completion: ((CapturedExchange) -> Void)?
    private var cancellation: (() -> Void)?
    
    init(exchange: CapturedExchange) {
        self.exchange = exchange
    }
    
    func setCompletionHandler(_ completion: @escaping (CapturedExchange) -> Void) {
        self.completion = completion
    }
    
    func setCancellationHandler(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }
    
    func resume() {
        completion?(exchange)
    }
    
    func cancel() {
        cancellation?()
    }
}

// MARK: - Regex Helper

extension String {
    func replacingOccurrences(of regex: Regex<AnyRegexOutput>, with template: String) -> String {
        if #available(macOS 13.0, *) {
            return self.replacing(regex, with: template)
        } else {
            // Fallback for older macOS versions
            let range = self.range(of: regex) ?? self.startIndex..<self.endIndex
            return self.replacingCharacters(in: range, with: template)
        }
    }
}
