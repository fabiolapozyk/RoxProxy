import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_response.dart';
import 'package:rox_proxy/models/captured_exchange.dart';

void main() {
  test('toMap serializes a proceed decision with modifications', () {
    final response = BreakpointResponse(
      breakpointId: 'bp-1',
      action: BreakpointAction.proceed,
      modifiedMethod: 'POST',
      modifiedUrl: 'https://example.com/api',
      modifiedHeaders: [
        const HttpHeader('X-Test', '1'),
        const HttpHeader('Content-Type', 'application/json'),
      ],
      modifiedBody: '{"x":1}',
      timestamp: DateTime.utc(2026, 8, 10, 10),
    );

    final map = response.toMap();
    expect(map['breakpointId'], 'bp-1');
    expect(map['action'], 'proceed');
    expect(map['modifiedMethod'], 'POST');
    expect(map['modifiedUrl'], 'https://example.com/api');
    expect(map['modifiedBody'], '{"x":1}');
    expect(map['timestamp'], '2026-08-10T10:00:00.000Z');

    final headers = map['modifiedHeaders'] as List;
    expect(headers.length, 2);
    final first = Map<String, dynamic>.from(headers.first as Map);
    expect(first['name'], 'X-Test');
    expect(first['value'], '1');
  });

  test('toMap serializes a response decision with status', () {
    final map = BreakpointResponse(
      breakpointId: 'bp-3',
      action: BreakpointAction.proceed,
      modifiedStatus: 503,
      modifiedBody: '{"error":true}',
      timestamp: DateTime.utc(2026, 8, 10, 10),
    ).toMap();

    expect(map['modifiedStatus'], 503);
    expect(map['modifiedBody'], '{"error":true}');
  });

  test('toMap serializes a cancel decision without modifications', () {
    final map = BreakpointResponse(
      breakpointId: 'bp-2',
      action: BreakpointAction.cancel,
      timestamp: DateTime.utc(2026, 8, 10, 10),
    ).toMap();

    expect(map['action'], 'cancel');
    expect(map['modifiedMethod'], isNull);
    expect(map['modifiedHeaders'], isNull);
    expect(map['modifiedBody'], isNull);
  });
}
