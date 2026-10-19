import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/ui/request_list/request_list_view.dart';

CapturedExchange buildExchange() => CapturedExchange(
  id: 'ex-1',
  startTime: DateTime.now(),
  method: 'GET',
  url: 'https://readonly-test.example/path',
  scheme: 'https',
  host: 'readonly-test.example',
  port: 443,
  path: '/path',
  requestHeaders: const [],
  requestSize: 0,
  isHTTPS: true,
  // Not decrypted: makes the "Intercept HTTPS" action available in live mode.
  isMITMDecrypted: false,
  state: ExchangeState.completed,
  statusCode: 200,
);

Future<void> openContextMenu(
  WidgetTester tester, {
  required bool readOnly,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 900,
            child: RequestListView(
              exchanges: [buildExchange()],
              selectedId: null,
              onSelect: (_) {},
              readOnly: readOnly,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tapAt(
    tester.getCenter(find.text('readonly-test.example')),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('read-only list keeps copy actions but hides mutating ones', (
    tester,
  ) async {
    await openContextMenu(tester, readOnly: true);

    expect(find.text('Copy URL'), findsOneWidget);
    expect(find.text('Edit and Replay'), findsNothing);
    expect(find.text('Mock with local file…'), findsNothing);
    expect(find.text('Breakpoint this request…'), findsNothing);
    expect(find.textContaining('Intercept HTTPS for'), findsNothing);
  });

  testWidgets('live list keeps the mutating actions', (tester) async {
    await openContextMenu(tester, readOnly: false);

    expect(find.textContaining('Intercept HTTPS for'), findsOneWidget);
    expect(find.text('Edit and Replay'), findsOneWidget);
    expect(find.text('Mock with local file…'), findsOneWidget);
    expect(find.text('Breakpoint this request…'), findsOneWidget);
  });
}
