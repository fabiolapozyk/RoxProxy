import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/ui/detail/detail_view.dart';
import 'package:rox_proxy/ui/detail/query_params_tab.dart';

CapturedExchange _exchange({
  required String method,
  required String url,
  String path = '/api',
}) => CapturedExchange(
  id: 'ex-1',
  startTime: DateTime(2026, 1, 1),
  method: method,
  url: url,
  scheme: 'https',
  host: 'api.example.com',
  port: 443,
  path: path,
  requestHeaders: const [],
  requestSize: 0,
  isHTTPS: true,
  isMITMDecrypted: true,
  state: ExchangeState.completed,
  statusCode: 200,
);

Future<void> _pumpDetail(WidgetTester tester, CapturedExchange exchange) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DetailView(exchange: exchange)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('QueryParamsTab', () {
    testWidgets('lists name/value pairs in order', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueryParamsTab(
              url: 'https://api.example.com/users?id=42&lang=it',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('id'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('lang'), findsOneWidget);
      expect(find.text('it'), findsOneWidget);
    });

    testWidgets('shows a placeholder when there are no parameters', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueryParamsTab(url: 'https://api.example.com/users'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No query parameters'), findsOneWidget);
    });
  });

  group('DetailView request tabs', () {
    testWidgets('GET shows a Query tab instead of Body', (tester) async {
      await _pumpDetail(
        tester,
        _exchange(
          method: 'GET',
          url: 'https://api.example.com/users?id=42',
          path: '/users?id=42',
        ),
      );

      expect(find.text('Query'), findsOneWidget);

      await tester.tap(find.text('Query'));
      await tester.pumpAndSettle();
      expect(find.text('id'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('POST keeps the Body tab and has no Query tab', (tester) async {
      await _pumpDetail(
        tester,
        _exchange(method: 'POST', url: 'https://api.example.com/users'),
      );

      expect(find.text('Query'), findsNothing);
      expect(find.text('Body'), findsOneWidget);
    });
  });
}
