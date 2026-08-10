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

### Verifica completa (consigliata)

```bash
# Format + analyze + unit test Dart + swift test + build debug
./scripts/verify.sh

# Rapida (salta il build debug)
./scripts/verify.sh --fast

# Smoke test end-to-end (build release, launch app, /health, /stats, richiesta HTTP reale, clean shutdown)
./scripts/smoke.sh
```

### Swift Tests

```bash
# Tutti i test Swift (core puro, package standalone)
cd packages/rox_proxy_native/macos/CoreTests && swift test

# Test specifici
swift test --filter DomainRuleTests
swift test --filter ProxyServerTests

# Con code coverage
swift test --enable-code-coverage
```

> **Nota**: il core Swift è testato tramite il package standalone `CoreTests`,
> che compila i sorgenti puri (Proxy/, Certificate/, Models/, Utilities/, MapLocal/)
> via symlink. Il plugin completo (`RoxProxyNativePlugin`) non è testabile via
> `swift test` perché importa FlutterMacOS: la sua compilazione è verificata da
> `flutter build macos --debug`.

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
packages/rox_proxy_native/macos/CoreTests/
├── Package.swift            # Package standalone (deps: NIO, NIOSSL, X509, Crypto)
└── Tests/CoreTests/
    ├── (symlink ai sorgenti puri del plugin)   # Proxy/, Certificate/, Models/, ...
    ├── ExchangeStreamHandlerStub.swift         # Stub del handler Flutter-only
    ├── MapLocalTests.swift                     # Test MapLocalMatcher/Handler
    ├── DomainRuleTests.swift                   # Matching wildcard/exact
    ├── ProxyServerTests.swift                  # Lifecycle, bind, /health, /stats
    ├── GzipDecompressorTests.swift             # gzip/zlib/deflate round-trip
    ├── BodyStoreTests.swift                    # Store/fetch/release corpi
    └── ExchangeSerializerTests.swift           # Serializzazione exchange

test/                         # Unit test Dart (Riverpod, widget)
integration_test/             # E2E (richiedono rete, eseguibili solo localmente)
├── proxy_e2e_test.dart      # HTTP/HTTPS interception
├── proxy_mitm_test.dart     # MITM
├── proxy_tls_error_test.dart # TLS errors, connection failures
└── proxy_replay_recovery_config_test.dart
```

## ✍️ Test Naming Convention

| Tipo | Convenzione | Esempio |
|------|-------------|---------|
| Unit test | `[Class]Tests` + `test[...]` | `DomainRuleTests.testWildcardMatchWorks` |
| Integration | `[Class]Tests` + `test[...]` | `ProxyServerTests.testServerBindsAndServesHealthEndpoint` |
| E2E | Descrittivo | `proxy intercepts HTTP GET requests` |

## 📝 Linee Guida per Nuovi Test

### 1. Swift Unit Tests (CoreTests)

**Quando scrivere**: Per ogni nuova logica nel core (Proxy/, Certificate/, Models/, Utilities/, MapLocal/).

I test vivono in `packages/rox_proxy_native/macos/CoreTests/Tests/CoreTests/` e usano **XCTest**.
I sorgenti del plugin sono compilati nel test target via symlink: nessun `@testable import`,
i tipi sono direttamente accessibili.

**Template:**
```swift
import Foundation
import XCTest

final class NewHandlerTests: XCTestCase {
    func testHandlerDoesX() {
        let handler = NewHandler(store: makeStore())
        XCTAssertEqual(handler.doSomething(), expected)
    }
}
```

**Best practices:**
- Testa **tutti** i percorsi: success, error, edge cases
- Mantieni test **veloci** (< 100ms cadauno)
- Per il `ProxyServer` usa porte casuali (range 20000-25000) e ferma sempre il server
- Se un sorgente puro dipende da un tipo Flutter-only (es. `ExchangeStreamHandler`),
  aggiungi uno stub nel target di test con la stessa firma
- Per nuovi file nel core: se già esiste un test che usa tipi stub, verifica che lo stub
  non entri in conflitto con i sorgenti reali ora symlinkati

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
- **Pulisci** sempre: stop proxy, rimuovi temp files
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
- ✅ Bind failure (porta occupata)

**Esempio:**
```swift
@MainActor
func testServerFailsToStartOnOccupiedPort() async throws {
    let port = nextPort()
    let server1 = ProxyServer(port: port, store: makeStore())
    try await server1.start()

    let server2 = ProxyServer(port: port, store: makeStore())
    do {
        try await server2.start()
        XCTFail("Expected start to fail on occupied port \(port)")
    } catch ProxyServer.ProxyError.bindFailed(let failedPort, _) {
        XCTAssertEqual(failedPort, port)
    }
    try? await server1.stop()
}
```

### 4. Test con MITM

**Setup richiesto**: CA installato nel Keychain di test; i test MITM completi
sono coperti dagli E2E in `integration_test/proxy_mitm_test.dart`
(richiedono rete e possono girare solo localmente).

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

### ProxyServer nei test (CoreTests)

I test di integrazione col proxy (`ProxyServerTests.swift`) avviano il server reale
su una porta casuale (range 20000-25000) e verificano gli endpoint interni
via socket TCP raw.

**Uso:**
```swift
@MainActor
func testServerStartsAndAnswers() async throws {
    let server = ProxyServer(port: nextPort(), store: makeStore())
    try await server.start()

    let response = try await requestTo(
        port: port,
        request: "GET http://127.0.0.1:\(port)/health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
    )
    XCTAssertTrue(response.hasPrefix("HTTP/1.1 200"))

    try? await server.stop()
}
```

**Best practices:**
- Ferma sempre il server alla fine del test (una porta lasciata aperta blocca i test successivi)
- Porte casuali: `Int.random(in: 20000...25000)` per evitare collisioni
- `ProxyServer` è `@MainActor`: marca la classe test `@MainActor`

### Stub per tipi Flutter-only

Alcuni sorgenti puri referenziano tipi che esistono solo nel plugin completo
(es. `BridgeSessionStore` usa `ExchangeStreamHandler`, che importa FlutterMacOS).
In quel caso aggiungi nel target di test uno stub con la stessa firma:

| Stub | Sostituisce |
|------|-------------|
| `ExchangeStreamHandlerStub.swift` | `Bridge/ExchangeStreamHandler.swift` (Flutter-only) |

**Attenzione**: se in futuro i sorgenti reali vengono symlinkati (es. aggiungendo
`BridgeSessionStore`), gli stub con lo stesso nome DEVONO essere rimossi per evitare
duplicati.

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
@MainActor
func testServerServesHealthEndpoint() async throws {
    // Vedi ProxyServerTests.swift in CoreTests
    let server = ProxyServer(port: nextPort(), store: makeStore())
    try await server.start()
    let response = try await requestTo(port: port, request: "GET http://127.0.0.1:\(port)/health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
    XCTAssertTrue(response.hasPrefix("HTTP/1.1 200"))
    try? await server.stop()
}
```

In alternativa, `scripts/smoke.sh` verifica `/health` e `/stats` sull'app release reale.

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
@MainActor
func testMetricsResetOnStart() async throws {
    ProxyMetrics.shared.reset()
    let server = ProxyServer(port: nextPort(), store: makeStore())
    try await server.start()

    XCTAssertEqual(ProxyMetrics.shared.requestCount, 0)
    XCTAssertEqual(ProxyMetrics.shared.errorCount, 0)
    XCTAssertNotNil(ProxyMetrics.shared.startTime)
    try? await server.stop()
}
```

## 🔍 Debugging Test

### Swift Tests Falliscono con "Port Already in Use"

**Soluzioni:**
1. Usa porte casuali nei test:
   ```swift
   nextPort() // contatore interno (vedi ProxyServerTests) oppure
   Int.random(in: 20000...25000)
   ```
2. Fermare altri proxy in esecuzione:
   ```bash
   lsof -i :20000-25000
   kill -9 <PID>
   ```
3. Verificare che i test precedenti non abbiano lasciato server attivi
   (ogni test deve stoppare il proprio `ProxyServer`).

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

Il CI del repo è in `.github/workflows/ci.yml` e replica `verify.sh`:
format → analyze → `flutter test test/` → `swift test` (CoreTests) → `flutter build macos --debug`.

```yaml
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: dart format --output=none --set-exit-if-changed lib test integration_test
      - run: flutter analyze
      - run: flutter test test/
      - working-directory: packages/rox_proxy_native/macos/CoreTests
        run: swift test
      - run: flutter build macos --debug
```

> Gli E2E (`integration_test/`) richiedono rete e non girano in CI: eseguili
> localmente con `flutter test integration_test/`.

## 📊 Code Coverage

**Obiettivo**: > 80% coverage

**Comando:**
```bash
# Swift coverage (CoreTests)
cd packages/rox_proxy_native/macos/CoreTests
swift test --enable-code-coverage
xcrun llvm-cov show -instr-profile .build/debug/codecov/default.profdata \
  -object .build/debug/CoreTestsPackageTests.xctest/Contents/MacOS/CoreTestsPackageTests \
  -format=text

# Flutter coverage
flutter test --coverage test/
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
   // ❌ SBAGLIATO - Proxy rimane in esecuzione, la porta resta occupata
   @MainActor
   func testSomething() async throws {
       let server = ProxyServer(port: nextPort(), store: makeStore())
       try await server.start()
       // ... test
       // Missing: stop!
   }

   // ✅ GIUSTO - Stop esplicito alla fine del test
   @MainActor
   func testSomething() async throws {
       let server = ProxyServer(port: nextPort(), store: makeStore())
       try await server.start()
       // ... test
       try? await server.stop()
   }
   ```

2. **Non gestire gli errori**:
   ```swift
   // ❌ SBAGLIATO - Test fallisce su qualsiasi errore
   @MainActor
   func testRequest() async throws {
       let server = ProxyServer(port: nextPort(), store: makeStore())
       try await server.start()
   }

   // ✅ GIUSTO - Gestione errori esplicita
   @MainActor
   func testRequest() async throws {
       do {
           let server = ProxyServer(port: nextPort(), store: makeStore())
           try await server.start()
       } catch {
           XCTFail("Start failed: \(error)")
       }
   }
   ```

3. **Stub duplicati nel target di test**:
   Quando si symlinka un nuovo sorgente reale, rimuovere eventuali stub con lo
   stesso nome (es. `BridgeSessionStore`, `ProxyMetrics` erano stub in
   `TestSupport.swift` e ora vengono dai sorgenti reali).

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

