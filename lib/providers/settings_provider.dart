import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/domain_rule.dart';
import '../models/proxy_settings.dart';
import '../services/settings_service.dart';
import 'proxy_channel_provider.dart';
import 'proxy_control_provider.dart';

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

/// True once settings have been loaded from disk for the first time.
final settingsLoadedProvider = StateProvider<bool>((ref) => false);

final settingsProvider = StateNotifierProvider<SettingsNotifier, ProxySettings>(
  (ref) {
    return SettingsNotifier(ref.read(settingsServiceProvider), ref);
  },
);

class SettingsNotifier extends StateNotifier<ProxySettings> {
  final SettingsService _service;
  final Ref _ref;

  SettingsNotifier(this._service, this._ref) : super(ProxySettings()) {
    _load();
  }

  Future<void> _load() async {
    final loaded = await _service.load();
    // isRecording has no UI toggle anymore; always start in recording mode.
    state = loaded.copyWith(isRecording: true);
    _ref.read(settingsLoadedProvider.notifier).state = true;
  }

  Future<void> _save() => _service.save(state);

  void setPort(int port) {
    state = state.copyWith(port: port);
    _save();
  }

  void setAutoStartProxy(bool value) {
    state = state.copyWith(autoStartProxy: value);
    _save();
  }

  void setIsRecording(bool value) {
    state = state.copyWith(isRecording: value);
    _save();
  }

  void setMaxExchanges(int value) {
    state = state.copyWith(maxExchanges: value);
    _save();
  }

  void setConnectionTimeout(int seconds) {
    state = state.copyWith(connectionTimeoutSeconds: seconds);
    _save();
  }

  void setHttpsInterceptionEnabled(bool value) {
    state = state.copyWith(httpsInterceptionEnabled: value);
    _save();
  }

  void setBreakpointEnabled(bool value) {
    state = state.copyWith(breakpointEnabled: value);
    _save();
  }

  void setSetSystemProxy(bool value) {
    state = state.copyWith(setSystemProxy: value);
    _save();
    // Apply immediately if the proxy is currently running.
    if (_ref.read(proxyStateProvider).isRunning) {
      _ref
          .read(proxyChannelProvider)
          .configureSystemProxy(enabled: value, port: state.port);
    }
  }

  void addDomain(String domain) {
    final trimmed = domain.trim();
    if (trimmed.isEmpty) return;
    if (state.domainRules.any((r) => r.domain == trimmed)) return;
    state = state.copyWith(
      domainRules: [
        ...state.domainRules,
        DomainRule(domain: trimmed),
      ],
    );
    _save();
  }

  void removeDomain(String id) {
    state = state.copyWith(
      domainRules: state.domainRules.where((r) => r.id != id).toList(),
    );
    _save();
  }

  void toggleDomain(String id) {
    state = state.copyWith(
      domainRules: state.domainRules
          .map(
            (r) => r.id == id
                ? DomainRule(
                    id: r.id,
                    domain: r.domain,
                    isEnabled: !r.isEnabled,
                  )
                : r,
          )
          .toList(),
    );
    _save();
  }
}
