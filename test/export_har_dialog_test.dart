import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/providers/har_export_provider.dart';
import 'package:rox_proxy/ui/export_har_dialog.dart';

class _Result {
  HarExportScope? value;
  bool completed = false;
}

Future<_Result> _open(
  WidgetTester tester, {
  required int total,
  required int filtered,
  required bool filterActive,
}) async {
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result.value = await showHarExportDialog(
                context,
                total: total,
                filtered: filtered,
                filterActive: filterActive,
              );
              result.completed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('defaults to filtered when a filter is active', (tester) async {
    final result = await _open(
      tester,
      total: 10,
      filtered: 3,
      filterActive: true,
    );

    expect(find.text('3 of 10 (filter active)'), findsOneWidget);
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();

    expect(result.completed, isTrue);
    expect(result.value, HarExportScope.filtered);
  });

  testWidgets('defaults to all when no filter is active', (tester) async {
    final result = await _open(
      tester,
      total: 10,
      filtered: 10,
      filterActive: false,
    );

    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();

    expect(result.value, HarExportScope.all);
  });

  testWidgets('lets the user switch to all calls', (tester) async {
    final result = await _open(
      tester,
      total: 10,
      filtered: 3,
      filterActive: true,
    );

    await tester.tap(find.text('All calls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();

    expect(result.value, HarExportScope.all);
  });

  testWidgets('cancel returns null', (tester) async {
    final result = await _open(
      tester,
      total: 10,
      filtered: 3,
      filterActive: true,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result.completed, isTrue);
    expect(result.value, isNull);
  });

  testWidgets('export is disabled when there is nothing to export', (
    tester,
  ) async {
    await _open(tester, total: 0, filtered: 0, filterActive: false);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
