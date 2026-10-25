# Changelog

## 0.5.0 - 2026-10-25

### Added

- `ProxyConfig` immutabile, `ProxyConfigStore` thread-safe con swap atomico e
  versione monotona, `ProxyConfigParser` condiviso con validazione strict.
- Metodo di canale `updateProxyConfig`: applica domain rules, Map Local,
  breakpoint e HTTPS interception senza fermare il server.
- Snapshot di configurazione per richiesta: le nuove richieste usano la config
  aggiornata, quelle in-flight e i tunnel già aperti mantengono la loro.
- Evento `resolved` sui breakpoint: il disable rilascia le richieste sospese e
  chiude i dialog.

### Changed

- `BreakpointHandler` non possiede più il matcher; il controllo di abilitazione
  avviene sotto lock, eliminando i pending orfani in caso di disable concorrente.
- `/stats` non viene più azzerato dalle modifiche di configurazione.
- Restart-only: porta e connection timeout.

### Fixed

- La chiusura del listener (e quindi la caduta di una VPN instradata dal proxy)
  non avviene più a ogni modifica di regole, Map Local o breakpoint.

## 0.0.1

- Initial release.
