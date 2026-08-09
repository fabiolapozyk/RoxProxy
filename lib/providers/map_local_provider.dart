import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/map_local_rule.dart';
import '../services/map_local_service.dart';

final mapLocalServiceProvider = Provider<MapLocalService>((ref) {
  return MapLocalService();
});

/// True once rules have been loaded from disk for the first time.
final mapLocalLoadedProvider = StateProvider<bool>((ref) => false);

final mapLocalProvider =
    StateNotifierProvider<MapLocalNotifier, List<MapLocalRule>>((ref) {
  return MapLocalNotifier(ref.read(mapLocalServiceProvider), ref);
});

class MapLocalNotifier extends StateNotifier<List<MapLocalRule>> {
  final MapLocalService _service;
  final Ref _ref;
  Future<void>? _loadFuture;

  MapLocalNotifier(this._service, this._ref) : super(const []) {
    _loadFuture = _load();
  }

  /// Resolves once rules have been loaded from disk (startup race guard).
  Future<void> ensureLoaded() async {
    await _loadFuture;
  }

  Future<void> _load() async {
    state = await _service.load();
    _ref.read(mapLocalLoadedProvider.notifier).state = true;
  }

  void _save() => _service.save(state);

  void addRule(MapLocalRule rule) {
    state = [...state, rule];
    _save();
  }

  void updateRule(MapLocalRule rule) {
    state = [for (final r in state) r.id == rule.id ? rule : r];
    _save();
  }

  void removeRule(String id) {
    state = state.where((r) => r.id != id).toList();
    _save();
  }

  void duplicateRule(String id) {
    final index = state.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final copy = state[index].duplicate();
    state = [...state, copy];
    _save();
  }

  void toggleRule(String id) {
    state = [
      for (final r in state) r.id == id ? r.copyWith(isEnabled: !r.isEnabled) : r,
    ];
    _save();
  }

  /// Reorders rules (drag & drop) — list position determines priority.
  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final rules = [...state];
    final moved = rules.removeAt(oldIndex);
    rules.insert(newIndex, moved);
    state = rules;
    _save();
  }

  /// Replaces the whole list (used by Import).
  void setRules(List<MapLocalRule> rules) {
    state = List.of(rules);
    _save();
  }
}
