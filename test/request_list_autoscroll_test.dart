import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/providers/exchange_provider.dart';
import 'package:rox_proxy/ui/request_list/request_list_view.dart';

/// Mutable list backing [filteredExchangesProvider] so tests can append
/// exchanges and observe the auto-scroll behaviour.
final _testExchanges = StateProvider<List<CapturedExchange>>((ref) => []);

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
  Future<ProviderContainer> pumpList(
    WidgetTester tester, {
    required bool autoScroll,
  }) async {
    final container = ProviderContainer(
      overrides: [
        filteredExchangesProvider.overrideWith(
          (ref) => ref.watch(_testExchanges),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 200,
              child: RequestListView(autoScroll: autoScroll),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('scrolls to reveal new exchanges when following the bottom', (
    tester,
  ) async {
    final container = await pumpList(tester, autoScroll: true);

    final initial = _range(0, 30);
    container.read(_testExchanges.notifier).state = initial;
    // Select the last (bottom) row: new arrivals should now be followed.
    container.read(selectedExchangeIdProvider.notifier).state = initial.last.id;
    await tester.pumpAndSettle();

    container.read(_testExchanges.notifier).state = [
      ...initial,
      ..._range(30, 35),
    ];
    await tester.pumpAndSettle();

    expect(find.textContaining('q-34'), findsOneWidget);
  });

  testWidgets('does not scroll when auto-scroll is disabled', (tester) async {
    final container = await pumpList(tester, autoScroll: false);

    final initial = _range(0, 30);
    container.read(_testExchanges.notifier).state = initial;
    container.read(selectedExchangeIdProvider.notifier).state = initial.last.id;
    await tester.pumpAndSettle();

    container.read(_testExchanges.notifier).state = [
      ...initial,
      ..._range(30, 35),
    ];
    await tester.pumpAndSettle();

    expect(find.textContaining('q-34'), findsNothing);
  });

  testWidgets('does not scroll when the user is not following the bottom', (
    tester,
  ) async {
    final container = await pumpList(tester, autoScroll: true);

    final initial = _range(0, 30);
    container.read(_testExchanges.notifier).state = initial;
    // Select the first row, so the user is looking at older traffic.
    container.read(selectedExchangeIdProvider.notifier).state =
        initial.first.id;
    await tester.pumpAndSettle();

    container.read(_testExchanges.notifier).state = [
      ...initial,
      ..._range(30, 35),
    ];
    await tester.pumpAndSettle();

    expect(find.textContaining('q-34'), findsNothing);
  });
}
