import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rox_proxy/models/map_local_rule.dart';
import 'package:rox_proxy/providers/map_local_provider.dart';
import 'package:rox_proxy/services/map_local_service.dart';

void main() {
  late Directory tempDir;
  late MapLocalService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('map_local_provider_test');
    service = MapLocalService(overrideDirectory: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [mapLocalServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> waitForLoad(ProviderContainer container) async {
    // Instantiates the notifier (its constructor triggers the async load).
    container.read(mapLocalProvider);
    var tries = 0;
    while (!container.read(mapLocalLoadedProvider) && tries < 1000) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      tries++;
    }
    expect(
      container.read(mapLocalLoadedProvider),
      isTrue,
      reason: 'provider should finish loading',
    );
  }

  test('loads empty rules by default', () async {
    final container = makeContainer();
    await waitForLoad(container);
    expect(container.read(mapLocalProvider), isEmpty);
  });

  test('add/update/toggle/remove/duplicate/reorder', () async {
    final container = makeContainer();
    await waitForLoad(container);
    final notifier = container.read(mapLocalProvider.notifier);

    final a = MapLocalRule(name: 'A', pathPattern: '/api/a');
    final b = MapLocalRule(name: 'B', pathPattern: '/api/b');
    notifier.addRule(a);
    notifier.addRule(b);
    expect(container.read(mapLocalProvider).length, 2);

    // Update
    notifier.updateRule(a.copyWith(statusCode: 404));
    expect(container.read(mapLocalProvider).first.statusCode, 404);

    // Toggle
    notifier.toggleRule(a.id);
    expect(container.read(mapLocalProvider).first.isEnabled, isFalse);

    // Duplicate
    notifier.duplicateRule(b.id);
    expect(container.read(mapLocalProvider).length, 3);
    final copy = container.read(mapLocalProvider).last;
    expect(copy.id, isNot(b.id));
    expect(copy.name, 'B (copy)');

    // Remove
    notifier.removeRule(a.id);
    expect(container.read(mapLocalProvider).length, 2);

    // Reorder: move first rule (b) after the second (copy)
    notifier.reorder(0, 2);
    final rules = container.read(mapLocalProvider);
    expect(rules.first.id, copy.id);
    expect(rules.last.id, b.id);
  });

  test('changes are persisted to disk', () async {
    final container = makeContainer();
    await waitForLoad(container);
    container
        .read(mapLocalProvider.notifier)
        .addRule(MapLocalRule(pathPattern: '/persisted'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final reloaded = await service.load();
    expect(reloaded.single.pathPattern, '/persisted');
  });

  test('setRules replaces the whole list (import)', () async {
    final container = makeContainer();
    await waitForLoad(container);
    container.read(mapLocalProvider.notifier).setRules([
      MapLocalRule(pathPattern: '/x'),
      MapLocalRule(pathPattern: '/y'),
    ]);
    expect(container.read(mapLocalProvider).length, 2);
  });
}
