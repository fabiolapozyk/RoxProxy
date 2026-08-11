# Requisito: Breakpoint su richieste HTTP/HTTPS

Stato: da implementare
Modello di riferimento: funzionalità Map Local (architettura core Swift + plugin Flutter + test)

## 1. Contesto e obiettivo

Il proxy intercetta già tutto il traffico HTTP/HTTPS (MITM per i domini configurati) e lo mostra in streaming nella UI. L'obiettivo è permettere all'utente di **sospendere una richiesta in transito**, ispezionarla, **modificarne metodo/URL/header/body** e decidere se inviarla al server oppure annullarla, con risposta interattiva in tempo reale.

Perimetro prima versione: **solo breakpoint sulle richieste (request)**, non sulle risposte.

## 2. Terminologia

- **Exchange**: singola transazione HTTP catturata (modello già esistente `CapturedExchange`).
- **Breakpoint**: sospensione di una richiesta in attesa di una decisione dell'utente.
- **Proceed**: inoltro al server della richiesta (originale o modificata).
- **Cancel**: annullamento della richiesta con risposta `400 Bad Request` al client.
- **Timeout**: mancata risposta dell'utente entro N secondi, quindi auto-Proceed con richiesta originale.

## 3. Requisiti funzionali

### RF1 — Attivazione e condizioni
- RF1.1 Il breakpoint è una funzionalità **attivabile/disattivabile** dall'utente.
- RF1.2 A funzionalità disattiva: overhead di latenza trascurabile e nessuna sospensione del traffico.
- RF1.3 Le condizioni di scatto sono centralizzate in un unico punto del core Swift (`shouldBreakpointRequest()`), configurate via codice nella prima versione (es. tutte le richieste, solo `POST`, match su host/path). Nessuna condizione configurabile da UI in v1 (vedi §10).

### RF2 — Sospensione della richiesta
- RF2.1 Il core Swift deve sospendere la richiesta in ingresso **senza bloccare l'event loop NIO** e senza impattare le altre connessioni.
- RF2.2 Il client resta in attesa finché l'utente non decide o scatta il timeout.
- RF2.3 I dati notificati all'utente includono: id breakpoint, id exchange, metodo, URL, header, body, timestamp.

### RF3 — Notifica alla UI e decisione
- RF3.1 Il core notifica la UI con il dettaglio della richiesta sospesa.
- RF3.2 La UI risponde con una delle azioni: **Proceed** (con eventuali modifiche), **Cancel** (abort 400), nessuna risposta (gestita dal timeout lato core).
- RF3.3 Se la UI non è disponibile (nessun listener sul canale di notifica), le richieste non devono mai rimanere bloccate: comportamento di default = inoltro immediato (degradazione graziosa).

### RF4 — Modifica della richiesta
- RF4.1 L'utente può modificare: metodo HTTP, URL, header (aggiunta/rimozione/modifica), body testuale.
- RF4.2 Il core applica le modifiche prima dell'inoltro al server.
- RF4.3 Limitazione v1: su richieste HTTPS intercettate (MITM) il cambio di host può non essere applicabile; documentare il comportamento senza rompere l'exchange.

### RF5 — Timeout
- RF5.1 Timeout di default **30 secondi**, configurabile nel core (costante).
- RF5.2 Allo scadere: auto-Proceed con la richiesta **originale** e log dell'evento.
- RF5.3 Il timeout deve essere cancellato alla ricezione della decisione (nessuna risorsa orfana sull'event loop).

### RF6 — Canale di comunicazione (bridge esistente)
- RF6.1 Notifica core → UI su **EventChannel dedicato** (`com.roxproxy/breakpointEvents`), stesso pattern di `com.roxproxy/exchanges` (`ExchangeStreamHandler`).
- RF6.2 Decisione UI → core sul **MethodChannel esistente** (`com.roxproxy/control`), nuovo metodo `breakpointDecision`, correlata per id breakpoint.
- RF6.3 Payload JSON (dizionari standard Flutter) con id correlatore (v. §7). Nessuna porta di rete, nessun protocollo di trasporto nuovo.
- RF6.4 Disponibilità UI = **sink EventChannel attivo**; sink assente ⇒ comportamento di default (auto-Proceed, RF3.3).

### RF7 — Integrazione UI
- RF7.1 Dialog dedicato mostrato automaticamente a ogni richiesta sospesa (una alla volta; eventuali richieste in parallelo accodate).
- RF7.2 Azioni chiare nel dialog: **Proceed** e **Cancel**; durante l'attesa l'utente vede il tempo residuo del timeout.
- RF7.3 Gli exchange oggetto di breakpoint compaiono nella lista richieste con marcatura (es. flag `isBreakpoint`) e stato coerente (sospeso → completato/annullato).
- RF7.4 Stato della funzionalità (attiva/disattiva) visibile nella UI.

## 4. Requisiti non funzionali

### RNF1 — Performance
- Latenza aggiuntiva solo sulle richieste che scattano il breakpoint.
- Nessun blocco dell'event loop: attese su promise/future, body e file gestiti fuori dal loop.
- Body grandi: notificare solo un prefisso (riuso soglia `BodyContent.maxInMemorySize`), senza tenere in memoria l'intera richiesta.

### RNF2 — Affidabilità
- Timeout di sicurezza su ogni punto di attesa (mai richieste bloccate per sempre).
- Il core non si fida dello stato della UI: sink assente, decisione non arrivata entro il timeout o errore di canale ⇒ auto-Proceed (nessuna riconnessione da gestire, il bridge è in-process).
- Shutdown pulito: a `stopProxy`, tutte le richieste sospese vengono rilasciate con Proceed.

### RNF3 — Concorrenza
- Più richieste sospese in parallelo gestite in modo thread-safe (pattern già usati da `RegexCache` e `BridgeSessionStore`).

### RNF4 — Sicurezza (boundary esplicito)
- **Nessun nuovo accesso di rete**: i canali sono in-process (messenger Flutter, stesso processo app). Il proxy non apre porte aggiuntive oltre quella HTTP; la porta del proxy resta l'unica superficie di rete.
- Chiamanti autorizzati: core Swift e plugin Flutter (stesso processo app). Nessun processo esterno può raggiungere i canali.
- Niente body, URL o payload delle richieste sospese in chiaro nei log (`ProxyLogger`): log solo eventi di alto livello (RNF5).

### RNF5 — Logging
- Log applicativo solo su eventi di alto livello (breakpoint creato, azione ricevuta, timeout), senza payload sensibili.

## 5. Architettura proposta (modello Map Local)

### Core Swift — `packages/rox_proxy_native/macos/rox_proxy_native/Sources/rox_proxy_native/`

| File | Ruolo |
|---|---|
| `Models/BreakpointRequest.swift` | Modello richiesta notificata alla UI (id, exchangeId, metodo, URL, headers, body, timestamp) |
| `Models/BreakpointResponse.swift` | Modello decisione utente (breakpointId, azione proceed/cancel, modifiche) |
| `Breakpoint/BreakpointMatcher.swift` | Condizioni di scatto, incapsula `shouldBreakpointRequest()` (analogo `MapLocalMatcher`) |
| `Breakpoint/BreakpointHandler.swift` | Sospensione, attesa decisione, timeout, applicazione modifiche, cancel 400 (analogo `MapLocalHandler`) |
| `Bridge/BreakpointStreamHandler.swift` | Nuovo EventChannel `com.roxproxy/breakpointEvents` per le notifiche (modello `ExchangeStreamHandler`) |
| `Proxy/HTTPProxyHandler.swift` | Hook: valutazione breakpoint, pausa richiesta, apply modifiche (modificato) |
| `Bridge/ProxyMethodHandler.swift` | Nuovo metodo `breakpointDecision` sul MethodChannel `control` (modificato) |

### Plugin Flutter — `lib/`

| File | Ruolo |
|---|---|
| `models/breakpoint_request.dart` | Modello Dart notifica (fromJson) |
| `models/breakpoint_response.dart` | Modello Dart decisione (toJson) |
| `services/breakpoint_service.dart` | Client dei canali: stream EventChannel notifiche + invio decisioni su MethodChannel (nessuna connessione da gestire) |
| `providers/breakpoint_provider.dart` | Riverpod: lifecycle del service, stream delle richieste sospese, azioni |
| `ui/breakpoint/breakpoint_dialog.dart` | Dialog di modifica: metodo, URL, header (add/remove), body, Proceed/Cancel |
| `ui/main_window.dart` | Listener del provider + apertura automatica del dialog (modificato) |
| `models/captured_exchange.dart` | Aggiunta flag `isBreakpoint` (modificato) |

### Test

| Area | File | Cosa copre |
|---|---|---|
| Swift core | `CoreTests/Tests/CoreTests/BreakpointTests.swift` | Matching condizioni, modello request/response, timeout, apply modifiche, cancel 400, rilascio a stop (tutto puro NIO, testabile senza FlutterMacOS) |
| Dart | `test/breakpoint_request_test.dart` `test/breakpoint_response_test.dart` | Serializzazione JSON |
| Dart | `test/breakpoint_service_test.dart` | Client dei canali con mock del binary messenger: stream notifiche, invio decisioni |
| Dart | `test/breakpoint_provider_test.dart` | Stato, coda richieste, azioni proceed/cancel |
| Dart | `test/breakpoint_dialog_test.dart` | UI: modifica campi, add/remove header, azioni |

## 6. Flusso di interazione

1. **Utente attiva** i breakpoint (impostazione UI → `startProxy` con flag).
2. **Richiesta in transito**: `HTTPProxyHandler` valuta `shouldBreakpointRequest()`; se scatta, sospende la richiesta e notifica via EventChannel.
3. **Dialog**: la UI mostra i dettagli; l'utente modifica e sceglie.
4. **Proceed** → il core applica le modifiche e inoltra al server; l'exchange prosegue normalmente.
5. **Cancel** → risposta `400 Bad Request` al client; exchange marcato annullato.
6. **Timeout 30s** (o sink non attivo) → inoltro immediato della richiesta originale.
7. A `stopProxy` → tutte le sospese vengono rilasciate con Proceed.

## 7. Protocollo messaggi (JSON)

Notifica (core → UI):

```json
{
  "id": "uuid",
  "exchangeId": "uuid",
  "type": "request",
  "method": "GET",
  "url": "https://example.com",
  "headers": {"Content-Type": "application/json"},
  "body": "...",
  "timestamp": "2026-08-10T10:00:00Z"
}
```

Decisione (UI → core):

```json
{
  "breakpointId": "uuid",
  "action": "proceed",
  "modifiedMethod": "POST",
  "modifiedUrl": "https://example.com/api",
  "modifiedHeaders": {"Authorization": "Bearer token"},
  "modifiedBody": "...",
  "timestamp": "2026-08-10T10:00:05Z"
}
```

Nessun handshake di rete: notifica e decisione viaggiano sui canali in-process, correlate per id breakpoint (RF6.3).

## 8. Criteri di accettazione

1. Breakpoint attivo: una richiesta matching viene sospesa e il dialog compare in < 1s.
2. Modifica di metodo/URL/header/body applicata alla richiesta inviata al server (verificabile con server di test che rispecchia la richiesta).
3. Cancel produce `400 Bad Request` al client e l'exchange risulta annullato.
4. Nessuna azione per 30s: la richiesta parte comunque, originale, con log di timeout.
5. WS down (client non connesso): le richieste non vengono mai bloccate.
6. `stopProxy` con sospese in attesa: tutte rilasciate, nessuna hang.
7. Richieste parallele: dialog accodati senza corruzione di stato.
8. Con breakpoint disattivo, nessuna differenza di comportamento rispetto a oggi (regressione su `smoke.sh`).
9. Nessuna porta di rete aggiuntiva aperta dal proxy (i canali sono in-process); con sink EventChannel non attivo le richieste non vengono bloccate (RF3.3).
10. `./scripts/verify.sh` verde; test Swift core + Dart nuovi inclusi.

## 9. Rischi e decisioni aperte

- **Bridge esistente vs WebSocket**: l'unico client è l'app Flutter (single-process), quindi si riusa il bridge: notifica su EventChannel dedicato + decisione sul MethodChannel `control`, zero superficie di rete (RNF4). Niente WS in v1; migrazione totale su WS non pianificata, rivalutabile solo se emergesse un client non-Flutter (CLI/remoto).
- **Latenza notifica**: la notifica passa dal main thread (come già per gli exchange); main occupato ⇒ consegna ritardata, mitigata dal timeout 30s (mai blocco definitivo).
- **Modifica host su richieste HTTPS MITM**: limitazione documentata, non bloccante per v1.
- **Body binario/large**: v1 solo body testuale e troncato; upload binari fuori scope.
- **Coda dialog**: con burst di richieste la coda può crescere; il timeout evita stalli.

## 10. Fuori scope (versioni successive)

- Breakpoint su risposte (response).
- Regole/condizioni configurabili da UI.
- Storico breakpoint e modifiche.
- Scripting (JS/Python) per modifiche automatiche.
- Body binari e grandi.

## 11. Dipendenze previste

### Swift
- Nessuna dipendenza nuova: `FlutterEventChannel`/`FlutterMethodChannel` già integrati nel plugin.

### Flutter
- Nessuna dipendenza nuova: riuso di `EventChannel`/`MethodChannel` nativi.
- `json_serializable`/`build_runner` (solo se si adotta il pattern generato; i modelli Map Local usano `fromJson/toJson` manuali, quindi possibile evitarli).
