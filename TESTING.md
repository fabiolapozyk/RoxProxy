# Testing Guide

## 🎯 Testing Philosophy

**Obiettivi:**
1. **Copertura completa** del flow proxy (HTTP, HTTPS, MITM, Tunnel)
2. **Test veloci** per sviluppo iterativo
3. **Test affidabili** per CI/CD
4. **Minimo boilerplate** per aggiungere nuovi test

**Strategia:**
- **Unit tests** (Swift): Logica isolata dei singoli componenti
- **Integration tests** (Swift): Interazione tra componenti
- **System tests** (Swift): Integrazione con sistema (networksetup, Keychain)
- **E2E tests** (Flutter): Flow completo con richieste reali

## 🏃 Running Tests

### Swift Tests

```bash
# Tutti i test Swift
swift test

# Test specifici
swift test Tests.RoxProxyTests.Handlers
swift test --filter HTTPProxyHandlerTests

# Con code coverage
swift test --enable-code-coverage
```

### Flutter E2E Tests

```bash
# Tutti gli E2E test
flutter test integration_test/

# Test specifico
flutter test integration_test/proxy_e2e_test.dart

# Verbose
flutter test -v integration_test/
```

## 📁 Test Structure

```
Tests/RoxProxyTests/
├── TestHarness/              # Gestione lifecycle proxy per test
│   └── TestHarness.swift    # Port automatica, CA generation, cleanup
├── TestUtilities/           # Helper per test
│   └── CertificateTestHelper.swift
├── Mocks/                   # Mock per SwiftNIO
│   ├── MockChannelHandlerContext.swift
│   ├── MockChannel.swift
│   ├── MockChannelPipeline.swift
│   ├── MockEventLoop.swift
│   ├── MockProxySessionStore.swift
│   └── MockSettingsStore.swift
├── Handlers/                # Unit test per handler
│   ├── HTTPProxyHandlerTests.swift
│   ├── OutboundHTTPHandlerTests.swift
│   ├── TunnelHandlerTests.swift
│   └── MITMHandlerTests.swift
├── ProxyServerIntegrationTests.swift
├── SystemProxyManagerTests.swift
└── CrashGuardTests.swift

integration_test/
├── proxy_e2e_test.dart      # HTTP/HTTPS interception
├── proxy_tls_error_test.dart # TLS errors, connection failures
└── proxy_system_test.dart   # System proxy config
```

## ✍️ Test Naming Convention

| Tipo | Convenzione | Esempio |
|------|-------------|---------|
| Unit test | `[Class][Method]Test` | `HTTPProxyHandlerParseTargetTest` |
| Integration | `[Feature]IntegrationTest` | `FullProxyFlowIntegrationTest` |
| System | `[Component]SystemTest` | `SystemProxyManagerSystemTest` |
| E2E | Descrittivo | `proxy intercepts HTTP GET requests` |

## 📝 Linee Guida per Nuovi Test

### 1. Swift Unit Tests

**Quando scrivere**: Per ogni nuovo handler o logica complessa

**Template:**
```swift
import Testing
@testable import RoxProxy

@Suite struct NewHandlerTests {
    @Test func handlerDoesX() async throws {
        // Arrange
        let mockContext = MockChannelHandlerContext()
        let mockStore = MockProxySessionStore()
        let handler = NewHandler(store: mockStore)

        // Act
        try await handler.doSomething()

        // Assert
        #expect(mockStore.receivedCall)
        #expect(mockContext.writes.count == 1)
    }
}
```

**Best practices:**
- Usa **sempre** `TestHarness` per test che richiedono proxy avviato
- Usa **sempre** mock per componenti esterni (NIO, Keychain)
- Testa **tutti** i percorsi: success, error, edge cases
- Mantieni test **veloci** (< 100ms cadauno)

### 2. Flutter E2E Tests

**Quando scrivere**: Per funzionalità utente visibili

**Template:**
```dart
testWidgets('Feature X works correctly', (tester) async {
  // Setup
  final proxyChannel = ProxyChannel();
  await proxyChannel.startProxy(port: 19999);

  // Act
  final response = await http.get(
    Uri.parse('http://example.com'),
    proxy: 'http://127.0.0.1:19999',
  );

  // Assert
  expect(response.statusCode, equals(200));

  // Cleanup
  await proxyChannel.stopProxy();
});
```

**Best practices:**
- Usa **sempre** porte uniche (range 18000-25000)
- **Attendi** che il proxy sia pronto (`await Future.delayed(...)`)
- **Pulisc** sempre: stop proxy, rimuovi temp files
- Usa `try/catch` per gestire errori attesi

### 3. Testing Error Scenarios

**Importante**: Testa **sempre** i casi di errore

**Errori da testare:**
- ✅ Timeout connessione
- ✅ DNS failure
- ✅ Connection reset
- ✅ TLS handshake error
- ✅ Certificate error
- ✅ Invalid HTTP request
- ✅ Body size limit (10MB)
- ✅ Pipelining rejection

**Esempio:**
```swift
@Test func proxyHandlesConnectionTimeout() async throws {
    let harness = try TestHarness(portRange: 18000...19000)
    harness.settingsStore.setConnectionTimeout(1) // 1 secondo

    try await harness.start()
    defer { try? await harness.stop() }

    // Connetti a server non rispondente
    do {
        _ = try await harness.makeRequest(to: "http://10.255.255.1:9999")
        #expect(Bool(false), "Dovrebbe lanciare timeout")
    } catch {
        #expect(error is TimeoutError)
    }
}
```

### 4. Test con MITM

**Setup required**: CA installato nel Keychain di test

**Template:**
```swift
@Test func mitmDecryptsHTTPSRequest() async throws {
    let harness = try TestHarness(
        portRange: 18000...19000,
        mitmDomains: ["example.com"]
    )

    try await harness.start()
    defer { try? await harness.stop() }

    // Fai richiesta HTTPS
    let (status, body) = try await harness.makeRequest(
        to: "https://example.com",
        method: "GET"
    )

    #expect(status == 200)
    #expect(!body.isEmpty)
}
```

**Best practices:**
- Aggiungi dominio a `mitmDomains` nel TestHarness
- Usa `client.badCertificateCallback = (_, _, _) => true` per test Dart
- Testa **sempre** sia il path MITM che Tunnel

## 🛠️ Test Utilities

### ProxyMetrics (Thread-Safe Monitoring)

`ProxyMetrics.shared` fornisce accesso alle metriche del proxy per debugging e testing:

```swift
// Accesso alle metriche
let metrics = ProxyMetrics.shared

// Contatori correnti
let requests = metrics.requestCount
let errors = metrics.errorCount
let bytesIn = metrics.bytesReceived
let bytesOut = metrics.bytesSent

// Reset metriche (utile per test isolati)
metrics.reset()

// Uptime
let uptime = metrics.uptime // TimeInterval in secondi

// Rappresentazione JSON (usata da /stats endpoint)
let json = metrics.toJSON()
// Restituisce: ["requests": Int, "errors": Int, "bytes_received": Int, ...]

// Rappresentazione pretty JSON
let prettyJson = metrics.toPrettyJSON()
```

### TestHarness (Swift)

Gestisce automaticamente:
- Selezione porta (range configurabile)
- Generazione CA per MITM
- Avvio/stop proxy
- Cleanup risorse

**Uso:**
```swift
let harness = try TestHarness(
    portRange: 20000...25000,  // Default: 18000...19000
    mitmDomains: ["example.com", "httpbin.org"]
)

try await harness.start()
// ... test logic
try await harness.stop()
```

**Metodi utili:**
```swift
// Fai richiesta HTTP/HTTPS attraverso il proxy
let (statusCode, body) = try await harness.makeRequest(
    to: "https://example.com",
    method: "GET",
    headers: ["Accept": "application/json"],
    body: Data("test".utf8)
)

// Ottieni lo store delle sessioni (per verifiche)
let exchanges = harness.sessionStore.exchanges
```

### Mock Components

Tutti i componenti SwiftNIO sono mockati:

| Mock | Utilizzo |
|------|----------|
| `MockChannelHandlerContext` | Captura write/flush/close |
| `MockChannel` | Traccia operazioni read/write |
| `MockChannelPipeline` | Gestisce handler chain |
| `MockEventLoop` | Simula event loop |
| `MockProxySessionStore` | Storage thread-safe per test |
| `MockSettingsStore` | Gestione settings per test |

## 📊 Testing Tools & Endpoints

### Health Check Endpoint

Il proxy espone un endpoint `/health` per verificare programmaticamente che il proxy sia in esecuzione:

```bash
# Verifica che il proxy sia attivo
curl http://127.0.0.1:8080/health
# Response: {"status":"running","timestamp":"2026-07-21T21:00:00Z"}
```

**Utilizzo nei test:**
```swift
@Test func proxyStartsAndRespondsToHealthCheck() async throws {
    let harness = try TestHarness()
    try await harness.start()
    defer { try? await harness.stop() }
    
    let (status, body) = try await harness.makeRequest(to: "http://127.0.0.1:8080/health")
    #expect(status == 200)
    #expect(body.contains("running"))
}
```

### Statistics Endpoint

Il proxy espone un endpoint `/stats` per recuperare le metriche in tempo reale:

```bash
# Ottieni statistiche proxy
curl http://127.0.0.1:8080/stats
# Response: {
#   "requests": 10,
#   "errors": 0,
#   "bytes_received": 1024,
#   "bytes_sent": 2048,
#   "connect_requests": 2,
#   "mitm_requests": 1,
#   "tunnel_requests": 1,
#   "uptime_seconds": "123.45",
#   "status": "running"
# }
```

**Utilizzo nei test:**
```swift
@Test func proxyTracksRequestCount() async throws {
    let harness = try TestHarness()
    try await harness.start()
    defer { try? await harness.stop() }
    
    // Fai alcune richieste
    _ = try await harness.makeRequest(to: "http://example.com")
    _ = try await harness.makeRequest(to: "http://example.org")
    
    // Verifica contatore richieste
    let (_, statsBody) = try await harness.makeRequest(to: "http://127.0.0.1:8080/stats")
    let stats = try JSONDecoder().decode([String: Int].self, from: statsBody.data(using: .utf8)!)
    #expect(stats["requests"] == 2)
}
```

### ProxyMetrics (Thread-Safe Counters)

`ProxyMetrics.shared` fornisce contatori thread-safe per il monitoraggio del proxy:

| Metrica | Descrizione | Metodo di increment |
|---------|-------------|-------------------|
| `requestCount` | Totale richieste HTTP/HTTPS | `incrementRequests()` |
| `errorCount` | Totale errori | `incrementErrors()` |
| `bytesReceived` | Bytes ricevuti dai client | `addReceivedBytes(_:)` |
| `bytesSent` | Bytes inviati ai client | `addSentBytes(_:)` |
| `connectRequests` | Totale richieste CONNECT | `incrementConnectRequests()` |
| `mitmRequests` | Totale richieste MITM | `incrementMITMRequests()` |
| `tunnelRequests` | Totale richieste Tunnel | `incrementTunnelRequests()` |
| `uptime` | Tempo di attività | `setStartTime(_:)` |

**Esempio di test:**
```swift
@Test func metricsResetOnProxyStart() async throws {
    let harness = try TestHarness()
    
    // Prima dello start, i contatori dovrebbero essere 0 (o reset)
    let metrics = ProxyMetrics.shared
    metrics.reset()
    
    try await harness.start()
    defer { try? await harness.stop() }
    
    #expect(metrics.requestCount == 0)
    #expect(metrics.errorCount == 0)
    #expect(metrics.uptime > 0)
}
```

## 🔍 Debugging Test

### Swift Tests Falliscono con "Port Already in Use"

**Soluzioni:**
1. Aumenta il range di porte:
   ```swift
   TestHarness(portRange: 20000...25000)
   ```
2. Fermare altri proxy in esecuzione:
   ```bash
   lsof -i :18000-19000
   kill -9 <PID>
   ```
3. Usa porte casuali:
   ```swift
   TestHarness(portRange: Int.random(in: 20000...25000)...Int.random(in: 20000...25000))
   ```

### Flutter E2E Tests Falliscono con Connection Refused

**Checklist:**
- [ ] Proxy avviato: `await proxyChannel.startProxy(...)`
- [ ] Proxy in ascolto: `netstat -an | grep <port>`
- [ ] Attesa sufficientemente lunga: `await Future.delayed(Duration(milliseconds: 500))`
- [ ] Porta non bloccata da firewall
- [ ] CA trust configurato (per HTTPS)

### Test Falliscono su CI ma Passano Locally

**Soluzioni:**
- Aumenta timeout nei test
- Usa range di porte uniche per ogni job CI
- Aggiungi retry logic per test flaky
- Assicurati che tutti i file temporanei siano puliti

**Esempio CI (GitHub Actions):**
```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Flutter
        uses: subosito/flutter-action@v2
      - name: Run Swift tests
        run: swift test --enable-code-coverage
      - name: Run Flutter E2E tests
        run: flutter test integration_test/
```

## 📊 Code Coverage

**Obiettivo**: > 80% coverage

**Comando:**
```bash
# Swift coverage
swift test --enable-code-coverage
xcrun llvm-cov show -instr-profile .build/debug/codecov/default.profdata \
  -object .build/debug/RoxProxyPackageTests.xctest/Contents/MacOS/RoxProxyPackageTests \
  -format=text

# Flutter coverage
flutter test --coverage integration_test/
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## ✅ Checklist prima di Push

- [ ] Tutti i test Swift passano (`swift test`)
- [ ] Tutti i test Flutter passano (`flutter test integration_test/`)
- [ ] Nuovi test aggiunti per nuova funzionalita
- [ ] Test aggiornati per bugfix
- [ ] Log aggiunti per debugging (os_log)
- [ ] Metriche aggiornate (ProxyMetrics) se applicabile
- [ ] Endpoint /health e /stats testati
- [ ] Documentazione aggiornata (MISTRAL.md, TESTING.md, README.md)

## 🚨 Common Pitfalls

1. **Dimenticare di stoppare il proxy**:
   ```swift
   // ❌ SBAGLIATO - Proxy rimane in esecuzione
   func testSomething() async throws {
       let harness = try TestHarness()
       try await harness.start()
       // ... test
       // Missing: try await harness.stop()
   }

   // ✅ GIUSTO - Cleanup con defer
   func testSomething() async throws {
       let harness = try TestHarness()
       try await harness.start()
       defer { try? await harness.stop() }
       // ... test
   }
   ```

2. **Non gestire gli errori**:
   ```swift
   // ❌ SBAGLIATO - Test fallisce su qualsiasi errore
   @Test func testRequest() async throws {
       let (status, _) = try await harness.makeRequest(to: "http://example.com")
       #expect(status == 200)
   }

   // ✅ GIUSTO - Gestione errori esplicita
   @Test func testRequest() async throws {
       do {
           let (status, _) = try await harness.makeRequest(to: "http://example.com")
           #expect(status == 200)
       } catch {
           #expect(Bool(false), "Request failed: \(error)")
       }
   }
   ```

3. **Test troppo lenti**:
   ```swift
   // ❌ SBAGLIATO - Timeout troppo lungo
   harness.settingsStore.setConnectionTimeout(30) // 30 secondi!

   // ✅ GIUSTO - Timeout breve per test
   harness.settingsStore.setConnectionTimeout(1) // 1 secondo
   ```

4. **Dimenticare di loggare**:
   ```swift
   // ❌ SBAGLIATO - Nessun log per debugging
   func handleRequest() {
       // ... complex logic
   }

   // ✅ GIUSTO - Log a diversi livelli
   func handleRequest() {
       ProxyLogger.http.debug("Handling request")
       // ... logic
       if error {
           ProxyLogger.http.error("Request failed: %@", error)
       }
   }
   ```

## 📚 Risorse Utili

- [Swift Testing Framework](https://github.com/apple/swift-testing)
- [Flutter Integration Testing](https://docs.flutter.dev/testing/integration-tests)
- [os_log Documentation](https://developer.apple.com/documentation/os/logging)
- [Console.app Usage](https://support.apple.com/guide/console/welcome/mac)

