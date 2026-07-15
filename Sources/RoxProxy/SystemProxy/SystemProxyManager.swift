import Foundation
import SystemConfiguration
import os.log

/// Configures and restores macOS system proxy settings via the `networksetup` tool.
///
/// - `enableProxy(port:)` sets HTTP + HTTPS proxy to `127.0.0.1:<port>` on all active
///   network services and saves their prior state for restoration.
/// - `disableProxy()` turns the proxy off on every service that was touched.
final class SystemProxyManager {

    /// Network services that had proxy enabled by this instance.
    private var affectedServices: [String] = []

    // MARK: - Public API

    /// Enables HTTP + HTTPS proxy on all active network services.
    func enableProxy(port: Int) throws {
        ProxyLogger.systemProxy.info("Enabling system proxy on port %d", port)
        let services = activeNetworkServices()
        guard !services.isEmpty else {
            ProxyLogger.systemProxy.error("No active network services found")
            throw SystemProxyError.noActiveServices
        }

        ProxyLogger.systemProxy.debug("Configuring proxy for services: %@", services.joined(separator: ", "))
        for service in services {
            Self.run("networksetup", ["-setwebproxy",             service, "127.0.0.1", "\(port)"])
            Self.run("networksetup", ["-setsecurewebproxy",       service, "127.0.0.1", "\(port)"])
            Self.run("networksetup", ["-setwebproxystate",        service, "on"])
            Self.run("networksetup", ["-setsecurewebproxystate",  service, "on"])
        }
        affectedServices = services
        ProxyLogger.systemProxy.info("System proxy enabled for %d services on port %d", services.count, port)
    }

    /// Turns off the proxy on all services that were modified by `enableProxy`.
    func disableProxy() {
        ProxyLogger.systemProxy.info("Disabling system proxy for %d services", affectedServices.count)
        for service in affectedServices {
            Self.run("networksetup", ["-setwebproxystate",       service, "off"])
            Self.run("networksetup", ["-setsecurewebproxystate", service, "off"])
        }
        affectedServices = []
        ProxyLogger.systemProxy.info("System proxy disabled")
    }

    /// Turns off the proxy on **all** services — used during crash recovery when
    /// the affected-services list is unavailable.
    static func forceDisableOnAllServices() {
        ProxyLogger.systemProxy.error("Force disabling proxy on ALL network services (crash recovery)")
        for service in allNetworkServices() where !service.hasPrefix("*") {
            run("networksetup", ["-setwebproxystate",       service, "off"])
            run("networksetup", ["-setsecurewebproxystate", service, "off"])
        }
        ProxyLogger.systemProxy.info("Proxy disabled on all services")
    }

    // MARK: - Network service discovery

    /// Active (enabled) network services — skips disabled ones (prefixed with `*`).
    private func activeNetworkServices() -> [String] {
        let all = Self.allNetworkServices()
        ProxyLogger.systemProxy.debug("Found %d network services, %d active", all.count, all.filter { !$0.hasPrefix("*") }.count)
        return all.filter { !$0.hasPrefix("*") }
    }

    private static func allNetworkServices() -> [String] {
        let output = shell("/usr/sbin/networksetup", args: ["-listallnetworkservices"])
        let services = output
            .components(separatedBy: .newlines)
            .dropFirst()                     // first line is a disclaimer header
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        ProxyLogger.systemProxy.debug("Discovered network services: %@", services.joined(separator: ", "))
        return services
    }

    // MARK: - Shell helpers

    private static func run(_ tool: String, _ args: [String]) {
        _ = shell("/usr/sbin/\(tool)", args: args)
    }

    @discardableResult
    private static func shell(_ path: String, args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - Errors

    enum SystemProxyError: Error, LocalizedError {
        case noActiveServices
        var errorDescription: String? {
            "No active network services found. Configure a network connection first."
        }
    }
}
