import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_rule.dart';
import 'package:rox_proxy/models/domain_rule.dart';
import 'package:rox_proxy/models/map_local_rule.dart';
import 'package:rox_proxy/models/proxy_settings.dart';
import 'package:rox_proxy/models/proxy_state.dart';
import 'package:rox_proxy/providers/breakpoint_rules_provider.dart';
import 'package:rox_proxy/providers/map_local_provider.dart';
import 'package:rox_proxy/providers/proxy_channel_provider.dart';
import 'package:rox_proxy/providers/proxy_control_provider.dart';
import 'package:rox_proxy/services/breakpoint_rules_service.dart';
import 'package:rox_proxy/services/map_local_service.dart';
import 'package:rox_proxy/services/proxy_channel.dart';

/// Records lifecycle calls and tracks how many are in flight at once, so a
/// regression that overlaps stop/start cycles fails the test.
class _FakeProxyChannel extends ProxyChannel {
  final Duration delay;
  int startCalls = 0;
  int stopCalls = 0;
  int updateCalls = 0;
  int _inFlight = 0;
  int maxInFlight = 0;

  _FakeProxyChannel({this.delay = Duration.zero});

  Future<void> _track() async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    await Future<void>.delayed(delay);
    _inFlight--;
  }

  @override
  Future<int> startProxy({
    required int port,
    required List<DomainRule> domainRules,
    required int connectionTimeoutSeconds,
    required bool setSystemProxy,
    required bool httpsInterceptionEnabled,
    List<MapLocalRule> mapLocalRules = const [],
    bool breakpointEnabled = false,
    List<BreakpointRule> breakpointRules = const [],
  }) async {
    startCalls++;
    await _track();
    return port;
  }

  @override
  Future<int> updateProxyConfig({
    required List<DomainRule> domainRules,
    required List<MapLocalRule> mapLocalRules,
    required bool httpsInterceptionEnabled,
    required bool breakpointEnabled,
    required List<BreakpointRule> breakpointRules,
  }) async {
    updateCalls++;
    await _track();
    return updateCalls;
  }

  @override
  Future<void> stopProxy() async {
    stopCalls++;
    await _track();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeProxyChannel channel;
  late ProviderContainer container;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('proxy_control_test');
    channel = _FakeProxyChannel(delay: const Duration(milliseconds: 5));
    container = ProviderContainer(
      overrides: [
        proxyChannelProvider.overrideWithValue(channel),
        mapLocalServiceProvider.overrideWithValue(
          MapLocalService(overrideDirectory: tempDir.path),
        ),
        breakpointRulesServiceProvider.overrideWithValue(
          BreakpointRulesService(overrideDirectory: tempDir.path),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('start then stop transitions the proxy state', () async {
    final notifier = container.read(proxyStateProvider.notifier);
    await notifier.start(ProxySettings());
    expect(container.read(proxyStateProvider), isA<ProxyRunning>());

    await notifier.stop();
    expect(container.read(proxyStateProvider), isA<ProxyStopped>());
  });

  test('rapid restarts never overlap stop/start on the channel', () async {
    final notifier = container.read(proxyStateProvider.notifier);
    final settings = ProxySettings();

    await notifier.start(settings);
    expect(container.read(proxyStateProvider), isA<ProxyRunning>());

    // Simulates several rule edits landing within the same instant.
    await Future.wait([
      notifier.restart(settings),
      notifier.restart(settings),
      notifier.restart(settings),
    ]);

    expect(channel.maxInFlight, 1, reason: 'stop/start must be serialized');
    expect(channel.stopCalls, 3);
    expect(channel.startCalls, 4); // 1 initial start + 3 restarts
    expect(container.read(proxyStateProvider), isA<ProxyRunning>());
  });

  test('a start queued behind a stop still brings the proxy up', () async {
    final notifier = container.read(proxyStateProvider.notifier);
    final settings = ProxySettings();

    await notifier.start(settings);
    // stop() and start() fired back-to-back must not race on the channel.
    await Future.wait([notifier.stop(), notifier.start(settings)]);

    expect(channel.maxInFlight, 1);
    expect(container.read(proxyStateProvider), isA<ProxyRunning>());
  });

  test('config updates are serialized and never restart the proxy', () async {
    final notifier = container.read(proxyStateProvider.notifier);
    final settings = ProxySettings();

    await notifier.start(settings);
    final startsBefore = channel.startCalls;
    final stopsBefore = channel.stopCalls;

    await Future.wait([
      notifier.updateConfig(settings),
      notifier.updateConfig(settings),
      notifier.updateConfig(settings),
    ]);

    expect(channel.updateCalls, 3);
    expect(channel.startCalls, startsBefore);
    expect(channel.stopCalls, stopsBefore);
    expect(channel.maxInFlight, 1, reason: 'updates must be serialized');
    expect(container.read(proxyStateProvider), isA<ProxyRunning>());
  });

  test('updateConfig is a no-op when the proxy is stopped', () async {
    final notifier = container.read(proxyStateProvider.notifier);

    await notifier.updateConfig(ProxySettings());

    expect(channel.updateCalls, 0);
    expect(container.read(proxyStateProvider), isA<ProxyStopped>());
  });
}
