import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/providers/breakpoint_rules_provider.dart';
import 'package:rox_proxy/providers/exchange_provider.dart';
import 'package:rox_proxy/services/breakpoint_rules_service.dart';
import 'package:rox_proxy/ui/request_list/request_list_view.dart';

void main() {
  late Directory tempDir;
  late BreakpointRulesService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('request_list_breakpoint');
    service = BreakpointRulesService(overrideDirectory: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  CapturedExchange completedExchange() => CapturedExchange(
    id: 'ex-1',
    startTime: DateTime.now(),
    method: 'POST',
    url: 'https://api.example.com/users?id=1',
    scheme: 'https',
    host: 'api.example.com',
    port: 443,
    path: '/users?id=1',
    requestHeaders: const [],
    requestSize: 0,
    isHTTPS: true,
    isMITMDecrypted: true,
    state: ExchangeState.completed,
    statusCode: 200,
  );

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filteredExchangesProvider.overrideWithValue([completedExchange()]),
          breakpointRulesServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 520, height: 900, child: RequestListView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('context menu offers "Breakpoint this request"', (tester) async {
    await pumpList(tester);

    final rowCenter = tester.getCenter(find.text('api.example.com'));
    await tester.tapAt(rowCenter, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Breakpoint this request…'), findsOneWidget);
  });

  testWidgets('marks request breakpoints with the green output icon', (
    tester,
  ) async {
    final exchange = completedExchange()..isBreakpoint = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filteredExchangesProvider.overrideWithValue([exchange]),
          breakpointRulesServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 520, height: 900, child: RequestListView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Suspended at request breakpoint'), findsOneWidget);
    expect(find.byIcon(Icons.output), findsOneWidget);
    expect(find.byTooltip('Suspended at response breakpoint'), findsNothing);
  });

  testWidgets('marks response breakpoints with the red input icon', (
    tester,
  ) async {
    final exchange = completedExchange()
      ..isBreakpoint = true
      ..isResponseBreakpoint = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filteredExchangesProvider.overrideWithValue([exchange]),
          breakpointRulesServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 520, height: 900, child: RequestListView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Suspended at response breakpoint'), findsOneWidget);
    expect(find.byIcon(Icons.input), findsOneWidget);
    expect(find.byTooltip('Suspended at request breakpoint'), findsNothing);
  });

  testWidgets(
    'creating a breakpoint from the context menu prefills host/path/method',
    (tester) async {
      await pumpList(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(RequestListView)),
      );
      container.read(breakpointRulesProvider);

      final rowCenter = tester.getCenter(find.text('api.example.com'));
      await tester.tapAt(rowCenter, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Breakpoint this request…'));
      await tester.pumpAndSettle();

      // Prefilled with the exchange data (query string stripped from path).
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Host pattern'))
            .controller!
            .text,
        'api.example.com',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Path pattern'))
            .controller!
            .text,
        '/users',
      );
      expect(
        find.descendant(
          of: find.byType(DropdownButtonFormField<String>),
          matching: find.text('POST'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Rule is added to the provider and persisted to disk.
      final rules = container.read(breakpointRulesProvider);
      expect(rules.length, 1);
      expect(rules.single.hostPattern, 'api.example.com');
      expect(rules.single.pathPattern, '/users');
      expect(rules.single.httpMethod, 'POST');
      final persisted = await service.load();
      expect(persisted.single.pathPattern, '/users');

      // "Rule added" snackbar is shown.
      expect(find.textContaining('Breakpoint rule added'), findsOneWidget);

      // Let the snackbar timer expire.
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
