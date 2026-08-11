import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_response.dart';
import 'package:rox_proxy/services/breakpoint_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const breakpointEvents = EventChannel('com.roxproxy/breakpointEvents');
  const control = MethodChannel('com.roxproxy/control');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(breakpointEvents, null);
  });

  test('breakpointStream parses notifications from the EventChannel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          breakpointEvents,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              events.success({
                'type': 'breakpoint',
                'request': {
                  'id': 'bp-1',
                  'exchangeId': 'ex-1',
                  'type': 'request',
                  'method': 'POST',
                  'url': 'https://example.com/api',
                  'headers': [
                    {'name': 'Content-Type', 'value': 'application/json'},
                  ],
                  'body': 'hello',
                  'timestamp': '2026-08-10T10:00:00Z',
                },
              });
            },
          ),
        );

    final service = BreakpointService();
    final request = await service.breakpointStream.first;
    expect(request.id, 'bp-1');
    expect(request.exchangeId, 'ex-1');
    expect(request.method, 'POST');
    expect(request.url, 'https://example.com/api');
    expect(request.headers.single.name, 'Content-Type');
    expect(request.body, 'hello');
  });

  test(
    'sendDecision invokes breakpointDecision on the control channel',
    () async {
      Map<String, dynamic>? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(control, (call) async {
            expect(call.method, 'breakpointDecision');
            captured = Map<String, dynamic>.from(call.arguments as Map);
            return {'accepted': true};
          });

      final service = BreakpointService();
      await service.sendDecision(
        BreakpointResponse(
          breakpointId: 'bp-1',
          action: BreakpointAction.proceed,
          modifiedMethod: 'POST',
          timestamp: DateTime.utc(2026, 8, 10, 10),
        ),
      );

      expect(captured!['breakpointId'], 'bp-1');
      expect(captured!['action'], 'proceed');
      expect(captured!['modifiedMethod'], 'POST');
    },
  );
}
