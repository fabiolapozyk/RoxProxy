# Changelog

Tutte le modifiche rilevanti a RoxProxy sono documentate in questo file.

Il formato segue [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
e il progetto usa [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Workflow di release: tag `v*` -> build + DMG + draft release (`.github/workflows/release.yml`)
- Roadmap pubblica su issue (`label: roadmap`): rewrite rules (#9), export HAR (#10)

## [0.5.0] - 2026-10-25

### Added

- Hot reload della configurazione: modificare regole di dominio, Map Local o breakpoint non riavvia più il proxy
- Snapshot immutabile per richiesta: le nuove richieste usano la configurazione aggiornata, mentre quelle in corso e i tunnel già aperti mantengono la versione con cui sono partiti
- Disattivando i breakpoint, le richieste sospese vengono rilasciate subito e i relativi dialog si chiudono
- Metodo di canale `updateProxyConfig` con validazione strict e risposta `{success, version}`

### Changed

- L'HTTPS interception si applica ai nuovi `CONNECT` senza riavvio
- I contatori di `/stats` non vengono più azzerati a ogni modifica di configurazione
- I testi dell'interfaccia indicano "applies to new requests" per le modifiche a caldo
- Il dialog Map Local valida la regex prima del salvataggio

### Fixed

- La VPN FortiClient non si scollega più quando si aggiunge, modifica o attiva/disattiva una regola Map Local, un breakpoint o una regola di dominio
- Il proxy non viene più fermato e riavviato (con disattivazione temporanea del proxy di sistema) a ogni modifica di configurazione

### Known Issues

- Cambiare porta o connection timeout richiede ancora un riavvio del proxy e può interrompere una VPN attiva

## [0.1.0] - 2026-08-13

### Added

- Breakpoint request/response con editing prima dell'inoltro (#8)
- Copia della response nel menu' contestuale e apertura body in editor esterno (#6, #7)
- Map Local: risposte locali per pattern URL
- Replay di richieste catturate
- Endpoint interni `GET /health` e `GET /stats`
- Infrastruttura test: CoreTests (SPM), `verify.sh`, `smoke.sh`, CI GitHub Actions (#3)
- Logging con `os_log` (subsystem `com.roxproxy`) per debug assistito da LLM
- Metriche proxy (`ProxyMetrics`)
- Crash recovery: ripristino proxy di sistema su uscita non pulita (sentinel + signal handler)

[Unreleased]: https://github.com/flapozyk/RoxProxy/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/flapozyk/RoxProxy/releases/tag/v0.5.0
[0.1.0]: https://github.com/flapozyk/RoxProxy/releases/tag/v0.1.0
