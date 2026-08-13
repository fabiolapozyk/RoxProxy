# Changelog

Tutte le modifiche rilevanti a RoxProxy sono documentate in questo file.

Il formato segue [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
e il progetto usa [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Workflow di release: tag `v*` -> build + DMG + draft release (`.github/workflows/release.yml`)
- Roadmap pubblica su issue (`label: roadmap`): rewrite rules (#9), export HAR (#10)

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

[Unreleased]: https://github.com/flapozyk/RoxProxy/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/flapozyk/RoxProxy/releases/tag/v0.1.0
