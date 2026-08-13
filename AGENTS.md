# AGENTS.md — RoxProxy

Guida per l'assistente di coding (opencode) che lavora su questo repository.

## Comandi di verifica

Dopo OGNI modifica al codice, eseguire la verifica prima di dichiarare il lavoro finito.

```bash
# Verifica completa (format + analyze + unit test + swift test + build debug)
./scripts/verify.sh

# Verifica rapida (salta build debug, ~1-2 min)
./scripts/verify.sh --fast

# Smoke test end-to-end (build release, launch app, /health, /stats, richiesta HTTP reale, clean shutdown)
./scripts/smoke.sh
./scripts/smoke.sh --skip-build   # riusa l'ultima build release
```

Il CI (`.github/workflows/ci.yml`) esegue lo stesso percorso di `verify.sh` su push/PR:
format → analyze → `flutter test test/` → `swift test` (CoreTests) → `flutter build macos --debug`.

## Workflow standard

1. Esplorare i file coinvolti prima di modificare.
2. Dopo ogni task: `./scripts/verify.sh --fast` (se i test unitari Dart sono lenti, basta
   `dart format` + `flutter analyze` + `swift test`).
3. Se si tocca il core Swift del proxy (Proxy/, Certificate/, Models/, Bridge/, MapLocal/):
   aggiornare/aggiungere i test in `packages/rox_proxy_native/macos/CoreTests/Tests/CoreTests/`
   e lanciare `swift test` lì.
4. Non committare senza verifiche passate.

## Ruoli agentici (modelli)

Tre modelli con ruoli fissi (config in `opencode.json`):

- **Esecutore** (default, ds4 flash): scrive codice, fix, test. Non prende decisioni importanti.
- **Manager** (subagent `manager`, ds4 pro): review, decisioni architetturali, escalation.
  Attivare tramite skill `supervisione` prima di: modifiche a Bridge/Models/handler proxy,
  prima del commit di feature non banali.
- **Oracolo visivo** (subagent `vision`, mimo-v2.5): bug UI/rendering/screenshot.
  Attivare tramite skill `debug-visivo`.

Regola: l'esecutore delega, il manager decide, il vision vede.

## Architettura (mappa rapida)

```
lib/                          # UI Flutter/Dart (Riverpod)
packages/rox_proxy_native/
  macos/rox_proxy_native/Sources/rox_proxy_native/
    Proxy/                    # SwiftNIO: HTTPProxyHandler, MITMHandler, TunnelHandler, ProxyServer
    Certificate/              # CertificateAuthority, DomainCertificateCache, KeychainInstaller
    Bridge/                   # Channel bridge Flutter <-> Swift (BridgeSessionStore, ExchangeSerializer)
    Models/                   # CapturedExchange, DomainRule, ProxySettings, MapLocalRule
    MapLocal/                 # MapLocalMatcher, MapLocalHandler
    SystemProxy/              # SystemProxyManager, CrashGuard
    Utilities/                # ProxyLogger (os_log, subsystem "com.roxproxy"), ProxyMetrics, GzipDecompressor
  macos/CoreTests/            # Package SPM standalone: test del core Swift puro
                             # (symlink dei sorgenti; NON si può testare via swift test il plugin
                             # completo perché RoxProxyNativePlugin importa FlutterMacOS)
integration_test/             # E2E (richiedono rete, eseguibili solo localmente)
test/                         # Unit test Dart
```

## Note critiche

- **Non eseguire `swift build`/`swift test` nella dir del plugin** (`packages/rox_proxy_native/macos/rox_proxy_native`):
  fallisce con "no such module 'FlutterMacOS'" (il modulo dipende da FlutterMacOS, disponibile solo in Xcode).
  Per il core Swift: `cd packages/rox_proxy_native/macos/CoreTests && swift test`.
- Il check di compilazione completo del plugin avviene tramite `flutter build macos --debug`.
- Log dell'app: `log show --predicate 'subsystem == "com.roxproxy"' --last 1h` oppure `log stream`.
- CrashGuard usa il sentinel `~/Library/Application Support/RoxProxy/.proxy-active`:
  se presente dopo un clean exit, il path di shutdown è rotto (lo verifica `smoke.sh`).
- Endpoint interni del proxy: `GET /health` e `GET /stats` (porta del proxy).
- Regole Map Local e settings in `~/Library/Application Support/RoxProxy/` (JSON).
- `scripts/release_script.sh` è gitignored (release manuali); `verify.sh`/`smoke.sh` sono versionati.
