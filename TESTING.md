# Testing Guide

This document covers the testing infrastructure for Rox Proxy, including how to write, organize, and troubleshoot tests.

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

## Test Architecture

### Layered Testing Approach

| Layer | Framework | Purpose | Location |
|-------|-----------|---------|----------|
| **Unit Tests** | Swift Testing | Test individual handlers in isolation | `Tests/RoxProxyTests/Handlers/` |
| **Integration Tests** | Swift Testing | Test component interactions | `Tests/RoxProxyTests/ProxyServerIntegrationTests.swift` |
| **System Tests** | Swift Testing | Test system proxy config and crash recovery | `Tests/RoxProxyTests/` |
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

## Expanding Test Coverage

### Missing Test Areas

- Connection timeout handling (partially covered in Dart TLS error tests)
- Body truncation at 10MB limit
- TLS handshake errors

**Recently Added Coverage:**
- ✅ Pipelining rejection - Swift unit tests in `HTTPProxyHandlerPipeliningTests`
- ✅ Network error scenarios (connection reset, DNS failure) - Dart tests in `TLS Error Tests - Network Error Scenarios` group
- ✅ System proxy configuration - Swift unit tests in `SystemProxyManagerTests`
- ✅ Crash recovery scenarios - Swift unit tests in `CrashGuardTests`

### Example Tests

**Swift - Timeout handling:**
```swift
@Test func proxyHandlesConnectionTimeout() async throws {
    let harness = try TestHarness()
    try await harness.start()
    defer { try? await harness.stop() }
    
    harness.settingsStore.setConnectionTimeout(1)
    
    // Try to connect to non-responsive server
    // Verify timeout error is captured
}
```

**Dart - Certificate endpoint:**
```dart
testWidgets('Certificate endpoint serves CA certificate', (tester) async {
  final response = await HttpClient().getUrl(
    Uri.parse('http://127.0.0.1:$proxyPort/cert.roxproxy/')
  );
  expect(response.statusCode, equals(200));
});
```

## CI/CD Configuration

Example GitHub Actions workflow:

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

## Troubleshooting

### Swift Tests Fail with "Port Already in Use"

Each test harness uses automatic port selection. If ports are exhausted:
- Increase the port range: `TestHarness(portRange: 20000...25000)`
- Stop other proxy instances running on your machine
- Use `lsof -i :18000-19000` to find conflicting processes

### Flutter E2E Tests Fail with Connection Refused

- Verify proxy is started: `await proxyChannel.startProxy(...)`
- Check proxy is listening: `netstat -an | grep 19999`
- Ensure test waits for proxy to start: `await Future.delayed(Duration(milliseconds: 500))`
- Verify port is not blocked by firewall

### Tests Fail on CI but Pass Locally

- CI may have stricter security policies
- Add retry logic for flaky tests
- Use unique port ranges for each CI job
- Ensure all temporary files are cleaned up in `tearDownAll`

### MITM Tests Fail with Certificate Errors

- Install CA certificate in test environment
- Use `client.badCertificateCallback = (cert, host, port) => true`
- For Flutter tests: implement CA trust setup in `setUpAll`

## Test Naming Convention

- **Unit tests**: `[ClassName][MethodName]Test` (e.g., `HTTPProxyHandlerParseTargetTest`)
- **Integration tests**: `[Feature]IntegrationTest` (e.g., `FullProxyFlowIntegrationTest`)
- **E2E tests**: Descriptive names (e.g., `proxy intercepts HTTP GET requests`)

## Guidelines

When adding new features:

1. **Add unit tests** for new handler logic
2. **Add integration tests** for component interactions
3. **Add E2E tests** for user-facing functionality
4. **Run all tests** before creating a PR
5. **Update documentation** in this file
