---
name: issue-triage
description: "Usare quando si lavora a partire da una issue GitHub (triage, stima, piano). L'utente cita issue di RoxProxy (flapozyk/RoxProxy). Produce un piano con test previsti prima di scrivere codice."
---

# Triage issue GitHub

Trasformare una issue di `flapozyk/RoxProxy` in piano eseguibile.

## Procedura

1. Leggere la issue: `gh issue view <numero>` (inclusi commenti con `gh issue view <numero> --comments`).
2. Se l'issue e' vaga o ambigua, chiedere chiarimenti all'utente invece di assumere.
3. Esplorare i file coinvolti. Per issue Swift: `packages/rox_proxy_native/macos/rox_proxy_native/Sources/`. Per issue UI: `lib/ui/`.
4. Produrre piano con: causa ipotizzata, file da toccare, test da aggiungere (CoreTests per Swift, `test/` per Dart), comandi di verifica (`./scripts/verify.sh --fast`).
5. Se il task e' non banale, sottoporre il piano al subagent `manager` (skill `supervisione`) prima di implementare.

## Conclusione

A fix verificato (`verify.sh` passato): proporre messaggio di commit e menzionare la issue (`#N`). Non chiudere la issue senza conferma dell'utente.
