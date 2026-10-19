import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proxy_state.dart';
import '../models/proxy_settings.dart';
import 'breakpoint_rules_provider.dart';
import 'map_local_provider.dart';
import 'proxy_channel_provider.dart';

final proxyStateProvider =
    StateNotifierProvider<ProxyStateNotifier, ProxyState>((ref) {
      return ProxyStateNotifier(ref);
    });

class ProxyStateNotifier extends StateNotifier<ProxyState> {
  final Ref _ref;

  /// Tail of the serialized lifecycle-operation chain (start/stop/restart).
  Future<void> _operations = Future.value();

  ProxyStateNotifier(this._ref) : super(const ProxyStopped());

  /// Runs [task] once every previously enqueued lifecycle operation has
  /// finished, so rapid stop/start/restart calls (e.g. several rule edits in a
  /// row) cannot overlap on the method channel.
  Future<void> _serialize(Future<void> Function() task) {
    final next = _operations.then<void>((_) => task()).catchError((
      Object error,
    ) {
      // Backstop only: _start/_doStop already surface errors via state.
      debugPrint('Proxy lifecycle operation failed: $error');
    });
    _operations = next;
    return next;
  }

  Future<void> start(ProxySettings settings) =>
      _serialize(() => _start(settings));

  Future<void> stop() => _serialize(_doStop);

  /// Stops (if running) and starts the proxy with [settings], to apply
  /// configuration changes without a manual stop/start.
  Future<void> restart(ProxySettings settings) => _serialize(() async {
    await _doStop();
    await _start(settings);
  });

  Future<void> _start(ProxySettings settings) async {
    if (state.isRunning) return;
    state = const ProxyStarting();
    try {
      final channel = _ref.read(proxyChannelProvider);
      // Wait for Map Local rules to finish loading from disk, otherwise an
      // empty list is sent to the native proxy on a fast startup/auto-start.
      await _ref.read(mapLocalProvider.notifier).ensureLoaded();
      await _ref.read(breakpointRulesProvider.notifier).ensureLoaded();
      final mapLocalRules = _ref.read(mapLocalProvider);
      final breakpointRules = _ref.read(breakpointRulesProvider);
      final port = await channel.startProxy(
        port: settings.port,
        domainRules: settings.domainRules,
        mapLocalRules: mapLocalRules,
        connectionTimeoutSeconds: settings.connectionTimeoutSeconds,
        setSystemProxy: settings.setSystemProxy,
        httpsInterceptionEnabled: settings.httpsInterceptionEnabled,
        breakpointEnabled: settings.breakpointEnabled,
        breakpointRules: breakpointRules,
      );
      state = ProxyRunning(port);
    } catch (e) {
      state = ProxyError(e.toString());
    }
  }

  Future<void> _doStop() async {
    if (!state.isRunning) return;
    try {
      await _ref.read(proxyChannelProvider).stopProxy();
    } catch (_) {}
    state = const ProxyStopped();
  }
}
