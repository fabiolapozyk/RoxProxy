import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/providers/exchange_provider.dart';
import 'package:rox_proxy/ui/request_list/request_list_view.dart';

CapturedExchange exchangeWithPath(String path) => CapturedExchange(
  id: 'ex-1',
  startTime: DateTime.now(),
  method: 'GET',
  url: 'https://api.example.com$path',
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

Future<void> pumpList(
  WidgetTester tester,
  CapturedExchange exchange, {
  double width = 520,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        filteredExchangesProvider.overrideWithValue([exchange]),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: width, height: 900, child: RequestListView()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('path shorter than the column is shown in full', (tester) async {
    await pumpList(tester, exchangeWithPath('/users'), width: 600);

    expect(find.text('/users'), findsOneWidget);
  });

  testWidgets('long path keeps the trailing part with a leading ellipsis', (
    tester,
  ) async {
    const path =
        '/api/v2/documents/dossier/2026/consolidated/report/export/chiamata.json';
    await pumpList(tester, exchangeWithPath(path), width: 600);

    final visible = find.textContaining('.json');
    expect(visible, findsOneWidget);

    final text = tester.widget<Text>(visible);
    expect(text.data, startsWith('…'));
    expect(path.endsWith(text.data!.substring(1)), isTrue);
  });

  testWidgets('GET path shows the query string stripped', (tester) async {
    await pumpList(
      tester,
      exchangeWithPath('/users?id=1&page=2&lang=it'),
      width: 600,
    );

    expect(find.text('/users'), findsOneWidget);
    expect(find.textContaining('?'), findsNothing);
  });

  testWidgets('non-GET path keeps the query string', (tester) async {
    final exchange = exchangeWithPath('/search?q=hello');
    exchange.method = 'POST';
    await pumpList(tester, exchange, width: 900);

    expect(find.textContaining('?q=hello'), findsOneWidget);
  });

  testWidgets('trailing end is never cut off at the ellipsis boundary', (
    tester,
  ) async {
    const path = '/svc/shreddit/user-drawer-button-logged-in';
    await pumpList(tester, exchangeWithPath(path));

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((d) => d.contains('…'))
        .toList();
    expect(texts, isNotEmpty);
    for (final t in texts) {
      expect(path.endsWith(t.substring(1)), isTrue);
    }
  });
}
