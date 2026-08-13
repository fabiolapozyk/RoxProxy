---
name: supervisione
description: "Usare PRIMA di modifiche a API pubbliche (channel bridge), architettura Swift/Dart, protocolli di rete, schema persistenza, e PRIMA del commit. Delega review e decisioni al subagent manager (ds4-pro)."
---

# Supervisione con manager

Il modello esecutore (ds4 flash) NON prende decisioni importanti: le sottopone al subagent `manager` (ds4-pro).

## Quando attivarla

- Modifiche a: bridge Flutter<->Swift (`packages/rox_proxy_native/.../Bridge/`), handler proxy (`Proxy/`, `MapLocal/`, `Breakpoint/`), modelli serializzati (`Models/`), schema file in `~/Library/Application Support/RoxProxy/`.
- Prima del commit di feature non banali.

## Procedura

1. Delegare al subagent `manager` con il tool Task: riassunto del task, file modificati, diff rilevante (`git diff`), rischi identificati, test previsti.
2. `manager` risponde con: approvazione, richiesta modifiche o indicazione di alternative.
3. Implementare SOLO dopo approvazione. In caso di richiesta modifiche, applicare e ri-sottoporre.
4. Prima del commit finale, ri-sottoporre il diff completo per review finale.

Il manager ha permessi di sola lettura: non esegue modifiche.
