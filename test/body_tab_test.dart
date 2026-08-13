import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/ui/detail/body_tab.dart';

CapturedExchange _exchangeWithJsonBody(String body) {
  final exchange = CapturedExchange(
    id: 'ex-1',
    startTime: DateTime(2026, 1, 1),
    method: 'POST',
    url: 'http://example.com/api',
    scheme: 'http',
    host: 'example.com',
    port: 80,
    path: '/api',
    requestHeaders: const [HttpHeader('Content-Type', 'application/json')],
    requestBodyRef: 'body-ref-1',
    requestSize: body.length,
    isHTTPS: false,
    isMITMDecrypted: false,
  );
  exchange.setCachedRequestBody(Uint8List.fromList(utf8.encode(body)));
  return exchange;
}

Map<String, int> _largePayload() {
  final payload = <String, int>{};
  for (var i = 0; i < 2500; i++) {
    payload['k$i'] = i;
  }
  return payload;
}

Future<List<MethodCall>> _pumpBodyTab(
  WidgetTester tester,
  CapturedExchange exchange,
) async {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call);
      return null;
    },
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: BodyTab.request(exchange: exchange)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return calls;
}

Future<void> _sendShortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
}

List<MethodCall> _setDataCalls(List<MethodCall> calls) =>
    calls.where((c) => c.method == 'Clipboard.setData').toList();

TextStyle? _firstLineStyle(WidgetTester tester) {
  final richText = tester.widget<RichText>(
    find
        .descendant(of: find.byType(ListView), matching: find.byType(RichText))
        .first,
  );
  final root = richText.text as TextSpan;
  return (root.children!.first as TextSpan).style;
}

void main() {
  testWidgets(
    'small JSON: non-lazy text widget, Cmd+A/Cmd+C leave native handling',
    (tester) async {
      final exchange = _exchangeWithJsonBody('{"a": 1, "b": [1, 2, 3]}');
      final calls = await _pumpBodyTab(tester, exchange);

      expect(find.byType(ListView), findsNothing);
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      await _sendShortcut(tester, LogicalKeyboardKey.keyA);
      await tester.pump();
      await _sendShortcut(tester, LogicalKeyboardKey.keyC);
      await tester.pump();

      expect(_setDataCalls(calls), isEmpty);
    },
  );

  testWidgets(
    'large JSON: Cmd+A highlights rows, Cmd+C copies, tap deselects',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final payload = _largePayload();
        final pretty = const JsonEncoder.withIndent('  ').convert(payload);
        final exchange = _exchangeWithJsonBody(jsonEncode(payload));
        final calls = await _pumpBodyTab(tester, exchange);

        expect(find.byType(ListView), findsOneWidget);

        await _sendShortcut(tester, LogicalKeyboardKey.keyA);
        await tester.pump();

        expect(_setDataCalls(calls), isEmpty);
        expect(_firstLineStyle(tester)?.backgroundColor, isNotNull);

        await _sendShortcut(tester, LogicalKeyboardKey.keyC);
        await tester.pump();

        expect(_setDataCalls(calls), hasLength(1));
        expect(_setDataCalls(calls).single.arguments, {'text': pretty});

        await tester.tap(find.byType(ListView));
        await tester.pump();
        await _sendShortcut(tester, LogicalKeyboardKey.keyC);
        await tester.pump();

        expect(_firstLineStyle(tester)?.backgroundColor, isNull);
        expect(
          _setDataCalls(
            calls,
          ).where((c) => (c.arguments as Map)['text'] == pretty),
          hasLength(1),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'large JSON with search field focused: Cmd+A/Cmd+C are not intercepted',
    (tester) async {
      final payload = _largePayload();
      final pretty = const JsonEncoder.withIndent('  ').convert(payload);
      final exchange = _exchangeWithJsonBody(jsonEncode(payload));
      final calls = await _pumpBodyTab(tester, exchange);

      await _sendShortcut(tester, LogicalKeyboardKey.keyF);
      await tester.pump();
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);

      await _sendShortcut(tester, LogicalKeyboardKey.keyA);
      await tester.pump();
      await _sendShortcut(tester, LogicalKeyboardKey.keyC);
      await tester.pump();

      expect(
        _setDataCalls(calls).where((c) => c.arguments == {'text': pretty}),
        isEmpty,
      );
    },
  );
}
