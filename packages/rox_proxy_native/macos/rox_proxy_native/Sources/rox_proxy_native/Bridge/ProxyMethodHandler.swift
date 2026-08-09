import Foundation
import FlutterMacOS
import os.log

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
        ProxyLogger.proxy.debug("Method call: %{public}@", call.method)
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
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Proxy control

    @MainActor
    private func startProxy(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        ProxyLogger.proxy.info("Starting proxy via Flutter method call")
        guard let args = call.arguments as? [String: Any],
              let port = args["port"] as? Int,
              let timeout = args["connectionTimeoutSeconds"] as? Int else {
            ProxyLogger.proxy.error("Invalid arguments for startProxy: missing port or timeout")
            result(FlutterError(code: "INVALID_ARGS", message: "Missing port or timeout", details: nil))
            return
        }

        // Parse domain rules from Dart
        ProxyLogger.proxy.debug("Parsing %d domain rules", (args["domainRules"] as? [[String: Any]])?.count ?? 0)
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

        // Parse Map Local rules from Dart
        ProxyLogger.map.debug("Parsing %d Map Local rules", (args["mapLocalRules"] as? [[String: Any]])?.count ?? 0)
        let mapLocalRules: [MapLocalRule] = (args["mapLocalRules"] as? [[String: Any]] ?? []).compactMap {
            MapLocalRule.fromDictionary($0)
        }

        ProxyLogger.proxy.debug(
            "%{public}@",
            "Proxy configuration: port=\(port), timeout=\(timeout), https=\(httpsInterceptionEnabled ? "yes" : "no"), systemProxy=\(setSystemProxy ? "yes" : "no"), mapLocalRules=\(mapLocalRules.count)"
        )

        let store = BridgeSessionStore(streamHandler: streamHandler, bodyStore: bodyStore)
        let server = ProxyServer(
            port: port,
            store: store,
            domainRules: domainRules,
            mapLocalRules: mapLocalRules,
            connectionTimeoutSeconds: timeout,
            certificateAuthority: certificateAuthority,
            domainCertCache: domainCertCache,
            httpsInterceptionEnabled: httpsInterceptionEnabled
        )
        self.proxyServer = server

        Task {
            do {
                try await server.start()
                ProxyLogger.proxy.info("Proxy started successfully on port %d", port)
                // Enable system proxy (only if the setting is on)
                if setSystemProxy {
                    do {
                        let spm = SystemProxyManager()
                        try spm.enableProxy(port: port)
                        self.systemProxyManager = spm
                    } catch {
                        ProxyLogger.systemProxy.error("Failed to enable system proxy: %{public}@", error.localizedDescription)
                        // Non-fatal: proxy works even if system setting fails
                    }
                }
                // Write crash sentinel
                self.crashGuard?.writeSentinel(port: port)
                result(["success": true, "port": port])
            } catch {
                ProxyLogger.proxy.error("Failed to start proxy: %{public}@", error.localizedDescription)
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
        ProxyLogger.systemProxy.debug("Configuring system proxy via Flutter method call")
        guard proxyServer != nil else {
            // Proxy not running — nothing to configure.
            ProxyLogger.systemProxy.error("Proxy not running, cannot configure system proxy")
            result(["success": true])
            return
        }
        guard let args = call.arguments as? [String: Any],
              let enabled = args["enabled"] as? Bool,
              let port    = args["port"]    as? Int else {
            ProxyLogger.systemProxy.error("Invalid arguments for configureSystemProxy")
            result(FlutterError(code: "INVALID_ARGS", message: "Missing enabled or port", details: nil))
            return
        }

        if enabled {
            ProxyLogger.systemProxy.info("Enabling system proxy on port %d", port)
            do {
                let spm = SystemProxyManager()
                try spm.enableProxy(port: port)
                self.systemProxyManager = spm
            } catch {
                ProxyLogger.systemProxy.error("Failed to enable system proxy: %{public}@", error.localizedDescription)
                // Non-fatal
            }
        } else {
            ProxyLogger.systemProxy.info("Disabling system proxy")
            systemProxyManager?.disableProxy()
            systemProxyManager = nil
        }
        result(["success": true])
    }

    @MainActor
    private func stopProxy(result: @escaping FlutterResult) {
        ProxyLogger.proxy.info("Stopping proxy via Flutter method call")
        stopProxyOnTerminate()
        result(["success": true])
    }

    /// Called on both explicit stop and app termination.
    @MainActor
    func stopProxyOnTerminate() {
        ProxyLogger.proxy.info("Stopping proxy on terminate")
        systemProxyManager?.disableProxy()
        systemProxyManager = nil
        crashGuard?.clearSentinel()

        let server = proxyServer
        proxyServer = nil
        Task {
            do {
                try await server?.stop()
                ProxyLogger.proxy.info("Proxy stopped successfully")
            } catch {
                ProxyLogger.proxy.error("Error stopping proxy: %{public}@", error.localizedDescription)
            }
        }
    }

    private func getProxyState(result: FlutterResult) {
        let state = proxyServer != nil ? "running" : "stopped"
        ProxyLogger.proxy.debug("Getting proxy state: %{public}@", state)
        result(["state": state])
    }

    // MARK: - Certificate

    private func installCACertificate(result: @escaping FlutterResult) {
        ProxyLogger.keychain.info("Installing CA certificate via Flutter method call")
        guard let ca = certificateAuthority else {
            ProxyLogger.keychain.error("CA not initialized")
            result(FlutterError(code: "NO_CA", message: "Certificate Authority not initialized", details: nil))
            return
        }
        let derData = ca.caCertificateDER()
        Task {
            do {
                try await keychainInstaller.installCAInSystemKeychain(derData: derData)
                ProxyLogger.keychain.info("CA certificate installed successfully")
                result(["trusted": true])
            } catch {
                ProxyLogger.keychain.error("Failed to install CA certificate: %{public}@", error.localizedDescription)
                result(FlutterError(
                    code: "INSTALL_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }

    private func checkCATrust(result: FlutterResult) {
        ProxyLogger.keychain.debug("Checking CA trust status")
        guard let ca = certificateAuthority else {
            ProxyLogger.keychain.error("CA not initialized")
            result(["trusted": false])
            return
        }
        let trusted = keychainInstaller.isCAInstalled(derData: ca.caCertificateDER())
        ProxyLogger.keychain.debug("CA trusted: %{public}@", trusted ? "yes" : "no")
        result(["trusted": trusted])
    }

    private func getCAStatus(result: FlutterResult) {
        ProxyLogger.keychain.debug("Getting CA status")
        let initialized = certificateAuthority != nil
        let trusted: Bool
        if let ca = certificateAuthority {
            trusted = keychainInstaller.isCAInstalled(derData: ca.caCertificateDER())
        } else {
            trusted = false
        }
        ProxyLogger.keychain.debug("CA status: initialized=%{public}@, trusted=%{public}@", initialized ? "yes" : "no", trusted ? "yes" : "no")
        result(["initialized": initialized, "trusted": trusted])
    }

    // MARK: - Body management

    private func fetchBody(_ call: FlutterMethodCall, result: FlutterResult) {
        ProxyLogger.proxy.debug("Fetching body via Flutter method call")
        guard let args = call.arguments as? [String: Any],
              let ref = args["ref"] as? String else {
            ProxyLogger.proxy.error("Invalid arguments for fetchBody: missing ref")
            result(FlutterError(code: "INVALID_ARGS", message: "Missing ref", details: nil))
            return
        }
        if let data = bodyStore.fetch(ref: ref) {
            ProxyLogger.proxy.debug("Body fetched successfully, size: %d bytes", data.count)
            result(FlutterStandardTypedData(bytes: data))
        } else {
            ProxyLogger.proxy.error("Body not found for ref: %{public}@", ref)
            result(nil)
        }
    }

    private func releaseBody(_ call: FlutterMethodCall, result: FlutterResult) {
        ProxyLogger.proxy.debug("Releasing body via Flutter method call")
        if let args = call.arguments as? [String: Any],
           let ref = args["ref"] as? String {
            bodyStore.release(ref: ref)
        }
        result(nil)
    }

    private func releaseAllBodies(result: FlutterResult) {
        ProxyLogger.proxy.debug("Releasing all bodies")
        bodyStore.releaseAll()
        result(nil)
    }

    // MARK: - Decompression

    private func decompressBody(_ call: FlutterMethodCall, result: FlutterResult) {
        ProxyLogger.proxy.debug("Decompressing body via Flutter method call")
        guard let args = call.arguments as? [String: Any],
              let typedData = args["data"] as? FlutterStandardTypedData,
              let encoding = args["encoding"] as? String else {
            ProxyLogger.proxy.error("Invalid arguments for decompressBody")
            result(FlutterError(code: "INVALID_ARGS", message: "Missing data or encoding", details: nil))
            return
        }
        let data = typedData.data
        ProxyLogger.proxy.debug("Decompressing %d bytes with encoding: %{public}@", data.count, encoding)
        if let decompressed = GzipDecompressor.decode(data: data, contentEncoding: encoding) {
            ProxyLogger.proxy.debug("Decompression successful: %d -> %d bytes", data.count, decompressed.count)
            result(FlutterStandardTypedData(bytes: decompressed))
        } else {
            ProxyLogger.proxy.error("Decompression failed")
            result(nil)
        }
    }

    // MARK: - Replay

    private func replayRequest(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        ProxyLogger.replay.info("Replaying request via Flutter method call")
        guard let args = call.arguments as? [String: Any],
              let method = args["method"] as? String,
              let urlString = args["url"] as? String,
              let url = URL(string: urlString),
              let headers = args["headers"] as? [[String: Any]] else {
            ProxyLogger.replay.error("Invalid arguments for replayRequest")
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required fields", details: nil))
            return
        }

        guard let server = proxyServer else {
            ProxyLogger.replay.error("Proxy server not running")
            result(FlutterError(code: "PROXY_NOT_RUNNING", message: "Proxy server not running", details: nil))
            return
        }

        ProxyLogger.replay.debug("Replay request: %{public}@ %{public}@", method, urlString)
        let httpHeaders = headers.reduce(into: [String: String]()) { dict, header in
            if let name = header["name"] as? String, let value = header["value"] as? String {
                dict[name] = value
            }
        }

        let bodyData: Data? = args["body"] as? String != nil ? Data((args["body"] as! String).utf8) : nil

        Task {
            do {
                ProxyLogger.replay.debug("Executing replay request")
                let exchangeId = try await server.replayRequest(
                    method: method,
                    url: url,
                    headers: httpHeaders,
                    body: bodyData
                )
                ProxyLogger.replay.info("Replay request completed, exchangeId: %{public}@", exchangeId)
                result(["exchangeId": exchangeId])
            } catch {
                ProxyLogger.replay.error("Replay request failed: %{public}@", error.localizedDescription)
                result(FlutterError(
                    code: "REPLAY_FAILED",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }
}
