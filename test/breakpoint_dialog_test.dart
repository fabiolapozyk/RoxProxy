import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_request.dart';
import 'package:rox_proxy/models/breakpoint_response.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/providers/breakpoint_provider.dart';
import 'package:rox_proxy/services/breakpoint_service.dart';
import 'package:rox_proxy/ui/breakpoint/breakpoint_dialog.dart';

class FakeBreakpointService extends BreakpointService {
  final controller = StreamController<BreakpointRequest>();
  final decisions = <BreakpointResponse>[];

  @override
  Stream<BreakpointRequest> get breakpointStream => controller.stream;

  @override
  Future<void> sendDecision(BreakpointResponse response) async {
    decisions.add(response);
  }
}

BreakpointRequest sampleRequest() => BreakpointRequest(
  id: 'bp-1',
  exchangeId: 'ex-1',
  method: 'POST',
  url: 'https://example.com/api',
  headers: const [HttpHeader('Content-Type', 'application/json')],
  body: '{"a":1}',
  timestamp: DateTime.now(),
);

void main() {
  /// Pumps the dialog after activating the provider with the sample request,
  /// exactly like the real flow (EventChannel → provider → dialog).
  Future<void> pumpDialog(
    WidgetTester tester,
    FakeBreakpointService fake,
  ) async {
    fake.controller.add(sampleRequest());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [breakpointServiceProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Scaffold(body: BreakpointDialog(request: sampleRequest())),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows request details and countdown', (tester) async {
    final fake = FakeBreakpointService();
    await pumpDialog(tester, fake);

    expect(find.text('Breakpoint — POST example.com'), findsOneWidget);
    expect(find.text('Auto-proceed in 30s'), findsOneWidget);
    expect(find.text('Proceed'), findsOneWidget);
    expect(find.text('Cancel (400)'), findsOneWidget);
    expect(find.text('{"a":1}'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Content-Type'), findsOneWidget);
  });

  testWidgets('proceed sends the modified request', (tester) async {
    final fake = FakeBreakpointService();
    await pumpDialog(tester, fake);

    await tester.enterText(
      find.widgetWithText(TextField, 'URL'),
      'https://example.com/changed',
    );
    await tester.tap(find.text('Proceed'));
    await tester.pumpAndSettle();

    final decision = fake.decisions.single;
    expect(decision.breakpointId, 'bp-1');
    expect(decision.action, BreakpointAction.proceed);
    expect(decision.modifiedUrl, 'https://example.com/changed');
    expect(decision.modifiedBody, '{"a":1}');
  });

  testWidgets('cancel sends the cancel decision', (tester) async {
    final fake = FakeBreakpointService();
    await pumpDialog(tester, fake);

    await tester.tap(find.text('Cancel (400)'));
    await tester.pumpAndSettle();

    final decision = fake.decisions.single;
    expect(decision.action, BreakpointAction.cancel);
  });
}
