import Cocoa
import FlutterMacOS

public class RoxProxyNativePlugin: NSObject, FlutterPlugin {

    private static var methodHandler: ProxyMethodHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
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
        let streamHandler = ExchangeStreamHandler()
        let breakpointStreamHandler = BreakpointStreamHandler()
        let bodyStore = BodyStore()
        let keychainInstaller = KeychainInstaller()

        // 3. CrashGuard: recover from previous crash, install signal handlers
        let crashGuard = CrashGuard()
        crashGuard.installSignalHandlers()
        crashGuard.recoverIfNeeded()

        // 4. Certificate Authority (non-fatal if it fails)
        var ca: CertificateAuthority? = nil
        var certCache: DomainCertificateCache? = nil
        do {
            ca = try CertificateAuthority.loadOrGenerate()
            certCache = DomainCertificateCache(ca: ca!)
        } catch {
            NSLog("RoxProxy: CA init failed: \(error)")
        }

        // 5. Method handler
        let handler = ProxyMethodHandler(
            certificateAuthority: ca,
            domainCertCache: certCache,
            keychainInstaller: keychainInstaller,
            streamHandler: streamHandler,
            breakpointStreamHandler: breakpointStreamHandler,
            bodyStore: bodyStore,
            crashGuard: crashGuard
        )
        Self.methodHandler = handler

        // 6. Register channels
        let instance = RoxProxyNativePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(streamHandler)
        
        // 7. Register breakpoint event channel
        let breakpointEventChannel = FlutterEventChannel(
            name: "com.roxproxy/breakpoints",
            binaryMessenger: registrar.messenger
        )
        breakpointEventChannel.setStreamHandler(breakpointStreamHandler)

        // 7. Clean shutdown on app termination
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Must run synchronously: the app may exit before an async Task executes.
            MainActor.assumeIsolated {
                Self.methodHandler?.stopProxyOnTerminate()
            }
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task { @MainActor in
            Self.methodHandler?.handle(call, result: result)
                ?? result(FlutterMethodNotImplemented)
        }
    }
}
