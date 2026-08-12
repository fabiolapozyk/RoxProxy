import os.log

/// Centralized logging utility for RoxProxy Native Plugin using macOS's unified logging system (os_log).
/// 
/// This mirrors the ProxyLogger in the main Swift app for consistency.
/// 
/// Logs are automatically:
/// - Persisted by the system
/// - Viewable in Console.app with subsystem filter "com.roxproxy"
/// - Thread-safe
/// 
/// Usage:
/// ```swift
/// ProxyLogger.proxy.info("Proxy started on port %d", port)
/// ProxyLogger.tls.debug("TLS handshake completed for %@", host)
/// ProxyLogger.error.error("Connection failed: %@", error.localizedDescription)
/// ```
/// 
/// Note on safety:
/// The message is first rendered into a plain Swift `String` with `String(format:)`,
/// then passed to `os_log` as a single `%@` argument. Passing the raw `[CVarArg]`
/// array directly into `os_log`'s variadic splats is unreliable: numeric `%d`
/// arguments print garbage and `%@` with an `Int` can crash the process.
/// The os_log-specific `%{public}@` / `%{private}@` markers are translated to
/// plain `%@` since the whole message is logged as one public string.

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
    
    /// Renders the format message with the given arguments into a single String.
    /// os_log-specific privacy markers (`%{public}@`, `%{private}@`) are not valid
    /// `printf` specifiers, so they are translated to plain `%@`.
    private func render(_ message: StaticString, _ args: [CVarArg]) -> String {
        var format = String(describing: message)
        format = format
            .replacingOccurrences(of: "%{public}@", with: "%@")
            .replacingOccurrences(of: "%{private}@", with: "%@")
        return String(format: format, arguments: args)
    }
    
    private func emit(_ message: StaticString, _ args: [CVarArg], type: OSLogType) {
        let formatted = render(message, args)
        if #available(macOS 11.0, *) {
            os_log("%{public}@", log: log, type: logType(type), formatted)
        } else {
            print(formatted)
        }
    }
    
    /// Log a debug message
    func debug(_ message: StaticString, _ args: CVarArg...) {
        emit(message, args, type: .debug)
    }
    
    /// Log an info message
    func info(_ message: StaticString, _ args: CVarArg...) {
        emit(message, args, type: .info)
    }
    
    /// Log a default message
    func `default`(_ message: StaticString, _ args: CVarArg...) {
        emit(message, args, type: .default)
    }
    
    /// Log an error message (always visible, high priority)
    func error(_ message: StaticString, _ args: CVarArg...) {
        emit(message, args, type: .error)
    }
    
    /// Log a fault message (critical errors that may cause crashes)
    func fault(_ message: StaticString, _ args: CVarArg...) {
        emit(message, args, type: .fault)
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

    /// Map Local rule matching and file serving
    static let map = CategoryLogger(log: OSLog(subsystem: subsystem, category: "mapLocal"))

    /// Breakpoint suspension, decisions and timeouts (no payloads)
    static let breakpoint = CategoryLogger(log: OSLog(subsystem: subsystem, category: "breakpoint"))
}
