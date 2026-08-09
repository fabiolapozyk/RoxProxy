# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Dopo OGNI modifica, eseguire la verifica prima di dichiarare il lavoro finito.

```bash
# Verifica completa (format + analyze + unit test + swift test + build debug)
./scripts/verify.sh

# Verifica rapida (salta build debug, ~1-2 min)
./scripts/verify.sh --fast

# Smoke test end-to-end (build release, launch app, /health, /stats, richiesta HTTP reale, clean shutdown)
./scripts/smoke.sh

# Run (debug)
flutter run -d macos
```

> **Non eseguire `swift build`/`swift test` nella dir del plugin**:
> fallisce con "no such module 'FlutterMacOS'". Per il core Swift:
> `cd packages/rox_proxy_native/macos/CoreTests && swift test`.
> Il check di compilazione completo del plugin avviene tramite `flutter build macos --debug`.

## Architecture

RoxProxy is a macOS 14+ desktop app that intercepts HTTP/HTTPS traffic. The **UI is Flutter/Dart**; all native proxy logic lives in a local Flutter plugin (`packages/rox_proxy_native`) written in Swift with SwiftNIO.

### Project layout

```
lib/                         # Flutter/Dart app
  main.dart                  # Entry point: ProviderScope + RoxProxyApp
  app.dart                   # MaterialApp with Material 3 theme
  models/                    # Dart models (CapturedExchange, DomainRule, ProxySettings, ProxyState)
  services/                  # ProxyChannel (MethodChannel/EventChannel), SettingsService (JSON)
  providers/                 # Riverpod providers (exchange list, settings, proxy state, CA trust)
  utils/                     # DataFormatting, BodyRenderer
  ui/
    main_window.dart         # Root scaffold: toolbar, sidebar, detail pane
    request_list/            # Virtualized exchange list
    detail/                  # Detail view: headers tab + lazy body tab
    settings/                # Settings dialog (General, HTTPS Domains, Certificate)
    components/              # Shared widgets (MethodBadge, StatusIndicator, etc.)

packages/rox_proxy_native/   # Local Flutter plugin (Swift)
  macos/rox_proxy_native/
    Sources/rox_proxy_native/
      Bridge/                # NEW: RoxProxyNativePlugin, ProxyMethodHandler,
                             #      ExchangeStreamHandler, BridgeSessionStore,
                             #      BodyStore, ExchangeSerializer
      Proxy/                 # SwiftNIO handlers (HTTPProxyHandler, MITMHandler, etc.)
      Certificate/           # CertificateAuthority, DomainCertificateCache, KeychainInstaller
      SystemProxy/           # SystemProxyManager, CrashGuard
      Models/                # CapturedExchange, DomainRule, ProxySettings (Swift side)
      Utilities/             # GzipDecompressor
  macos/CoreTests/           # Package SPM standalone: test del core Swift puro
                             # (symlink dei sorgenti; NON si può testare via swift test
                             # il plugin completo perché importa FlutterMacOS)
```

### Platform channels

- **MethodChannel** `com.roxproxy/control` — Flutter → Swift: `startProxy`, `stopProxy`, `getProxyState`, `installCACertificate`, `checkCATrust`, `getCAStatus`, `fetchBody`, `releaseBody`, `releaseAllBodies`, `decompressBody`
- **EventChannel** `com.roxproxy/exchanges` — Swift → Flutter: streams `{type: "new"|"update", exchange: {...}}` maps

### Request flow (Swift side)

1. **`ProxyServer`** — SwiftNIO `ServerBootstrap` on `127.0.0.1:<port>`. Each connection gets an HTTP codec + `HTTPProxyHandler`.
2. **`HTTPProxyHandler`** — plain HTTP: forwards via `OutboundHTTPHandler`; `CONNECT`: tunnels blindly (`TunnelHandler`) or MITM-intercepts if host matches a `DomainRule`.
3. **MITM path** — `CertificateAuthority` issues a forged leaf cert → `NIOSSLServerHandler` → `MITMSetupHandler` → `MITMHandler` makes upstream TLS connection and captures the exchange.
4. **`BridgeSessionStore`** (replaces the old `ProxySessionStore`) — receives NIO thread callbacks via `Task { @MainActor in ... }` and pushes serialized events to the Flutter EventChannel via `ExchangeStreamHandler`.

### Body transfer pattern

Bodies are NOT inlined in events. Swift stores `Data` in `BodyStore` keyed by UUID; the event carries a `requestBodyRef`/`responseBodyRef` string. Dart calls `fetchBody(ref)` lazily when the user opens an exchange. `FlutterStandardTypedData` transfers `Uint8List` as raw bytes.

### Dart state management (Riverpod)

| Provider | Type | Purpose |
|---|---|---|
| `proxyChannelProvider` | `Provider` | Singleton `ProxyChannel` |
| `settingsProvider` | `StateNotifierProvider` | `ProxySettings`, persisted to JSON |
| `proxyStateProvider` | `StateNotifierProvider` | `ProxyState` sealed class |
| `exchangeListProvider` | `StateNotifierProvider` | Live list, fed by EventChannel stream |
| `filteredExchangesProvider` | `Provider` (derived) | Filtered by `filterTextProvider` |
| `selectedExchangeProvider` | `Provider` (derived) | Currently selected exchange |
| `caTrustProvider` | `StateNotifierProvider` | CA initialized/trusted state |

### Certificate infrastructure

`CertificateAuthority` generates a self-signed P-256 root CA on first launch, stored in `~/Library/Application Support/RoxProxy/`. Per-domain leaf certs are signed on demand and cached by `DomainCertificateCache`. `KeychainInstaller` installs the root CA into the macOS System Keychain.

### macOS entitlements

App Sandbox is **disabled** (required for TCP binding, `networksetup` subprocess, Keychain trust). Network client + server entitlements are enabled.

### Crash recovery

Swift registers `NSApplication.willTerminateNotification` in `RoxProxyNativePlugin` to stop the proxy and disable the system proxy on clean exit. `CrashGuard` (signal handler + sentinel file) handles unclean exits on relaunch.
