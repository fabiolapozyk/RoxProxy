import Cocoa
import FlutterMacOS
import os.log

public class RoxProxyNativePlugin: NSObject, FlutterPlugin {

    private static var methodHandler: ProxyMethodHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        ProxyLogger.proxy.info("RoxProxyNativePlugin registering")
        // 1. Channels
        let methodChannel = FlutterMethodChannel(
            name: "com.roxproxy/control",
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "com.roxproxy/exchanges",
            binaryMessenger: registrar.messenger
        )

        // 2. Shared objects
        ProxyLogger.proxy.debug("Creating shared objects: streamHandler, bodyStore, keychainInstaller")
        let streamHandler = ExchangeStreamHandler()
        let bodyStore = BodyStore()
        let keychainInstaller = KeychainInstaller()

        // 3. CrashGuard: recover from previous crash, install signal handlers
        ProxyLogger.crashGuard.info("Initializing CrashGuard")
        let crashGuard = CrashGuard()
        crashGuard.installSignalHandlers()
        crashGuard.recoverIfNeeded()

        // 4. Certificate Authority (non-fatal if it fails)
        ProxyLogger.certificate.info("Loading or generating Certificate Authority")
        var ca: CertificateAuthority? = nil
        var certCache: DomainCertificateCache? = nil
        do {
            ca = try CertificateAuthority.loadOrGenerate()
            certCache = DomainCertificateCache(ca: ca!)
            ProxyLogger.certificate.info("CA loaded successfully")
        } catch {
            ProxyLogger.certificate.error("CA init failed: %{public}@", error.localizedDescription)
            NSLog("RoxProxy: CA init failed: \(error)")
        }

        // 5. Method handler
        ProxyLogger.proxy.debug("Creating ProxyMethodHandler")
        let handler = ProxyMethodHandler(
            certificateAuthority: ca,
            domainCertCache: certCache,
            keychainInstaller: keychainInstaller,
            streamHandler: streamHandler,
            bodyStore: bodyStore,
            crashGuard: crashGuard
        )
        Self.methodHandler = handler

        // 6. Register channels
        ProxyLogger.proxy.info("Registering Flutter channels")
        let instance = RoxProxyNativePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(streamHandler)

        // 7. Clean shutdown on app termination
        ProxyLogger.proxy.debug("Registering termination notification handler")
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            ProxyLogger.proxy.info("App will terminate, stopping proxy")
            // Must run synchronously: the app may exit before an async Task executes.
            MainActor.assumeIsolated {
                Self.methodHandler?.stopProxyOnTerminate()
            }
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        ProxyLogger.proxy.debug("Handling method call: %{public}@", call.method)
        Task { @MainActor in
            Self.methodHandler?.handle(call, result: result)
                ?? result(FlutterMethodNotImplemented)
        }
    }
}
