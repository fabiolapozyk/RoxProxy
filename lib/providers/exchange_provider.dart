import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/captured_exchange.dart';
import '../services/proxy_channel.dart';
import 'proxy_channel_provider.dart';
import 'settings_provider.dart';

// --- Filter text ---
final filterTextProvider = StateProvider<String>((ref) => '');

// --- Selected exchange ID ---
final selectedExchangeIdProvider = StateProvider<String?>((ref) => null);

// --- Exchange list ---
final exchangeListProvider =
    StateNotifierProvider<ExchangeListNotifier, List<CapturedExchange>>((ref) {
      return ExchangeListNotifier(ref);
    });

// --- Filtered exchange list (derived) ---
final filteredExchangesProvider = Provider<List<CapturedExchange>>((ref) {
  final all = ref.watch(exchangeListProvider);
  final filter = ref.watch(filterTextProvider).toLowerCase().trim();
  if (filter.isEmpty) return all;
  return all.where((e) {
    return e.url.toLowerCase().contains(filter) ||
        e.host.toLowerCase().contains(filter) ||
        e.method.toLowerCase().contains(filter);
  }).toList();
});

// --- Selected exchange (derived) ---
final selectedExchangeProvider = Provider<CapturedExchange?>((ref) {
  final id = ref.watch(selectedExchangeIdProvider);
  if (id == null) return null;
  final all = ref.watch(exchangeListProvider);
  try {
    return all.firstWhere((e) => e.id == id);
  } catch (_) {
    return null;
  }
});

class ExchangeListNotifier extends StateNotifier<List<CapturedExchange>> {
  final Ref _ref;
  StreamSubscription? _subscription;

  ExchangeListNotifier(this._ref) : super([]) {
    _subscribe();
  }

  void _subscribe() {
    final channel = _ref.read(proxyChannelProvider);
    _subscription = channel.exchangeStream.listen(_onEvent);
  }

  void _onEvent(ExchangeEvent event) {
    final settings = _ref.read(settingsProvider);
    if (!settings.isRecording && event.type == 'new') return;

    if (event.type == 'new') {
      var list = [...state, event.exchange];
      // Enforce maxExchanges cap
      if (list.length > settings.maxExchanges) {
        list = list.sublist(list.length - settings.maxExchanges);
      }
      state = list;
    } else if (event.type == 'update') {
      final idx = state.indexWhere((e) => e.id == event.exchange.id);
      if (idx == -1) return;
      final updated = state[idx];
      updated.applyUpdate(event.exchange);
      // Trigger rebuild by creating a new list with the same objects
      state = [...state];
    }
  }

  void clear() {
    _ref.read(proxyChannelProvider).releaseAllBodies();
    state = [];
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
