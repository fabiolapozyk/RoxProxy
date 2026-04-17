import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/breakpoint_rule.dart';
import '../services/settings_service.dart';
import '../services/proxy_channel.dart';
import 'proxy_channel_provider.dart';
import 'settings_provider.dart';

final breakpointServiceProvider = Provider<BreakpointService>((ref) {
  return BreakpointService(ref.read(settingsServiceProvider));
});

final breakpointProvider = 
    StateNotifierProvider<BreakpointNotifier, List<BreakpointRule>>((ref) {
  return BreakpointNotifier(
    ref.read(breakpointServiceProvider),
    ref.read(proxyChannelProvider),
  );
});

class BreakpointService {
  final SettingsService _settingsService;
  static const _storageKey = 'breakpointRules';

  BreakpointService(this._settingsService);

  Future<List<BreakpointRule>> load() async {
    final data = await _settingsService.getValue(_storageKey);
    if (data == null) return [];
    
    try {
      final list = data as List<dynamic>;
      return list
          .map((e) => BreakpointRule.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> save(List<BreakpointRule> rules) async {
    await _settingsService.setValue(
      _storageKey,
      rules.map((r) => r.toMap()).toList(),
    );
  }
}

class BreakpointNotifier extends StateNotifier<List<BreakpointRule>> {
  final BreakpointService _service;
  final ProxyChannel _proxyChannel;

  BreakpointNotifier(this._service, this._proxyChannel) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _service.load();
    _syncWithNative();
  }

  Future<void> _save() async {
    await _service.save(state);
    _syncWithNative();
  }

  Future<void> _syncWithNative() async {
    try {
      await _proxyChannel.setBreakpointRules(state);
    } catch (e) {
      // Native layer might not be ready yet
    }
  }

  void addRule(BreakpointRule rule) {
    state = [...state, rule];
    _save();
  }

  void removeRule(String id) {
    state = state.where((r) => r.id != id).toList();
    _save();
  }

  void updateRule(BreakpointRule updatedRule) {
    state = state.map((r) => r.id == updatedRule.id ? updatedRule : r).toList();
    _save();
  }

  void toggleRule(String id) {
    state = state.map((r) => 
      r.id == id ? r.copyWith(isEnabled: !r.isEnabled) : r
    ).toList();
    _save();
  }
}