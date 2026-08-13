---
name: debug-visivo
description: "Usare quando il debug coinvolge l'aspetto visivo dell'app Flutter: bug UI, layout, rendering, screenshot, confronto atteso-vs-reale, issue visuali. Delega l'analisi al subagent vision (mimo-v2.5)."
---

# Debug visivo

Per bug/verifiche che richiedono vista (layout Flutter, rendering, screenshot, difformita' visive):

1. Raccogliere il materiale: screenshot dell'app (scattato dall'utente o da test), descrizione del comportamento atteso, file Dart coinvolti in `lib/ui/`.
2. Delegare l'analisi al subagent `vision` (modello visivo mimo-v2.5) con il tool Task: passare i percorsi file assoluti degli screenshot e dei sorgenti coinvolti, descrizione del problema, comportamento atteso.
3. Chiedere a `vision` di restituire: diagnosi puntuale (widget/riga), fix proposto.
4. Applicare il fix con il modello esecutore (ds4 flash), poi rieseguire i test: `flutter test test/` e `flutter analyze`.

Non modificare codice basandosi solo su ipotesi visive senza il responso di `vision`.
