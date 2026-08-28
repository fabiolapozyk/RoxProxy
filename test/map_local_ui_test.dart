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
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapLocalServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: Scaffold(body: MapLocalRuleManager())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state when no rules exist', (tester) async {
    await pumpPanel(tester);
    expect(
      find.text(
        'No Map Local rules.\nAdd a rule to start serving local files.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('adds a rule through the dialog', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Name (optional)'),
      'Mock users',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Path pattern'),
      '/api/users',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Host pattern'),
      'api.example.com',
    );
    await tester.ensureVisible(find.text('Inline'));
    await tester.tap(find.text('Inline'));
    await tester.pumpAndSettle();
    final bodyField = find.widgetWithText(TextField, 'Response body');
    await tester.ensureVisible(bodyField);
    await tester.enterText(bodyField, '{"ok":true}');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Mock users'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.textContaining('/api/users'), findsWidgets);

    // Persisted to disk as an inline rule.
    final loaded = await service.load();
    expect(loaded.single.pathPattern, '/api/users');
    expect(loaded.single.isInline, isTrue);
    expect(loaded.single.inlineBody, '{"ok":true}');
  });

  testWidgets('adds a file rule through the dialog', (tester) async {
    final tempFile = File('${tempDir.path}/response.json');
    tempFile.writeAsStringSync('{"ok":true}');
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Path pattern'),
      '/api/file',
    );
    final fileField = find.widgetWithText(TextField, 'Local response file');
    await tester.ensureVisible(fileField);
    await tester.enterText(fileField, tempFile.path);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/api/file'), findsWidgets);
    final loaded = await service.load();
    expect(loaded.single.isInline, isFalse);
    expect(loaded.single.filePath, tempFile.path);
  });

  testWidgets('Save is disabled without a file or an inline body', (
    tester,
  ) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

    // File mode: no path selected.
    expect(saveButton().onPressed, isNull);

    // Inline mode: empty body.
    await tester.ensureVisible(find.text('Inline'));
    await tester.tap(find.text('Inline'));
    await tester.pumpAndSettle();
    expect(saveButton().onPressed, isNull);

    // Typing a body enables Save.
    final bodyField = find.widgetWithText(TextField, 'Response body');
    await tester.ensureVisible(bodyField);
    await tester.enterText(bodyField, '{}');
    await tester.pumpAndSettle();
    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets('edits an existing rule', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Path pattern'),
      '/api/old',
    );
    await tester.ensureVisible(find.text('Inline'));
    await tester.tap(find.text('Inline'));
    await tester.pumpAndSettle();
    final bodyField = find.widgetWithText(TextField, 'Response body');
    await tester.ensureVisible(bodyField);
    await tester.enterText(bodyField, '{}');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Open edit dialog
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final pathField = find.widgetWithText(TextField, 'Path pattern');
    expect(tester.widget<TextField>(pathField).controller!.text, '/api/old');

    await tester.enterText(pathField, '/api/new');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/api/new'), findsWidgets);
  });

  testWidgets('switching source resets the other source fields', (
    tester,
  ) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Path pattern'),
      '/api/switch',
    );
    await tester.ensureVisible(find.text('Inline'));
    await tester.tap(find.text('Inline'));
    await tester.pumpAndSettle();
    final bodyField = find.widgetWithText(TextField, 'Response body');
    await tester.ensureVisible(bodyField);
    await tester.enterText(bodyField, '{"inline":true}');
    await tester.pumpAndSettle();

    // Back to file mode: body must be dropped and file path kept empty.
    await tester.ensureVisible(find.text('File'));
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    final saveDisabled = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
        .onPressed;
    expect(saveDisabled, isNull);

    // Back to inline: body is still there.
    await tester.ensureVisible(find.text('Inline'));
    await tester.tap(find.text('Inline'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Response body'))
          .controller!
          .text,
      '{"inline":true}',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final loaded = await service.load();
    expect(loaded.single.isInline, isTrue);
    expect(loaded.single.filePath, '');
    expect(loaded.single.inlineBody, '{"inline":true}');
  });

  testWidgets('deletes a rule', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Path pattern'),
      '/api/del',
    );
    await tester.ensureVisible(find.text('Inline'));
    await tester.tap(find.text('Inline'));
    await tester.pumpAndSettle();
    final bodyField = find.widgetWithText(TextField, 'Response body');
    await tester.ensureVisible(bodyField);
    await tester.enterText(bodyField, '{}');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/api/del'), findsWidgets);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No Map Local rules.\nAdd a rule to start serving local files.',
      ),
      findsOneWidget,
    );
    expect(await service.load(), isEmpty);
  });
}
