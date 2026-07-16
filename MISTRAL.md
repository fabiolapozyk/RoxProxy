# MISTRAL.md

Guida per Mistral Vibe per lo sviluppo di Rox Proxy.

## 🚀 Commands

```bash
# Build Flutter app
flutter build macos

# Run debug
flutter run -d macos

# Test Dart
flutter test

# Test Swift
cd packages/rox_proxy_native && swift test

# Run specific Swift test
swift test Tests.RoxProxyTests --filter HTTPProxyHandlerTests

# View logs (os_log)
log show --predicate 'subsystem == "com.roxproxy"' --last 1h
log stream --predicate 'subsystem == "com.roxproxy"'
```

## 🏗️ Architecture

**Principi base:**
1. **Minimalismo**: Meno dipendenze = meno problemi
2. **Sicurezza prima**: Non compromettere la sicurezza per semplificare
3. **Separazione chiara**: UI (Flutter) ↔ Business Logic (Swift)
4. **Os_log per tutto**: Logging nativo macOS, visibile in Console.app

**Project Layout:**
```
lib/                          # Flutter UI + State (Riverpod)
  utils/
    uuid.dart                 # Custom UUID v4 generator
    path_utils.dart           # Application Support directory
  services/                   # ProxyChannel (Flutter ↔ Swift)
  providers/                  # Riverpod-based state management
  models/                     # Data models
  ui/                         # Widgets

packages/rox_proxy_native/    # Swift Plugin
  Sources/rox_proxy_native/
    Bridge/                   # Flutter ↔ Swift communication
    Proxy/                    # SwiftNIO handlers (HTTP, HTTPS, Tunnel, MITM)
    Certificate/              # CA generation, domain certs, Keychain
    SystemProxy/              # networksetup, crash recovery
    Models/                   # Swift-side data models
    Utilities/                # ProxyLogger (os_log), GzipDecompressor
```

## 📡 Platform Channels

| Channel | Direction | Methods |
|---------|-----------|---------|
| `com.roxproxy/control` | Flutter → Swift | `startProxy`, `stopProxy`, `getProxyState`, `installCACertificate`, `checkCATrust`, `getCAStatus`, `fetchBody`, `releaseBody`, `releaseAllBodies`, `decompressBody` |
| `com.roxproxy/exchanges` | Swift → Flutter | Stream events: `{type: "new"|"update", exchange: {...}}` |

## 🔧 Request Flow (Swift)

1. **ProxyServer** - SwiftNIO `ServerBootstrap` su `0.0.0.0:port`
2. **HTTPProxyHandler** - Gestisce richieste HTTP plain
3. **CONNECT** - Tunnel blind o MITM interception (se dominio in regole)
4. **MITMHandler** - TLS decryption con certificato forgiato
5. **BridgeSessionStore** - Riceve callbacks da thread NIO, invia eventi a Flutter

## 📦 Body Transfer

Bodies **non** inlined negli eventi:
- Swift: memorizza `Data` in `BodyStore` (key = UUID)
- Event: contiene `requestBodyRef`/`responseBodyRef`
- Dart: chiama `fetchBody(ref)` lazy quando l'utente apre lo scambio

## 🛡️ Security

- App Sandbox **disabilitato** (necessario per TCP binding, networksetup, Keychain)
- CA self-signed P-256 generato al primo avvio
- Certificati per dominio generati on-demand e cachati
- `KeychainInstaller` installa CA nel System Keychain

## 💡 Development Guidelines

### Aggiungere nuove feature:

1. **Swift side**:
   - Aggiungi handler/logica in `packages/rox_proxy_native/Sources/...`
   - Aggiungi metodo in `ProxyMethodHandler` se serve esposizione a Flutter
   - Aggiungi categoria di log in `ProxyLogger.swift`

2. **Flutter side**:
   - Aggiungi metodo in `ProxyChannel`
   - Aggiungi Provider se serve state
   - Aggiungi widget in `lib/ui/`

3. **Testing**:
   - Swift: unit test con `TestHarness` (vedi TESTING.md)
   - Flutter: E2E test in `integration_test/`

### Debugging:

```bash
# Log in tempo reale
log stream --predicate 'subsystem == "com.roxproxy"'

# Log degli ultimi 5 minuti
log show --predicate 'subsystem == "com.roxproxy"' --last 5m

# Filtra per categoria
log show --predicate 'subsystem == "com.roxproxy" AND category == "tls"'

# Livello di dettaglio
log show --predicate 'subsystem == "com.roxproxy"' --info --debug
```

### Code Style:

- **Swift**: Segui Apple Swift API Design Guidelines
- **Dart**: Segui Flutter style guide
- **Naming**: `camelCase` per variabili, `PascalCase` per classi
- **Logging**: Usa **sempre** `ProxyLogger.category.level("messaggio")`
- **Error handling**: Logga **sempre** gli errori con `.error`

### Dipendenze:

**Regole generali:**
- Evitare nuove dipendenze esterne se esiste una soluzione semplice
- Preferire implementazioni custom per funzionalita banali (UUID, path, ecc.)
- Per la sicurezza (certificati, TLS), usare librerie Apple ufficiali

**Dipendenze attuali approvate:**
- **Flutter**: `flutter_riverpod`, `riverpod_annotation` (fase 2: sostituire con Provider)
- **Swift**: `swift-nio`, `swift-nio-ssl`, `swift-certificates`, `swift-asn1`, `swift-crypto`

## 🔄 Refactoring Checklist

Prima di fare refactoring:
- [ ] Tutti i test passano (`swift test` + `flutter test integration_test/`)
- [ ] Nuove dipendenze sono strettamente necessarie
- [ ] Il codice e piu semplice, non piu complesso
- [ ] La documentazione e aggiornata