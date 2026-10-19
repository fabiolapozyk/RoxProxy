import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/ui/request_list/request_list_view.dart';

CapturedExchange _exchange(int i) => CapturedExchange(
  id: 'ex-$i',
  startTime: DateTime(2026, 1, 1),
  method: 'GET',
  url: 'https://api.example.com/req-$i',
  scheme: 'https',
  host: 'api.example.com',
  port: 443,
  path: '/req-$i',
  requestHeaders: const [],
  requestSize: 0,
  isHTTPS: true,
  isMITMDecrypted: true,
  state: ExchangeState.completed,
  statusCode: 200,
);

List<CapturedExchange> _range(int start, int end) => [
  for (var i = start; i < end; i++) _exchange(i),
];

void main() {
  late ValueNotifier<List<CapturedExchange>> exchanges;
  late ValueNotifier<String?> selected;

  setUp(() {
    exchanges = ValueNotifier<List<CapturedExchange>>([]);
    selected = ValueNotifier<String?>(null);
  });

  tearDown(() {
    exchanges.dispose();
    selected.dispose();
  });

  Future<void> pumpList(WidgetTester tester, {required bool autoScroll}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 200,
              child: ValueListenableBuilder<List<CapturedExchange>>(
                valueListenable: exchanges,
                builder: (context, list, _) => ValueListenableBuilder<String?>(
                  valueListenable: selected,
                  builder: (context, selectedId, _) => RequestListView(
                    exchanges: list,
                    selectedId: selectedId,
                    onSelect: (id) => selected.value = id,
                    autoScroll: autoScroll,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('scrolls to reveal new exchanges when following the bottom', (
    tester,
  ) async {
    await pumpList(tester, autoScroll: true);

    final initial = _range(0, 30);
    exchanges.value = initial;
    // Select the last (bottom) row: new arrivals should now be followed.
    selected.value = initial.last.id;
    await tester.pumpAndSettle();

    exchanges.value = [...initial, ..._range(30, 35)];
    await tester.pumpAndSettle();

    expect(find.textContaining('q-34'), findsOneWidget);
  });

  testWidgets('does not scroll when auto-scroll is disabled', (tester) async {
    await pumpList(tester, autoScroll: false);

    final initial = _range(0, 30);
    exchanges.value = initial;
    selected.value = initial.last.id;
    await tester.pumpAndSettle();

    exchanges.value = [...initial, ..._range(30, 35)];
    await tester.pumpAndSettle();

    expect(find.textContaining('q-34'), findsNothing);
  });

  testWidgets('does not scroll when the user is not following the bottom', (
    tester,
  ) async {
    await pumpList(tester, autoScroll: true);

    final initial = _range(0, 30);
    exchanges.value = initial;
    // Select the first row, so the user is looking at older traffic.
    selected.value = initial.first.id;
    await tester.pumpAndSettle();

    exchanges.value = [...initial, ..._range(30, 35)];
    await tester.pumpAndSettle();

    expect(find.textContaining('q-34'), findsNothing);
  });
}
