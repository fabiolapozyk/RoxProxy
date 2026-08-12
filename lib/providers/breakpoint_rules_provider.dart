import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/breakpoint_rule.dart';
import '../services/breakpoint_rules_service.dart';

final breakpointRulesServiceProvider = Provider<BreakpointRulesService>((ref) {
  return BreakpointRulesService();
});

/// True once rules have been loaded from disk for the first time.
final breakpointRulesLoadedProvider = StateProvider<bool>((ref) => false);

final breakpointRulesProvider =
    StateNotifierProvider<BreakpointRulesNotifier, List<BreakpointRule>>((ref) {
      return BreakpointRulesNotifier(
        ref.read(breakpointRulesServiceProvider),
        ref,
      );
    });

class BreakpointRulesNotifier extends StateNotifier<List<BreakpointRule>> {
  final BreakpointRulesService _service;
  final Ref _ref;
  Future<void>? _loadFuture;

  BreakpointRulesNotifier(this._service, this._ref) : super(const []) {
    _loadFuture = _load();
  }

  /// Resolves once rules have been loaded from disk (startup race guard).
  Future<void> ensureLoaded() async {
    await _loadFuture;
  }

  Future<void> _load() async {
    state = await _service.load();
    _ref.read(breakpointRulesLoadedProvider.notifier).state = true;
  }

  void _save() => _service.save(state);

  void addRule(BreakpointRule rule) {
    state = [...state, rule];
    _save();
  }

  void updateRule(BreakpointRule rule) {
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
    state = [...state, state[index].duplicate()];
    _save();
  }

  void toggleRule(String id) {
    state = [
      for (final r in state)
        r.id == id ? r.copyWith(isEnabled: !r.isEnabled) : r,
    ];
    _save();
  }

  /// Sostituisce l'intera lista (usato da Import).
  void setRules(List<BreakpointRule> rules) {
    state = List.of(rules);
    _save();
  }
}
