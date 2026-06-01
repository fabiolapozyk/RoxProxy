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

## Running Tests

### Swift Tests (Unit & Integration)

The project includes comprehensive test coverage for the Swift proxy core using the native `swift test` framework.

```bash
# Run all Swift tests
swift test

# Run specific test suite
swift test Tests.RoxProxyTests.Handlers

# Run with code coverage
swift test --enable-code-coverage
```

**Test Structure:**
```
Tests/RoxProxyTests/
├── TestHarness/              # Proxy lifecycle management
│   └── TestHarness.swift      # Automatic port selection, CA generation
├── TestUtilities/           # Helper classes
│   └── CertificateTestHelper.swift
├── Mocks/                   # Mock implementations for NIO components
│   ├── MockProxySessionStore.swift
│   ├── MockSettingsStore.swift
│   └── MockChannelHandlerContext.swift
├── Handlers/                # Unit tests for proxy handlers
│   ├── HTTPProxyHandlerTests.swift
│   ├── OutboundHTTPHandlerTests.swift
│   ├── TunnelHandlerTests.swift
│   └── MITMHandlerTests.swift
└── ProxyServerIntegrationTests.swift
```

### Flutter Tests (E2E)

End-to-end tests that verify the proxy works with real HTTP/HTTPS requests through the Flutter-Swift bridge.

```bash
# Run all E2E tests
flutter test integration_test/

# Run specific E2E test file
flutter test integration_test/proxy_e2e_test.dart

# Run with verbose output
flutter test -v integration_test/
```

**E2E Test Coverage:**
- HTTP GET/POST request interception
- Request/response header capture
- Response status code capture
- HTTPS CONNECT tunnel creation
- Real server requests (example.com, httpbin.org)
- Body capture for POST requests

---

## Test Architecture

### Layered Testing Approach

| Layer | Framework | Purpose | Location |
|-------|-----------|---------|----------|
| **Unit Tests** | Swift Testing | Test individual handlers in isolation | `Tests/RoxProxyTests/Handlers/` |
| **Integration Tests** | Swift Testing | Test component interactions | `Tests/RoxProxyTests/ProxyServerIntegrationTests.swift` |
| **E2E Tests** | Flutter integration_test | Test full proxy flow with real network calls | `integration_test/` |

### Test Harness

The `TestHarness` class provides a centralized way to manage proxy lifecycle during tests:

```swift
// Create harness with automatic port selection
let harness = try TestHarness(portRange: 18000...19000)

// Start proxy
try await harness.start()

// Make requests through proxy
let (statusCode, body) = try await harness.makeRequest(
    to: "http://example.com",
    method: "GET"
)

// Stop proxy
try await harness.stop()
```

Features:
- Automatic port selection (avoids conflicts)
- MITM certificate generation for HTTPS tests
- Thread-safe with `@MainActor` mock stores
- Automatic cleanup of temporary resources

### Mock Components

All SwiftNIO components are mocked for unit testing:

- **MockChannelHandlerContext** - Captures writes, flushes, closes
- **MockChannel** - Tracks write/read operations
- **MockChannelPipeline** - Manages handler chain
- **MockEventLoop** - Provides realistic event loop simulation
- **MockProxySessionStore** - Thread-safe exchange storage
- **MockSettingsStore** - Thread-safe settings management

---

## Next Steps

### 1. Run All Tests
Verify that the test infrastructure works correctly:
```bash
# Run Swift tests
swift test

# Run Flutter E2E tests
flutter test integration_test/
```

### 2. Add MITM E2E Tests (Flutter)
Currently, MITM testing requires CA certificate trust setup. Consider adding:
- Automatic CA installation in test setup
- Tests for decrypted HTTPS traffic capture
- Tests for certificate validation

### 3. Configure CI/CD
Set up GitHub Actions to run tests automatically:
```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Flutter
        uses: subosito/flutter-action@v2
      - name: Run Flutter E2E tests
        run: flutter test integration_test/
      - name: Run Swift tests
        run: swift test
```

### 4. Expand Test Coverage

**Missing Test Areas:**
- Connection timeout handling
- Body truncation at 10MB limit
- Pipelining rejection
- Network error scenarios (connection reset, DNS failure)
- TLS handshake errors
- System proxy configuration
- Crash recovery scenarios

**Example Test to Add:**
```swift
// Test timeout handling
@Test func proxyHandlesConnectionTimeout() async throws {
    let harness = try TestHarness()
    try await harness.start()
    defer { try? await harness.stop() }
    
    // Configure short timeout
    harness.settingsStore.setConnectionTimeout(1)
    
    // Try to connect to non-responsive server
    // Verify timeout error is captured
}
```

### 5. Add Test for Mobile/LAN Certificate Endpoint
Test the `http://cert.roxproxy/` certificate download endpoint:
```dart
testWidgets('Certificate endpoint serves CA certificate', (tester) async {
  final response = await HttpClient().getUrl(
    Uri.parse('http://127.0.0.1:$proxyPort/cert.roxproxy/')
  );
  expect(response.statusCode, equals(200));
  // Verify certificate is valid DER
});
```

### 6. Performance Testing
Add benchmark tests for:
- Request throughput (requests/second)
- Memory usage with many exchanges
- Response time impact of proxy interception

### 7. Add Test Documentation
Create a `TESTING.md` file with:
- How to write new tests
- Test organization conventions
- Mocking guidelines
- Troubleshooting test failures

---

## Troubleshooting Tests

### Swift Tests Fail with "Port Already in Use"
**Solution:** Each test harness uses automatic port selection. If ports are exhausted:
- Increase the port range: `TestHarness(portRange: 20000...25000)`
- Stop other proxy instances running on your machine
- Use `lsof -i :18000-19000` to find conflicting processes

### Flutter E2E Tests Fail with Connection Refused
**Solution:**
- Verify proxy is started: `await proxyChannel.startProxy(...)`
- Check proxy is listening: `netstat -an | grep 19999`
- Ensure test waits for proxy to start: `await Future.delayed(Duration(milliseconds: 500))`
- Verify port is not blocked by firewall

### Tests Fail on CI but Pass Locally
**Solution:**
- CI may have stricter security policies
- Add retry logic for flaky tests
- Use unique port ranges for each CI job
- Ensure all temporary files are cleaned up in `tearDownAll`

### MITM Tests Fail with Certificate Errors
**Solution:**
- Install CA certificate in test environment
- Use `client.badCertificateCallback = (cert, host, port) => true`
- For Flutter tests: implement CA trust setup in `setUpAll`

---

## Contributing

When adding new features:

1. **Add unit tests** for new handler logic
2. **Add integration tests** for component interactions
3. **Add E2E tests** for user-facing functionality
4. **Run all tests** before creating a PR
5. **Update documentation** in this README

Test naming convention:
- Unit tests: `[ClassName][MethodName]Test` (e.g., `HTTPProxyHandlerParseTargetTest`)
- Integration tests: `[Feature]IntegrationTest` (e.g., `FullProxyFlowIntegrationTest`)
- E2E tests: Descriptive names (e.g., `proxy intercepts HTTP GET requests`)
