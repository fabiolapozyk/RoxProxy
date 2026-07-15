import AppKit
import SwiftUI
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sessionStore = ProxySessionStore()
    let settingsStore = SettingsStore()

    private(set) var certificateAuthority: CertificateAuthority?
    private(set) var domainCertCache: DomainCertificateCache?
    let keychainInstaller = KeychainInstaller()

    private var proxyServer: ProxyServer?
    private var systemProxyManager: SystemProxyManager?
    private var crashGuard: CrashGuard?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProxyLogger.proxy.info("Application launching")
        
        NSApp.activate(ignoringOtherApps: true)
        settingsStore.load()
        
        ProxyLogger.crashGuard.info("Initializing crash guard")
        crashGuard = CrashGuard()
        crashGuard?.installSignalHandlers()
        crashGuard?.recoverIfNeeded(settingsStore: settingsStore)

        // Load or generate the CA (done synchronously on launch; fast after first run)
        ProxyLogger.certificate.info("Loading or generating Certificate Authority")
        do {
            let ca = try CertificateAuthority.loadOrGenerate()
            certificateAuthority = ca
            domainCertCache = DomainCertificateCache(ca: ca)

            // Update CA trust status in settings store
            let derData = ca.caCertificateDER()
            settingsStore.isCATrusted = keychainInstaller.isCAInstalled(derData: derData)
            ProxyLogger.certificate.info("CA loaded successfully, trusted: %s", settingsStore.isCATrusted ? "yes" : "no")
        } catch {
            // Non-fatal: HTTPS MITM won't work, but HTTP proxy still will
            ProxyLogger.certificate.error("CA initialization failed: %@", error.localizedDescription)
            ProxyLogger.error.error("CA initialization failed: %@", error.localizedDescription)
        }

        // Observe start/stop notifications from the toolbar
        NotificationCenter.default.addObserver(
            forName: .startProxy, object: nil, queue: .main
        ) { [weak self] _ in self?.startProxy() }

        NotificationCenter.default.addObserver(
            forName: .stopProxy, object: nil, queue: .main
        ) { [weak self] _ in self?.stopProxy() }

        if settingsStore.settings.autoStartProxy {
            startProxy()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProxyLogger.proxy.info("Application will terminate")
        stopProxy()
        crashGuard?.clearSentinel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func startProxy() {
        let port = settingsStore.settings.port
        ProxyLogger.proxy.info("Starting proxy on port %d", port)
        
        let server = ProxyServer(
            port: port,
            store: sessionStore,
            settingsStore: settingsStore,
            certificateAuthority: certificateAuthority,
            domainCertCache: domainCertCache
        )
        proxyServer = server

        Task {
            do {
                try await server.start()
                await MainActor.run {
                    sessionStore.proxyState = .running(port: port)
                    ProxyLogger.proxy.info("Proxy started successfully on port %d", port)
                }
                crashGuard?.writeSentinel(port: port)

                let sysProxy = SystemProxyManager()
                systemProxyManager = sysProxy
                try sysProxy.enableProxy(port: port)
            } catch {
                ProxyLogger.proxy.error("Failed to start proxy: %@", error.localizedDescription)
                ProxyLogger.error.error("Proxy start failed: %@", error.localizedDescription)
                await MainActor.run {
                    sessionStore.proxyState = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Installs the root CA certificate into the System keychain (requires admin).
    func installCertificate() async throws {
        ProxyLogger.keychain.info("Attempting to install CA certificate in System Keychain")
        guard let ca = certificateAuthority else {
            ProxyLogger.keychain.error("CA not initialized")
            throw CertInstallError.caNotInitialized
        }
        let derData = ca.caCertificateDER()
        try await keychainInstaller.installCAInSystemKeychain(derData: derData)
        isCATrusted = keychainInstaller.isCAInstalled(derData: derData)
        settingsStore.isCATrusted = isCATrusted
        ProxyLogger.keychain.info("CA certificate installed successfully, trusted: %s", isCATrusted ? "yes" : "no")
    }

    private(set) var isCATrusted: Bool = false

    enum CertInstallError: Error, LocalizedError {
        case caNotInitialized
        var errorDescription: String? { "Certificate Authority not initialized." }
    }

    func stopProxy() {
        ProxyLogger.proxy.info("Stopping proxy")
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
                ProxyLogger.proxy.error("Error stopping proxy: %@", error.localizedDescription)
            }
        }

        Task { @MainActor in
            sessionStore.proxyState = .stopped
        }
    }
}
