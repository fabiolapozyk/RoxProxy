import Foundation
import FlutterMacOS

/// Routes Flutter MethodChannel calls to the appropriate Swift service.
/// All public methods are called on the main thread by Flutter's channel dispatch.
final class ProxyMethodHandler: NSObject {

    private var proxyServer: ProxyServer?
    private var systemProxyManager: SystemProxyManager?
    private var crashGuard: CrashGuard?

    let certificateAuthority: CertificateAuthority?
    let domainCertCache: DomainCertificateCache?
    let keychainInstaller: KeychainInstaller
    let streamHandler: ExchangeStreamHandler
    let bodyStore: BodyStore

    init(
        certificateAuthority: CertificateAuthority?,
        domainCertCache: DomainCertificateCache?,
        keychainInstaller: KeychainInstaller,
        streamHandler: ExchangeStreamHandler,
        bodyStore: BodyStore,
        crashGuard: CrashGuard?
    ) {
        self.certificateAuthority = certificateAuthority
        self.domainCertCache = domainCertCache
        self.keychainInstaller = keychainInstaller
        self.streamHandler = streamHandler
        self.bodyStore = bodyStore
        self.crashGuard = crashGuard
    }

    // MARK: - Dispatch

    @MainActor
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startProxy":           startProxy(call, result: result)
        case "stopProxy":            stopProxy(result: result)
        case "getProxyState":        getProxyState(result: result)
        case "configureSystemProxy": configureSystemProxy(call, result: result)
        case "installCACertificate": installCACertificate(result: result)
        case "checkCATrust":    checkCATrust(result: result)
        case "getCAStatus":     getCAStatus(result: result)
        case "fetchBody":       fetchBody(call, result: result)
        case "releaseBody":     releaseBody(call, result: result)
        case "releaseAllBodies": releaseAllBodies(result: result)
        case "decompressBody":  decompressBody(call, result: result)
        case "replayRequest":   replayRequest(call, result: result)
        case "setBreakpointRules": setBreakpointRules(call, result: result)
        case "waitForBreakpoint": waitForBreakpoint(call, result: result)
        case "resumeExchange": resumeExchange(call, result: result)
        case "cancelExchange": cancelExchange(call, result: result)
        case "logBreakpointEvent": logBreakpointEvent(call, result: result)
        case "bringWindowToFront": bringWindowToFront(_: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Proxy control

    @MainActor
    private func startProxy(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let port = args["port"] as? Int,
              let timeout = args["connectionTimeoutSeconds"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing port or timeout", details: nil))
            return
        }

        // Parse domain rules from Dart
        let rawRules = args["domainRules"] as? [[String: Any]] ?? []
        let domainRules: [DomainRule] = rawRules.compactMap { dict in
            guard let idStr = dict["id"] as? String,
                  let id = UUID(uuidString: idStr),
                  let domain = dict["domain"] as? String else { return nil }
            let isEnabled = dict["isEnabled"] as? Bool ?? true
            return DomainRule(id: id, domain: domain, isEnabled: isEnabled)
        }

        let httpsInterceptionEnabled = args["httpsInterceptionEnabled"] as? Bool ?? true
        let setSystemProxy = args["setSystemProxy"] as? Bool ?? true

        let store = BridgeSessionStore(streamHandler: streamHandler, bodyStore: bodyStore)
        let server = ProxyServer(
            port: port,
            store: store,
            domainRules: domainRules,
            connectionTimeoutSeconds: timeout,
            certificateAuthority: certificateAuthority,
            domainCertCache: domainCertCache,
            httpsInterceptionEnabled: httpsInterceptionEnabled,
            breakpointRules: [] // Will be set via setBreakpointRules
        )
        self.proxyServer = server

        Task {
            do {
                try await server.start()
                // Enable system proxy (only if the setting is on)
                if setSystemProxy {
                    do {
                        let spm = SystemProxyManager()
                        try spm.enableProxy(port: port)
                        self.systemProxyManager = spm
                    } catch {
                        // Non-fatal: proxy works even if system setting fails
                    }
                }
                // Write crash sentinel
                self.crashGuard?.writeSentinel(port: port)
                result(["success": true, "port": port])
            } catch {
                self.proxyServer = nil
                result(FlutterError(
                    code: "START_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    @MainActor
    private func configureSystemProxy(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard proxyServer != nil else {
            // Proxy not running — nothing to configure.
            result(["success": true])
            return
        }
        guard let args = call.arguments as? [String: Any],
              let enabled = args["enabled"] as? Bool,
              let port    = args["port"]    as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing enabled or port", details: nil))
            return
        }

        if enabled {
            do {
                let spm = SystemProxyManager()
                try spm.enableProxy(port: port)
                self.systemProxyManager = spm
            } catch {
                // Non-fatal
            }
        } else {
            systemProxyManager?.disableProxy()
            systemProxyManager = nil
        }
        result(["success": true])
    }

    @MainActor
    private func stopProxy(result: @escaping FlutterResult) {
        stopProxyOnTerminate()
        result(["success": true])
    }

    /// Called on both explicit stop and app termination.
    @MainActor
    func stopProxyOnTerminate() {
        systemProxyManager?.disableProxy()
        systemProxyManager = nil
        crashGuard?.clearSentinel()

        let server = proxyServer
        proxyServer = nil
        Task {
            try? await server?.stop()
        }
    }

    private func getProxyState(result: FlutterResult) {
        if proxyServer != nil {
            result(["state": "running"])
        } else {
            result(["state": "stopped"])
        }
    }

    // MARK: - Certificate

    private func installCACertificate(result: @escaping FlutterResult) {
        guard let ca = certificateAuthority else {
            result(FlutterError(code: "NO_CA", message: "Certificate Authority not initialized", details: nil))
            return
        }
        let derData = ca.caCertificateDER()
        Task {
            do {
                try await keychainInstaller.installCAInSystemKeychain(derData: derData)
                result(["trusted": true])
            } catch {
                result(FlutterError(
                    code: "INSTALL_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    private func checkCATrust(result: FlutterResult) {
        guard let ca = certificateAuthority else {
            result(["trusted": false])
            return
        }
        let trusted = keychainInstaller.isCAInstalled(derData: ca.caCertificateDER())
        result(["trusted": trusted])
    }

    private func getCAStatus(result: FlutterResult) {
        let initialized = certificateAuthority != nil
        let trusted: Bool
        if let ca = certificateAuthority {
            trusted = keychainInstaller.isCAInstalled(derData: ca.caCertificateDER())
        } else {
            trusted = false
        }
        result(["initialized": initialized, "trusted": trusted])
    }

    // MARK: - Body management

    private func fetchBody(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let ref = args["ref"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing ref", details: nil))
            return
        }
        if let data = bodyStore.fetch(ref: ref) {
            result(FlutterStandardTypedData(bytes: data))
        } else {
            result(nil)
        }
    }

    private func releaseBody(_ call: FlutterMethodCall, result: FlutterResult) {
        if let args = call.arguments as? [String: Any],
           let ref = args["ref"] as? String {
            bodyStore.release(ref: ref)
        }
        result(nil)
    }

    private func releaseAllBodies(result: FlutterResult) {
        bodyStore.releaseAll()
        result(nil)
    }

    // MARK: - Decompression

    private func decompressBody(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let typedData = args["data"] as? FlutterStandardTypedData,
              let encoding = args["encoding"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing data or encoding", details: nil))
            return
        }
        let data = typedData.data
        if let decompressed = GzipDecompressor.decode(data: data, contentEncoding: encoding) {
            result(FlutterStandardTypedData(bytes: decompressed))
        } else {
            result(nil)
        }
    }

    // MARK: - Replay

    private func replayRequest(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let method = args["method"] as? String,
              let urlString = args["url"] as? String,
              let url = URL(string: urlString),
              let headers = args["headers"] as? [[String: Any]] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required fields", details: nil))
            return
        }

        guard let server = proxyServer else {
            result(FlutterError(code: "PROXY_NOT_RUNNING", message: "Proxy server not running", details: nil))
            return
        }

        let httpHeaders = headers.reduce(into: [String: String]()) { dict, header in
            if let name = header["name"] as? String, let value = header["value"] as? String {
                dict[name] = value
            }
        }

        let bodyData: Data? = args["body"] as? String != nil ? Data((args["body"] as! String).utf8) : nil

        Task {
            do {
                let exchangeId = try await server.replayRequest(
                    method: method,
                    url: url,
                    headers: httpHeaders,
                    body: bodyData
                )
                result(["exchangeId": exchangeId])
            } catch {
                result(FlutterError(
                    code: "REPLAY_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    // MARK: - Breakpoint Management

    private func setBreakpointRules(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let rulesData = args["rules"] as? [[String: Any]] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing rules", details: nil))
            return
        }

        let rules: [BreakpointRule] = rulesData.compactMap { ruleDict in
            guard let id = ruleDict["id"] as? String,
                  let urlPattern = ruleDict["urlPattern"] as? String else {
                return nil
            }
            let isEnabled = ruleDict["isEnabled"] as? Bool ?? true
            let interceptRequest = ruleDict["interceptRequest"] as? Bool ?? true
            let interceptResponse = ruleDict["interceptResponse"] as? Bool ?? true
            
            return BreakpointRule(
                id: id,
                urlPattern: urlPattern,
                isEnabled: isEnabled,
                interceptRequest: interceptRequest,
                interceptResponse: interceptResponse
            )
        }

        proxyServer?.setBreakpointRules(rules)
        
        // Also update the HTTP handler if the server is running
        if let server = proxyServer {
            // This would require access to the HTTP handler
            // For now, we'll just log it
            print("✅ Breakpoint rules set: \(rules.count) rules")
        }
        
        result(nil)
    }

    private func waitForBreakpoint(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let exchangeId = args["exchangeId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing exchangeId", details: nil))
            return
        }

        // This method would wait for a breakpoint to be hit
        // For now, we'll just return nil since the native implementation isn't complete
        result(nil)
    }

    private func resumeExchange(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let exchangeId = args["exchangeId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing exchangeId", details: nil))
            return
        }

        let modifications = args["modifications"] as? [String: Any]
        proxyServer?.resumeExchange(exchangeId: exchangeId, modifications: modifications)
        result(nil)
    }

    private func cancelExchange(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let exchangeId = args["exchangeId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing exchangeId", details: nil))
            return
        }

        proxyServer?.cancelExchange(exchangeId: exchangeId)
        result(nil)
    }

    private func logBreakpointEvent(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let exchangeId = args["exchangeId"] as? String,
              let action = args["action"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing exchangeId or action", details: nil))
            return
        }

        let modifications = args["modifications"] as? String
        let error = args["error"] as? String
        
        // Log to console for now
        print("[Breakpoint Event] \(action): \(exchangeId), modifications: \(modifications ?? "none"), error: \(error ?? "none")")
        
        result(nil)
    }

    private func bringWindowToFront(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            self?.proxyServer?.bringWindowToFront()
            result(nil)
        }
    }
}
