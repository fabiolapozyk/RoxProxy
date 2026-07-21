import os.log

/// Centralized logging utility for RoxProxy Native Plugin using macOS's unified logging system (os_log).
/// 
/// This mirrors the ProxyLogger in the main Swift app for consistency.
/// 
/// Logs are automatically:
/// - Persisted by the system
/// - Viewable in Console.app with subsystem filter "com.roxproxy"
/// - Privacy-aware (sensitive data like hostnames is automatically redacted in public builds)
/// - Thread-safe
/// 
/// Usage:
/// ```swift
/// ProxyLogger.proxy.info("Proxy started on port %d", port)
/// ProxyLogger.tls.debug("TLS handshake completed for %{public}@", host)
/// ProxyLogger.error.error("Connection failed: %@", error.localizedDescription)
/// ```

/// Wrapper struct that provides convenient logging methods for a specific category
struct CategoryLogger {
    private let log: OSLog
    
    init(log: OSLog) {
        self.log = log
    }
    
    /// Returns the appropriate log type based on build configuration.
    /// In release builds, uses .default for .info and .debug to ensure persistence.
    private func logType(_ type: OSLogType) -> OSLogType {
        #if DEBUG
        return type
        #else
        // In release builds, map debug and info to default for persistence
        if type == .debug || type == .info {
            return .default
        }
        return type
        #endif
    }
    
    /// Log a debug message
    func debug(_ message: StaticString, _ args: CVarArg..., file: StaticString = #file, line: Int = #line) {
        if #available(macOS 11.0, *) {
            os_log(message, log: log, type: logType(.debug), args)
        } else {
            print(String(format: message.description, arguments: args))
        }
    }
    
    /// Log an info message
    func info(_ message: StaticString, _ args: CVarArg..., file: StaticString = #file, line: Int = #line) {
        if #available(macOS 11.0, *) {
            os_log(message, log: log, type: logType(.info), args)
        } else {
            print(String(format: message.description, arguments: args))
        }
    }
    
    /// Log a default message
    func `default`(_ message: StaticString, _ args: CVarArg..., file: StaticString = #file, line: Int = #line) {
        if #available(macOS 11.0, *) {
            os_log(message, log: log, type: .default, args)
        } else {
            print(String(format: message.description, arguments: args))
        }
    }
    
    /// Log an error message (always visible, high priority)
    func error(_ message: StaticString, _ args: CVarArg..., file: StaticString = #file, line: Int = #line) {
        if #available(macOS 11.0, *) {
            os_log(message, log: log, type: .error, args)
        } else {
            fputs(String(format: "[ERROR] " + message.description, arguments: args) + "\n", stderr)
        }
    }
    
    /// Log a fault message (critical errors that may cause crashes)
    func fault(_ message: StaticString, _ args: CVarArg..., file: StaticString = #file, line: Int = #line) {
        if #available(macOS 11.0, *) {
            os_log(message, log: log, type: .fault, args)
        } else {
            fputs(String(format: "[FAULT] " + message.description, arguments: args) + "\n", stderr)
        }
    }
}

final class ProxyLogger {
    
    // MARK: - Log Categories

    /// Subsystem identifier - used to filter logs in Console.app
    private static let subsystem = "com.roxproxy"

    /// Proxy lifecycle and general operations
    static let proxy = CategoryLogger(log: OSLog(subsystem: subsystem, category: "proxy"))

    /// TLS/SSL and MITM decryption operations
    static let tls = CategoryLogger(log: OSLog(subsystem: subsystem, category: "tls"))

    /// Certificate Authority and certificate management
    static let certificate = CategoryLogger(log: OSLog(subsystem: subsystem, category: "certificate"))

    /// Keychain operations
    static let keychain = CategoryLogger(log: OSLog(subsystem: subsystem, category: "keychain"))

    /// System proxy configuration (networksetup)
    static let systemProxy = CategoryLogger(log: OSLog(subsystem: subsystem, category: "systemProxy"))

    /// HTTP request/response handling
    static let http = CategoryLogger(log: OSLog(subsystem: subsystem, category: "http"))

    /// Error logging (all critical errors)
    static let error = CategoryLogger(log: OSLog(subsystem: subsystem, category: "error"))

    /// Crash recovery and signal handling
    static let crashGuard = CategoryLogger(log: OSLog(subsystem: subsystem, category: "crashGuard"))

    /// Replay functionality
    static let replay = CategoryLogger(log: OSLog(subsystem: subsystem, category: "replay"))
}
