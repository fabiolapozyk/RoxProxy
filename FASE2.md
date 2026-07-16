# Fase 2: Ulteriore Semplificazione

Questo file contiene i prossimi passi pianificati per la semplificazione dell'architettura.

## 🎯 Obiettivi Fase 2

### 1. Sostituire Riverpod con Provider
**Motivazione:** Provider è più leggero e sufficiente per questo caso d'uso
**Dipendenze da rimuovere:**
- `flutter_riverpod: ^2.6.1`
- `riverpod_annotation: ^2.6.1`
- `riverpod_generator: ^2.6.5` (dev_dependency)

**Dipendenza da aggiungere:**
- `provider: ^6.1.5`

**Sforzo stimato:** 1-2 giorni
**Risparmio:** 3 dipendenze

---

## 📋 Passi Dettagliati

### Passo 1: Aggiungere Provider
```yaml
# pubspec.yaml
dependencies:
  provider: ^6.1.5
```

### Passo 2: Convertire i Provider Riverpod

#### `proxyChannelProvider`
**Da:**
```dart
final proxyChannelProvider = Provider<ProxyChannel>((ref) {
  return ProxyChannel();
});
```

**A:**
```dart
final proxyChannelProvider = Provider<ProxyChannel>((_) {
  return ProxyChannel();
});
```

#### `settingsProvider` (StateNotifierProvider)
**Da:**
```dart
final settingsProvider = StateNotifierProvider<SettingsNotifier, ProxySettings>((ref) {
  return SettingsNotifier();
});
```

**A:**
```dart
final settingsProvider = ChangeNotifierProvider<SettingsNotifier>((_) {
  return SettingsNotifier();
});
```

Nota: Dovrà essere modificato `SettingsNotifier` per estendere `ChangeNotifier` invece di `StateNotifier`.

#### `proxyStateProvider` (StateNotifierProvider)
**Da:**
```dart
final proxyStateProvider = StateNotifierProvider<ProxyStateNotifier, ProxyState>((ref) {
  return ProxyStateNotifier(ref.read(proxyChannelProvider));
});
```

**A:**
```dart
final proxyStateProvider = ChangeNotifierProvider<ProxyStateNotifier>((_) {
  return ProxyStateNotifier();
});
```

#### `exchangeListProvider` (StateNotifierProvider)
**Da:**
```dart
final exchangeListProvider = StateNotifierProvider<ExchangeListNotifier, List<CapturedExchange>>((ref) {
  return ExchangeListNotifier();
});
```

**A:**
```dart
final exchangeListProvider = ChangeNotifierProvider<ExchangeListNotifier>((_) {
  return ExchangeListNotifier();
});
```

#### `caTrustProvider` (StateNotifierProvider)
**Da:**
```dart
final caTrustProvider = StateNotifierProvider<CATrustNotifier, bool>((ref) {
  return CATrustNotifier();
});
```

**A:**
```dart
final caTrustProvider = ChangeNotifierProvider<CATrustNotifier>((_) {
  return CATrustNotifier();
});
```

#### `filteredExchangesProvider` (derived)
**Da:**
```dart
final filteredExchangesProvider = Provider<List<CapturedExchange>>((ref) {
  final filter = ref.watch(filterTextProvider);
  final exchanges = ref.watch(exchangeListProvider);
  // ...
});
```

**A:**
```dart
final filteredExchangesProvider = Provider<List<CapturedExchange>>((ref) {
  final filter = ref.watch(filterTextProvider);
  final exchanges = ref.watch(exchangeListProvider);
  // ...
});
```
Nota: I Provider derivati possono essere convertiti in `Provider` o `SelectorProvider`.

#### `selectedExchangeProvider` (derived)
**Da:**
```dart
final selectedExchangeProvider = Provider<CapturedExchange?>((ref) {
  final list = ref.watch(filteredExchangesProvider);
  final index = ref.watch(selectedIndexProvider);
  // ...
});
```

**A:**
```dart
final selectedExchangeProvider = Provider<CapturedExchange?>((ref) {
  final list = ref.watch(filteredExchangesProvider);
  final index = ref.watch(selectedIndexProvider);
  // ...
});
```

---

### Passo 3: Aggiornare i Notifier

Tutti i `StateNotifier` devono essere convertiti in `ChangeNotifier`:

**Da:**
```dart
class SettingsNotifier extends StateNotifier<ProxySettings> {
  SettingsNotifier() : super(ProxySettings());
  
  void updateSettings(ProxySettings newSettings) {
    state = newSettings;
  }
}
```

**A:**
```dart
class SettingsNotifier extends ChangeNotifier {
  ProxySettings _settings = ProxySettings();
  ProxySettings get settings => _settings;
  
  void updateSettings(ProxySettings newSettings) {
    _settings = newSettings;
    notifyListeners();
  }
}
```

---

### Passo 4: Aggiornare i Consumer

**Da:**
```dart
Consumer(
  builder: (context, ref, child) {
    final settings = ref.watch(settingsProvider);
    // ...
  },
)
```

**A:**
```dart
Consumer<SettingsNotifier>(
  builder: (context, notifier, child) {
    final settings = notifier.settings;
    // ...
  },
)
```

Oppure usando `Selector` per ottimizzazione:

```dart
Selector<SettingsNotifier, ProxySettings>(
  selector: (_, notifier) => notifier.settings,
  builder: (context, settings, child) {
    // ...
  },
)
```

---

### Passo 5: Rimuovere Code Generation

Rimuovere tutti i file generati da Riverpod:
- Rimuovere `*.g.dart` file
- Rimuovere `riverpod_generator` da dev_dependencies
- Rimuovere `build_runner` se non usato per altro

---

## 🎯 Benefici Attesi

1. **Meno dipendenze:** -3
2. **Codice più semplice:** Provider ha meno concetti (nessun ref, watch, read)
3. **Meno code generation:** Non servono più i file .g.dart
4. **Maggiore compatibilità:** Provider è più maturo e ampiamente usato

---

## ⚠️ Rischi e Considerazioni

1. **StateNotifier vs ChangeNotifier:**
   - StateNotifier offre `state` immutable
   - ChangeNotifier richiede gestione manuale dello stato
   - Per questo progetto, ChangeNotifier è sufficiente

2. **Ref vs Context:**
   - Riverpod usa `ref` per accedere ad altri provider
   - Provider usa `Provider.of<T>(context, listen: false)`
   - Attenzione a non usare context across async gaps

3. **Test:**
   - I test con Riverpod usano `Container`
   - I test con Provider usano `ProviderScope`
   - Dovranno essere aggiornati

---

## 📚 Risorse Utili

- [Provider Documentation](https://docs.flutter.dev/development/data-and-backend/state-mgmt/simple)
- [Riverpod to Provider Migration Guide](https://riverpod.dev/docs/migration/from_provider_to_riverpod/) (inverso, ma utile)
- [Flutter State Management Comparison](https://docs.flutter.dev/development/data-and-backend/state-mgmt/options)

---

## ✅ Checklist Completamento

- [ ] Aggiunto `provider: ^6.1.5` a pubspec.yaml
- [ ] Rimosso `flutter_riverpod`, `riverpod_annotation` da dependencies
- [ ] Rimosso `riverpod_generator` da dev_dependencies
- [ ] Convertito tutti i StateNotifier in ChangeNotifier
- [ ] Aggiornati tutti i Provider definizioni
- [ ] Aggiornati tutti i Consumer nel codice
- [ ] Aggiornati/creati i test per Provider
- [ ] Verificato che tutto compili
- [ ] Verificato che tutti i test passino
- [ ] Aggiornata documentazione (MISTRAL.md, TESTING.md)
