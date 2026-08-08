import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proxy_state.dart';
import '../models/proxy_settings.dart';
import 'map_local_provider.dart';
import 'proxy_channel_provider.dart';

final proxyStateProvider =
    StateNotifierProvider<ProxyStateNotifier, ProxyState>((ref) {
  return ProxyStateNotifier(ref);
});

class ProxyStateNotifier extends StateNotifier<ProxyState> {
  final Ref _ref;

  ProxyStateNotifier(this._ref) : super(const ProxyStopped());

  Future<void> start(ProxySettings settings) async {
    if (state.isRunning) return;
    state = const ProxyStarting();
    try {
      final channel = _ref.read(proxyChannelProvider);
      final port = await channel.startProxy(
        port: settings.port,
        domainRules: settings.domainRules,
        mapLocalRules: _ref.read(mapLocalProvider),
        connectionTimeoutSeconds: settings.connectionTimeoutSeconds,
        setSystemProxy: settings.setSystemProxy,
        httpsInterceptionEnabled: settings.httpsInterceptionEnabled,
      );
      state = ProxyRunning(port);
    } catch (e) {
      state = ProxyError(e.toString());
    }
  }

  Future<void> stop() async {
    if (!state.isRunning) return;
    try {
      await _ref.read(proxyChannelProvider).stopProxy();
    } catch (_) {}
    state = const ProxyStopped();
  }
}
