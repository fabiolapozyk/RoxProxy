# Rox Proxy

A macOS 14+ desktop HTTP/HTTPS proxy inspector. Built with Flutter (UI) and Swift/SwiftNIO (native proxy engine).

## Features

- Intercept and inspect HTTP and HTTPS traffic
- MITM TLS decryption for configured domains
- Live request/response stream with filtering
- Body viewer with gzip/deflate decompression
- CA certificate installer for macOS System Keychain
- Certificate download endpoint for mobile/LAN devices (`http://cert.roxproxy/`)
- Crash recovery: system proxy is restored on unclean exit

## Known Limitations

- **Brotli compression**: Responses compressed with Brotli (`br`) are not supported and will display an error message. Use gzip or deflate compression instead.

## Requirements

- macOS 14 (Sonoma) or later
- Flutter 3.x
- Xcode 15+
- Swift 5.9+

## Getting started

```bash
# Install dependencies
flutter pub get

# Run in debug mode
flutter run -d macos

# Build release
flutter build macos
```

## Architecture

The UI is Flutter/Dart. All proxy logic lives in the local plugin `packages/rox_proxy_native`, written in Swift with SwiftNIO.

```
lib/                         # Flutter/Dart app
  main.dart                  # Entry point
  app.dart                   # MaterialApp + theme
  models/                    # CapturedExchange, DomainRule, ProxySettings, ProxyState
  services/                  # ProxyChannel (MethodChannel/EventChannel), SettingsService
  providers/                 # Riverpod providers
  utils/                     # DataFormatting, BodyRenderer
  ui/                        # Widgets

packages/rox_proxy_native/   # Swift plugin
  Sources/rox_proxy_native/
    Bridge/                  # Flutter ↔ Swift bridge
    Proxy/                   # SwiftNIO handlers
    Certificate/             # CA generation, per-domain certs, Keychain installer
    SystemProxy/             # networksetup integration, crash guard
    Models/                  # Swift-side models
```

### Platform channels

| Channel | Direction | Methods |
|---|---|---|
| `com.roxproxy/control` | Flutter → Swift | `startProxy`, `stopProxy`, `getProxyState`, `installCACertificate`, `checkCATrust`, `getCAStatus`, `fetchBody`, `releaseBody`, `releaseAllBodies`, `decompressBody` |
| `com.roxproxy/exchanges` | Swift → Flutter | streams `{type, exchange}` events |

## Inspecting traffic from mobile / LAN devices

The proxy listens on all network interfaces (`0.0.0.0`), so devices on the same Wi-Fi network can route traffic through it.

1. Find your Mac's local IP (shown in Settings → Certificate).
2. On the mobile device, set the HTTP/HTTPS proxy to `<mac-ip>:<port>` (default port `8888`).
3. Open `http://cert.roxproxy/` in the device browser — the proxy serves the CA certificate directly.
4. Install and trust the certificate in the device settings.

> **iOS**: Settings → General → VPN & Device Management → install, then Settings → General → About → Certificate Trust Settings → enable.
>
> **Android**: Settings → Security → Install certificate → CA certificate.

## Certificate infrastructure

On first launch, `CertificateAuthority` generates a self-signed P-256 root CA stored in `~/Library/Application Support/RoxProxy/`. Per-domain leaf certificates are signed on demand and cached in memory. `KeychainInstaller` installs the root CA into the macOS System Keychain (requires admin password).

## macOS entitlements

App Sandbox is disabled — required for TCP binding on all interfaces, `networksetup` subprocess calls, and Keychain trust operations.

## Security warning on first launch

When you first launch Rox Proxy, macOS may show a security warning:

> "Rox Proxy" cannot be opened because Apple cannot check it for malicious software.

This happens because the app is not signed with an Apple Developer ID and the sandbox is disabled (necessary for proxy functionality).

### How to open Rox Proxy:

**Method 1: Open from Finder**
1. Go to your Applications folder
2. Find "Rox Proxy" in the list
3. Control-click (or right-click) on the app icon
4. Select "Open" from the context menu
5. Click "Open" in the security dialog that appears

**Method 2: Using Terminal**
```bash
# Remove quarantine flag
sudo xattr -r -d com.apple.quarantine /Applications/Rox\ Proxy.app

# Add to security exceptions
sudo spctl --add /Applications/Rox\ Proxy.app
```

**Method 3: System Preferences**
1. Try opening the app normally (double-click)
2. When blocked, open System Settings → Privacy & Security
3. Under the "Security" section, you'll see:
   > "Rox Proxy" was blocked because it is not from an identified developer
4. Click "Open Anyway"

After the first launch, macOS will remember your choice and won't show this warning again.

---

## Tests

```bash
# Swift (unit + integration + system tests)
swift test

# Flutter E2E tests
flutter test integration_test/
```

**Copertura:**
- HTTP/HTTPS interception, MITM decryption, certificate handling
- TLS errors, tunnel creation, connection failures
- DNS failure, connection reset, non-routable IP handling
- Pipelining rejection (HTTP/1.1)
- System proxy configuration (macOS networksetup)
- Crash recovery (sentinel file, signal handlers)

Dettagli in [TESTING.md](TESTING.md).

---

## Contributing

When adding new features, ensure all tests pass. See [TESTING.md](TESTING.md) for guidelines.
