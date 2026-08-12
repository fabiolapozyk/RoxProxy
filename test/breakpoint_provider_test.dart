import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_notification.dart';
import 'package:rox_proxy/models/breakpoint_request.dart';
import 'package:rox_proxy/models/breakpoint_response.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/models/response_breakpoint.dart';
import 'package:rox_proxy/providers/breakpoint_provider.dart';
import 'package:rox_proxy/services/breakpoint_service.dart';

/// Fake service: emits notifications from a controller and records decisions.
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

RequestBreakpointNotification requestNotification(String id) =>
    RequestBreakpointNotification(
      BreakpointRequest(
        id: id,
        exchangeId: 'ex-$id',
        method: 'GET',
        url: 'https://example.com/$id',
        headers: const [],
        timestamp: DateTime.now(),
      ),
    );

ResponseBreakpointNotification responseNotification(String id) =>
    ResponseBreakpointNotification(
      ResponseBreakpoint(
        id: id,
        exchangeId: 'ex-$id',
        method: 'GET',
        url: 'https://example.com/$id',
        statusCode: 200,
        statusMessage: 'OK',
        headers: const [],
        timestamp: DateTime.now(),
      ),
    );

void main() {
  test('notification activates the dialog state', () async {
    final fake = FakeBreakpointService();
    final container = ProviderContainer(
      overrides: [breakpointServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    // Istanzia il notifier (e la subscription) prima di emettere eventi.
    container.read(breakpointProvider.notifier);

    fake.controller.add(requestNotification('a'));
    await Future<void>.delayed(Duration.zero);

    final state = container.read(breakpointProvider);
    expect(state.active?.id, 'a');
    expect(state.active, isA<RequestBreakpointNotification>());
    expect(state.remainingSeconds, BreakpointNotifier.timeoutSeconds);
  });

  test('parallel requests are queued', () async {
    final fake = FakeBreakpointService();
    final container = ProviderContainer(
      overrides: [breakpointServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    container.read(breakpointProvider.notifier);

    fake.controller.add(requestNotification('a'));
    fake.controller.add(responseNotification('b'));
    fake.controller.add(requestNotification('c'));
    await Future<void>.delayed(Duration.zero);

    var state = container.read(breakpointProvider);
    expect(state.active?.id, 'a');
    expect(state.queue.map((n) => n.id), ['b', 'c']);

    await container.read(breakpointProvider.notifier).cancel();
    state = container.read(breakpointProvider);
    expect(state.active, isA<ResponseBreakpointNotification>());
    expect(state.queue.map((n) => n.id), ['c']);
  });

  test('proceed sends the decision with modifications and advances', () async {
    final fake = FakeBreakpointService();
    final container = ProviderContainer(
      overrides: [breakpointServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    container.read(breakpointProvider.notifier);

    fake.controller.add(requestNotification('a'));
    await Future<void>.delayed(Duration.zero);

    await container
        .read(breakpointProvider.notifier)
        .proceed(
          method: 'POST',
          url: 'https://example.com/edited',
          headers: const [],
          body: '{"x":1}',
        );

    final decision = fake.decisions.single;
    expect(decision.breakpointId, 'a');
    expect(decision.action, BreakpointAction.proceed);
    expect(decision.modifiedMethod, 'POST');
    expect(decision.modifiedUrl, 'https://example.com/edited');
    expect(decision.modifiedBody, '{"x":1}');
    expect(container.read(breakpointProvider).active, isNull);
  });

  test('proceedResponse forwards the response as-is', () async {
    final fake = FakeBreakpointService();
    final container = ProviderContainer(
      overrides: [breakpointServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    container.read(breakpointProvider.notifier);

    fake.controller.add(responseNotification('r'));
    await Future<void>.delayed(Duration.zero);

    await container.read(breakpointProvider.notifier).proceedResponse();

    final decision = fake.decisions.single;
    expect(decision.breakpointId, 'r');
    expect(decision.action, BreakpointAction.proceed);
    expect(decision.modifiedMethod, isNull);
    expect(decision.modifiedStatus, isNull);
    expect(container.read(breakpointProvider).active, isNull);
  });

  test('proceedResponse forwards modifications for responses', () async {
    final fake = FakeBreakpointService();
    final container = ProviderContainer(
      overrides: [breakpointServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    container.read(breakpointProvider.notifier);

    fake.controller.add(responseNotification('r'));
    await Future<void>.delayed(Duration.zero);

    await container
        .read(breakpointProvider.notifier)
        .proceedResponse(
          status: 503,
          headers: const [HttpHeader('X-Test', '1')],
          body: '{"error":true}',
        );

    final decision = fake.decisions.single;
    expect(decision.modifiedStatus, 503);
    expect(decision.modifiedBody, '{"error":true}');
    expect(decision.modifiedHeaders?.single.name, 'X-Test');
  });

  test('cancel sends the cancel decision', () async {
    final fake = FakeBreakpointService();
    final container = ProviderContainer(
      overrides: [breakpointServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    container.read(breakpointProvider.notifier);

    fake.controller.add(requestNotification('a'));
    await Future<void>.delayed(Duration.zero);

    await container.read(breakpointProvider.notifier).cancel();

    final decision = fake.decisions.single;
    expect(decision.action, BreakpointAction.cancel);
    expect(container.read(breakpointProvider).active, isNull);
  });

  test('countdown reaches zero and advances without sending a decision', () {
    fakeAsync((async) {
      final fake = FakeBreakpointService();
      final container = ProviderContainer(
        overrides: [breakpointServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      container.read(breakpointProvider.notifier);

      fake.controller.add(requestNotification('a'));
      async.flushMicrotasks();

      expect(container.read(breakpointProvider).active?.id, 'a');

      async.elapse(
        const Duration(seconds: BreakpointNotifier.timeoutSeconds + 1),
      );

      expect(container.read(breakpointProvider).active, isNull);
      expect(fake.decisions, isEmpty);
    });
  });
}
