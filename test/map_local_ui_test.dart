import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/providers/map_local_provider.dart';
import 'package:rox_proxy/services/map_local_service.dart';
import 'package:rox_proxy/ui/map_local/map_local_panel.dart';

void main() {
  late Directory tempDir;
  late MapLocalService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('map_local_ui_test');
    service = MapLocalService(overrideDirectory: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapLocalServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(
          home: Scaffold(body: MapLocalRuleManager()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state when no rules exist', (tester) async {
    await pumpPanel(tester);
    expect(find.text('No Map Local rules.\nAdd a rule to start serving local files.'),
        findsOneWidget);
  });

  testWidgets('adds a rule through the dialog', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Name (optional)'), 'Mock users');
    await tester.enterText(
        find.widgetWithText(TextField, 'Path pattern'), '/api/users');
    await tester.enterText(
        find.widgetWithText(TextField, 'Host pattern'), 'api.example.com');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Mock users'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.textContaining('/api/users'), findsWidgets);

    // Persisted to disk
    final loaded = await service.load();
    expect(loaded.single.pathPattern, '/api/users');
  });

  testWidgets('edits an existing rule', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Path pattern'), '/api/old');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Open edit dialog
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final pathField =
        find.widgetWithText(TextField, 'Path pattern');
    expect(tester.widget<TextField>(pathField).controller!.text, '/api/old');

    await tester.enterText(pathField, '/api/new');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/api/new'), findsWidgets);
  });

  testWidgets('deletes a rule', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Path pattern'), '/api/del');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/api/del'), findsWidgets);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('No Map Local rules.\nAdd a rule to start serving local files.'),
        findsOneWidget);
    expect(await service.load(), isEmpty);
  });
}
