import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/providers/exchange_provider.dart';
import 'package:rox_proxy/providers/map_local_provider.dart';
import 'package:rox_proxy/services/map_local_service.dart';
import 'package:rox_proxy/ui/request_list/request_list_view.dart';

void main() {
  late Directory tempDir;
  late MapLocalService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('request_list_map_local');
    service = MapLocalService(overrideDirectory: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  CapturedExchange completedExchange() => CapturedExchange(
    id: 'ex-1',
    startTime: DateTime.now(),
    method: 'GET',
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
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filteredExchangesProvider.overrideWithValue([completedExchange()]),
          mapLocalServiceProvider.overrideWithValue(service),
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

  testWidgets('context menu offers "Mock with local file"', (tester) async {
    await pumpList(tester);

    // Right-click on the exchange row.
    final rowCenter = tester.getCenter(find.text('api.example.com'));
    await tester.tapAt(rowCenter, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Mock with local file…'), findsOneWidget);
  });

  testWidgets(
    'creating a rule from the context menu prefills host/path/method',
    (tester) async {
      await pumpList(tester);

      // Capture the container before the flow: the notifier is created lazily
      // on first read.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RequestListView)),
      );
      container.read(mapLocalProvider);

      final rowCenter = tester.getCenter(find.text('api.example.com'));
      await tester.tapAt(rowCenter, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mock with local file…'));
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
      // Method dropdown prefilled with GET.
      expect(
        find.descendant(
          of: find.byType(DropdownButtonFormField<String>),
          matching: find.text('GET'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Inline'));
      await tester.tap(find.text('Inline'));
      await tester.pumpAndSettle();
      final bodyField = find.widgetWithText(TextField, 'Response body');
      await tester.ensureVisible(bodyField);
      await tester.enterText(bodyField, '{"ok":true}');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Rule is added to the provider and persisted to disk.
      final rules = container.read(mapLocalProvider);
      expect(rules.length, 1);
      expect(rules.single.hostPattern, 'api.example.com');
      expect(rules.single.pathPattern, '/users');
      expect(rules.single.httpMethod, 'GET');
      expect(rules.single.isInline, isTrue);
      final persisted = await service.load();
      expect(persisted.single.pathPattern, '/users');
      expect(persisted.single.inlineBody, '{"ok":true}');

      // "Rule added" snackbar is shown.
      expect(find.textContaining('Map Local rule added'), findsOneWidget);

      // Let the snackbar timer expire.
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
