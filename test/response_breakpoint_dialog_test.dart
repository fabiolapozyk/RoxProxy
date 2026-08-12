import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_notification.dart';
import 'package:rox_proxy/models/breakpoint_response.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/models/response_breakpoint.dart';
import 'package:rox_proxy/providers/breakpoint_provider.dart';
import 'package:rox_proxy/services/breakpoint_service.dart';
import 'package:rox_proxy/ui/breakpoint/response_breakpoint_dialog.dart';

class FakeBreakpointService extends BreakpointService {
  final controller = StreamController<BreakpointNotification>();
  final decisions = <BreakpointResponse>[];

  @override
  Stream<BreakpointNotification> get breakpointStream => controller.stream;

  @override
  Future<void> sendDecision(BreakpointResponse response) async {
    decisions.add(response);
  }
}

ResponseBreakpointNotification sampleResponse() =>
    ResponseBreakpointNotification(
      ResponseBreakpoint(
        id: 'rb-1',
        exchangeId: 'ex-1',
        method: 'GET',
        url: 'https://example.com/api',
        statusCode: 404,
        statusMessage: 'Not Found',
        headers: const [
          // ignore: prefer_const_constructors
          HttpHeader('Content-Type', 'application/json'),
        ],
        body: '{"error":true}',
        timestamp: DateTime.now(),
      ),
    );

void main() {
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
                    builder: (_) => ResponseBreakpointDialog(
                      response: sampleResponse().response,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    container.read(breakpointProvider.notifier);
    fake.controller.add(sampleResponse());
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows status, headers and body with countdown', (tester) async {
    final fake = FakeBreakpointService();
    await pumpDialog(tester, fake);

    expect(find.text('Response breakpoint — GET example.com'), findsOneWidget);
    expect(find.text('404 Not Found'), findsOneWidget);
    expect(find.text('Auto-proceed in 30s'), findsOneWidget);
    expect(find.text('Content-Type: application/json'), findsOneWidget);
    expect(find.text('{"error":true}'), findsOneWidget);
    expect(find.text('Proceed'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('proceed forwards the response as-is', (tester) async {
    final fake = FakeBreakpointService();
    await pumpDialog(tester, fake);

    await tester.tap(find.text('Proceed'));
    await tester.pumpAndSettle();

    expect(fake.decisions.single.breakpointId, 'rb-1');
    expect(fake.decisions.single.action.name, 'proceed');
  });

  testWidgets('cancel aborts the response', (tester) async {
    final fake = FakeBreakpointService();
    await pumpDialog(tester, fake);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fake.decisions.single.action.name, 'cancel');
  });
}
