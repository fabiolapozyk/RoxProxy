# rox_proxy_native

Local Flutter plugin that hosts the RoxProxy native engine: a Swift/SwiftNIO
HTTP/HTTPS intercepting proxy for macOS.

The Dart UI lives in the app (`lib/`); this package only exposes the platform
channels and all the proxy logic.

## Layout

```
macos/rox_proxy_native/Sources/rox_proxy_native/
  Bridge/          # Flutter <-> Swift bridge: plugin, method handler,
                   # session/body stores, ProxyConfigStore + ProxyConfigParser
  Proxy/           # SwiftNIO handlers: ProxyServer, HTTPProxyHandler,
                   # MITMHandler, OutboundHTTPHandler, TunnelHandler
  Breakpoint/      # Breakpoint matcher, suspension engine, modifiers
  Certificate/     # CA generation, per-domain certs, Keychain installer
  MapLocal/        # MapLocal matcher + response handler
  Models/          # CapturedExchange, DomainRule, ProxyConfig, rules, settings
  SystemProxy/     # networksetup integration, CrashGuard
  Utilities/       # ProxyLogger (os_log), ProxyMetrics, GzipDecompressor
```

## Configuration hot reload

The proxy configuration is an immutable `ProxyConfig` snapshot held by a
thread-safe `ProxyConfigStore`:

- handlers read `configStore.current()` at `.head` and keep that snapshot for the
  whole exchange (request + response);
- new requests use the latest snapshot; in-flight requests and already-open
  tunnels keep the snapshot they started with;
- the `CONNECT`/MITM decision is sticky per connection;
- `ProxyMethodHandler.updateProxyConfig` swaps the snapshot atomically without
  stopping the server. It is strict: an invalid rule rejects the whole update.
  `startProxy` is lenient and drops invalid saved rules with a log;
- hot-swappable: domain rules, Map Local, breakpoint toggle/rules, HTTPS
  interception (new CONNECTs). Restart-only: port and connection timeout.

This is what keeps long-lived connections (including a VPN tunnel routed through
RoxProxy) alive while rules are edited. Do not reintroduce `stopProxy` /
`startProxy` on configuration changes.

## Platform channels

- `com.roxproxy/control` (MethodChannel): `startProxy`, `updateProxyConfig`,
  `stopProxy`, `getProxyState`, `configureSystemProxy`, certificate/body/replay
  methods, `breakpointDecision`.
- `com.roxproxy/exchanges` (EventChannel): captured exchange events.
- `com.roxproxy/breakpointEvents` (EventChannel): `request`, `response` and
  `resolved` breakpoint events.

See the root `README.md` for the full method list and the app-level architecture.

## Testing

```bash
# Pure Swift core (standalone SPM package; symlinks the sources)
cd macos/CoreTests && swift test

# Full app verification (format, analyze, Dart tests, Swift tests, debug build)
./scripts/verify.sh

# End-to-end smoke test (release build, launch, /health, /stats, clean shutdown)
./scripts/smoke.sh
```

Do **not** run `swift build` / `swift test` inside `macos/rox_proxy_native`:
the plugin imports `FlutterMacOS`, which is only available through the Xcode /
Flutter build. Use `flutter build macos --debug` to verify the full plugin.
