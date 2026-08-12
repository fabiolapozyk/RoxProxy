import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_rule.dart';
import 'package:rox_proxy/providers/breakpoint_rules_provider.dart';
import 'package:rox_proxy/services/breakpoint_rules_service.dart';

void main() {
  late Directory tempDir;
  late BreakpointRulesService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('breakpoint_rules_test');
    service = BreakpointRulesService(overrideDirectory: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('add/update/toggle/remove rules with persistence', () async {
    final container = ProviderContainer(
      overrides: [breakpointRulesServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(breakpointRulesProvider.notifier);
    await notifier.ensureLoaded();

    final rule = BreakpointRule(
      hostPattern: 'api.example.com',
      pathPattern: '/api/**',
      httpMethod: 'POST',
      target: BreakpointTarget.both,
    );
    notifier.addRule(rule);
    expect(container.read(breakpointRulesProvider).length, 1);

    notifier.toggleRule(rule.id);
    expect(container.read(breakpointRulesProvider).single.isEnabled, isFalse);

    final updated = rule.copyWith(hostPattern: 'other.com', isEnabled: true);
    notifier.updateRule(updated);
    expect(
      container.read(breakpointRulesProvider).single.hostPattern,
      'other.com',
    );
    expect(container.read(breakpointRulesProvider).single.isEnabled, isTrue);

    notifier.removeRule(rule.id);
    expect(container.read(breakpointRulesProvider), isEmpty);
  });

  test('rules survive provider recreation (persisted on disk)', () async {
    final first = ProviderContainer(
      overrides: [breakpointRulesServiceProvider.overrideWithValue(service)],
    );
    await first.read(breakpointRulesProvider.notifier).ensureLoaded();
    first
        .read(breakpointRulesProvider.notifier)
        .addRule(BreakpointRule(hostPattern: 'h1'));
    first.dispose();

    final second = ProviderContainer(
      overrides: [breakpointRulesServiceProvider.overrideWithValue(service)],
    );
    addTearDown(second.dispose);
    await second.read(breakpointRulesProvider.notifier).ensureLoaded();

    expect(second.read(breakpointRulesProvider).length, 1);
    expect(second.read(breakpointRulesProvider).single.hostPattern, 'h1');
  });

  test('empty file yields no rules', () async {
    final container = ProviderContainer(
      overrides: [breakpointRulesServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    await container.read(breakpointRulesProvider.notifier).ensureLoaded();
    expect(container.read(breakpointRulesProvider), isEmpty);
  });
}
