# Rox Proxy

[![CI](https://github.com/flapozyk/RoxProxy/actions/workflows/ci.yml/badge.svg)](https://github.com/flapozyk/RoxProxy/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A macOS 14+ desktop HTTP/HTTPS proxy inspector. Built with Flutter (UI) and Swift/SwiftNIO (native proxy engine).

## Features

- Intercept and inspect HTTP and HTTPS traffic
- MITM TLS decryption for configured domains
- Live request/response stream with filtering
- Body viewer with gzip/deflate decompression
- Request/response **breakpoints**: pause traffic matching a rule, inspect and edit before it continues
- **Map Local**: serve local content in place of remote responses, per URL pattern
- **Replay**: re-send a captured request, optionally edited, and inspect the new response
- CA certificate installer for macOS System Keychain
- Certificate download endpoint for mobile/LAN devices (`http://cert.roxproxy/`)
- Internal diagnostics endpoints: `GET /health` and `GET /stats` on the proxy port
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

Prebuilt releases (DMG) are attached to [GitHub Releases](https://github.com/flapozyk/RoxProxy/releases).
The app is not notarized yet: see "Security warning on first launch" below.

## Roadmap

Ideas tracked as issues with the [`roadmap`](https://github.com/flapozyk/RoxProxy/issues?q=label%3Aroadmap) label:

- [Rewrite rules automatiche](https://github.com/flapozyk/RoxProxy/issues/9) — declarative header/body modification without manual breakpoints
- [Export HAR](https://github.com/flapozyk/RoxProxy/issues/10) — session export in HAR 1.2 format

Contributions welcome: open an issue or pick one up.

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
# Unit + widget tests (Dart)
flutter test test/

# Core proxy tests (Swift, standalone SPM package)
cd packages/rox_proxy_native/macos/CoreTests && swift test

# Full verification (format + analyze + tests + debug build)
./scripts/verify.sh

# End-to-end smoke test (release build, launch app, /health, /stats, real HTTP request)
./scripts/smoke.sh
```

**Copertura:**
- HTTP/HTTPS interception, MITM decryption, certificate handling
- TLS errors, tunnel creation, connection failures
- DNS failure, connection reset, non-routable IP handling
- Pipelining rejection (HTTP/1.1)
- Breakpoints, Map Local, replay
- System proxy configuration (macOS networksetup)
- Crash recovery (sentinel file, signal handlers)

Dettagli in [TESTING.md](TESTING.md).

## Releases

Tagging a `v*` tag on `main` triggers `.github/workflows/release.yml`: builds the release app, packages it in a DMG and publishes a draft GitHub Release. To publish:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Then review and publish the draft release on GitHub. Apple notarization is not wired up yet (no Developer ID configured).

---

## Contributing

When adding new features, ensure all tests pass. See [TESTING.md](TESTING.md) for guidelines.
