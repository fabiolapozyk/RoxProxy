import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/ui/settings/settings_view.dart';

void main() {
  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 760, height: 560, child: SettingsView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sidebar shows all sections', (tester) async {
    await pumpSettings(tester);
    for (final label in ['General', 'HTTPS Domains', 'Certificate', 'Map Local']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('starts on General and switches sections', (tester) async {
    await pumpSettings(tester);

    // General is selected by default (its content is present).
    expect(find.text('Map Local rules'), findsNothing);

    // Switch to Map Local.
    await tester.tap(find.text('Map Local'));
    await tester.pumpAndSettle();
    expect(find.text('Add rule'), findsOneWidget);
    expect(
      find.textContaining('Requests matching a rule are answered'),
      findsOneWidget,
    );

    // Switch to HTTPS Domains.
    await tester.tap(find.text('HTTPS Domains'));
    await tester.pumpAndSettle();
    expect(find.text('example.com or *.example.com'), findsOneWidget);
    expect(find.text('Add rule'), findsNothing);
  });
}
