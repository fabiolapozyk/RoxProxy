import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/ui/detail/body_search.dart';
import 'package:rox_proxy/ui/detail/body_tab.dart';
import 'package:rox_proxy/utils/body_renderer.dart';

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

CapturedExchange _exchangeWithTextBody(String body) {
  final exchange = CapturedExchange(
    id: 'ex-text',
    startTime: DateTime(2026, 1, 1),
    method: 'GET',
    url: 'http://example.com/txt',
    scheme: 'http',
    host: 'example.com',
    port: 80,
    path: '/txt',
    requestHeaders: const [HttpHeader('Content-Type', 'text/plain')],
    requestBodyRef: 'body-ref-text',
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

ScrollableState _bodyScrollable(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(finder);
}

int _countBackground(InlineSpan span, Color? color) {
  var count = 0;
  if (span is TextSpan) {
    if (span.style?.backgroundColor == color) count += 1;
    for (final child in span.children ?? const <InlineSpan>[]) {
      count += _countBackground(child, color);
    }
  }
  return count;
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

  testWidgets(
    'search: Enter scrolls to occurrences in order, cycles, N/M updates',
    (tester) async {
      final lines = <String>[
        for (var i = 0; i < 30; i++) 'line $i filler content',
        'first TARGET here',
        for (var i = 0; i < 20; i++) 'line $i more filler',
        'second TARGET here',
        for (var i = 0; i < 20; i++) 'line $i even more',
        'third TARGET here',
        for (var i = 0; i < 10; i++) 'last $i',
      ];
      final exchange = _exchangeWithTextBody(lines.join('\n'));
      await _pumpBodyTab(tester, exchange);

      await _sendShortcut(tester, LogicalKeyboardKey.keyF);
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'TARGET');
      await tester.pump();

      expect(find.textContaining('0/3'), findsOneWidget);

      final scrollable = _bodyScrollable(tester);
      expect(scrollable.position.pixels, 0);

      // Enter (simulato come azione di submit) -> prima occorrenza
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final first = scrollable.position.pixels;
      expect(first, greaterThan(0));
      expect(find.textContaining('1/3'), findsOneWidget);

      // L'occorrenza corrente ha highlight arancione (una sola).
      final orange = Colors.orange[400];
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final orangeCount = richTexts.fold<int>(
        0,
        (sum, rt) => sum + _countBackground(rt.text, orange),
      );
      expect(orangeCount, 1);

      // Enter -> seconda occorrenza
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final second = scrollable.position.pixels;
      expect(second, greaterThan(first));
      expect(find.textContaining('2/3'), findsOneWidget);

      // Enter -> terza occorrenza
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final third = scrollable.position.pixels;
      expect(third, greaterThan(second));
      expect(find.textContaining('3/3'), findsOneWidget);

      // Enter -> ciclo alla prima occorrenza
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, closeTo(first, 1));
      expect(find.textContaining('1/3'), findsOneWidget);
    },
  );

  testWidgets('search: previous (chevron) from no-selection goes to the last '
      'occurrence and cycles back', (tester) async {
    final lines = <String>[
      for (var i = 0; i < 30; i++) 'line $i filler content',
      'first TARGET here',
      for (var i = 0; i < 20; i++) 'line $i more filler',
      'second TARGET here',
      for (var i = 0; i < 20; i++) 'line $i even more',
      'third TARGET here',
      for (var i = 0; i < 10; i++) 'last $i',
    ];
    final exchange = _exchangeWithTextBody(lines.join('\n'));
    await _pumpBodyTab(tester, exchange);

    await _sendShortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'TARGET');
    await tester.pump();
    expect(find.textContaining('0/3'), findsOneWidget);

    // Nessuna selezione: "precedente" va all'ULTIMA occorrenza.
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(find.textContaining('3/3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(find.textContaining('2/3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(find.textContaining('1/3'), findsOneWidget);
  });

  testWidgets('search treats the query as literal text (regex escaped)', (
    tester,
  ) async {
    final exchange = _exchangeWithTextBody('foo.bar\nfooxbar\n');
    await _pumpBodyTab(tester, exchange);

    await _sendShortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.pump();

    // Il '.' non deve comportarsi da wildcard: 'foo.bar' trova solo la riga 0.
    await tester.enterText(find.byType(TextField), 'foo.bar');
    await tester.pump();
    expect(find.textContaining('0/1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'fooxbar');
    await tester.pump();
    expect(find.textContaining('0/1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nomatch');
    await tester.pump();
    expect(find.textContaining('0/0'), findsOneWidget);
  });

  testWidgets('large JSON (lazy): Enter scrolls to the match line', (
    tester,
  ) async {
    final payload = <String, int>{};
    for (var i = 0; i < 2500; i++) {
      payload['k$i'] = i;
    }
    final exchange = _exchangeWithJsonBody(jsonEncode(payload));
    await _pumpBodyTab(tester, exchange);

    expect(find.byType(ListView), findsOneWidget);

    await _sendShortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'k2400');
    await tester.pump();
    expect(find.textContaining('0/1'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Dopo lo scroll il match è stato costruito e ha l'highlight corrente.
    final orange = Colors.orange[400];
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final orangeCount = richTexts.fold<int>(
      0,
      (sum, rt) => sum + _countBackground(rt.text, orange),
    );
    expect(orangeCount, 1);
  });

  testWidgets('JSON search matches across segment boundaries', (tester) async {
    final exchange = _exchangeWithJsonBody('{"a": 1, "b": 2}');
    await _pumpBodyTab(tester, exchange);

    await _sendShortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.pump();

    // '": 1' attraversa i segmenti stringa/punteggiatura/spazio/numero.
    await tester.enterText(find.byType(TextField), '": 1');
    await tester.pump();
    expect(find.textContaining('0/1'), findsOneWidget);
  });

  testWidgets('large JSON with mixed line heights: Enter lands on the match, '
      'not a page earlier', (tester) async {
    // Finestra stretta così le righe lunghe vanno a capo (altezze variabili).
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final map = <String, dynamic>{};
    for (var i = 0; i < 1900; i++) {
      map['a$i'] = i;
    }
    for (var i = 0; i < 160; i++) {
      map['t$i'] = 'x' * 45;
    }
    final body = jsonEncode(map);
    final exchange = _exchangeWithJsonBody(body);
    await _pumpBodyTab(tester, exchange);

    await _sendShortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    await tester.pump();

    // Offset atteso: stessa metrica usata dal layout di ricerca.
    final mode = BodyRenderer.render(
      data: Uint8List.fromList(utf8.encode(body)),
      contentType: 'application/json',
    );
    final lines = (mode as RenderJson).lines
        .map((l) => l.segments.map((s) => s.text).join())
        .toList();
    final layout = BodySearchLayout(
      lines: lines,
      maxWidth: 400 - 24,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.5,
      ),
    );
    final match = findMatches(lines, 't100').single;
    final expected = layout.offsetForMatch(match);

    await tester.enterText(find.byType(TextField), 't100');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final pos = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    final orangeFinder = find.byWidgetPredicate(
      (w) => w is RichText && _hasBackground(w.text, Colors.orange[400]),
    );
    expect(orangeFinder, findsOneWidget);

    final rb = tester.renderObject<RenderBox>(orangeFinder.first);
    final topLeft = rb.localToGlobal(Offset.zero);
    final viewportTop = tester.getTopLeft(find.byType(ListView)).dy;
    final contentY = pos.position.pixels + (topLeft.dy - viewportTop);
    // +12 = padding top della ListView; tolleranza piccola.
    expect(contentY, closeTo(expected + 12, 2));
  });
}

bool _hasBackground(InlineSpan span, Color? color) {
  if (span is! TextSpan) return false;
  if (span.style?.backgroundColor == color) return true;
  return span.children?.any((c) => _hasBackground(c, color)) ?? false;
}
