import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_rule.dart';
import 'package:rox_proxy/models/proxy_settings.dart';
import 'package:rox_proxy/providers/breakpoint_rules_provider.dart';
import 'package:rox_proxy/providers/settings_provider.dart';
import 'package:rox_proxy/services/breakpoint_rules_service.dart';
import 'package:rox_proxy/services/settings_service.dart';
import 'package:rox_proxy/ui/breakpoint/breakpoint_rules_panel.dart';

/// SettingsService no-op: evita scritture su disco nei test.
class _NoopSettingsService extends SettingsService {
  @override
  Future<ProxySettings> load() async => ProxySettings();

  @override
  Future<void> save(ProxySettings settings) async {}
}

void main() {
  late Directory tempDir;
  late BreakpointRulesService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('breakpoint_rules_ui_test');
    service = BreakpointRulesService(overrideDirectory: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          breakpointRulesServiceProvider.overrideWithValue(service),
          settingsServiceProvider.overrideWithValue(_NoopSettingsService()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BreakpointRulesManager()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state when no rules exist', (tester) async {
    await pumpPanel(tester);
    expect(find.textContaining('No breakpoint rules'), findsOneWidget);
    expect(find.text('Add rule'), findsOneWidget);
    expect(find.text('Breakpoints enabled'), findsOneWidget);
  });

  testWidgets('toggles the global switch', (tester) async {
    await pumpPanel(tester);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    expect(container.read(settingsProvider).breakpointEnabled, isTrue);
  });

  testWidgets('adds a rule through the dialog', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Host pattern'),
      'api.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Path pattern'),
      '/api/**',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('api.example.com'), findsWidgets);
    expect(find.text('1 rule(s)'), findsOneWidget);
  });

  testWidgets('toggles and deletes a rule', (tester) async {
    final container = ProviderContainer(
      overrides: [breakpointRulesServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container
        .read(breakpointRulesProvider.notifier)
        .addRule(
          BreakpointRule(hostPattern: 'h1', target: BreakpointTarget.response),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          breakpointRulesServiceProvider.overrideWithValue(service),
          settingsServiceProvider.overrideWithValue(_NoopSettingsService()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BreakpointRulesManager()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('h1'), findsWidgets);
    expect(find.textContaining('· response'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('0 rule(s)'), findsOneWidget);
  });
}
