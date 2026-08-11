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
  /// Pumps the app and opens the dialog via a real route, exactly like the
  /// real flow (EventChannel → provider → showDialog).
  Future<void> pumpDialog(
    WidgetTester tester,
    FakeBreakpointService fake,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [breakpointServiceProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => BreakpointDialog(request: sampleRequest()),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Crea il notifier (e la subscription) prima di emettere l'evento.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    container.read(breakpointProvider.notifier);
    // Attiva il provider PRIMA di aprire il dialog, come in produzione
    // (main_window osserva il provider fin dall'avvio).
    fake.controller.add(sampleRequest());
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows request details and countdown', (tester) async {
    final fake = FakeBreakpointService();
    await pumpDialog(tester, fake);

    expect(find.byType(BreakpointDialog), findsOneWidget);
    expect(find.text('Breakpoint — POST example.com'), findsOneWidget);
    expect(find.text('Auto-proceed in 30s'), findsOneWidget);
    expect(find.text('Proceed'), findsOneWidget);
    expect(find.text('Cancel (400)'), findsOneWidget);
    expect(find.text('{"a":1}'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Content-Type'), findsOneWidget);
  });

  testWidgets('closes on timeout when the request auto-proceeds', (
    tester,
  ) async {
    final fake = FakeBreakpointService();
    await pumpDialog(tester, fake);
    expect(find.byType(BreakpointDialog), findsOneWidget);

    // Scade il countdown UI (30 tick + margine).
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();

    expect(find.byType(BreakpointDialog), findsNothing);
    expect(fake.decisions, isEmpty, reason: 'il timeout non invia decisioni');
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
