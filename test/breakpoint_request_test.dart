import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_request.dart';

void main() {
  test('fromMap parses a full notification', () {
    final request = BreakpointRequest.fromMap({
      'id': 'bp-1',
      'exchangeId': 'ex-1',
      'type': 'request',
      'method': 'POST',
      'url': 'https://example.com/api',
      'headers': [
        {'name': 'Content-Type', 'value': 'application/json'},
      ],
      'body': '{"ok":true}',
      'timestamp': '2026-08-10T10:00:00Z',
    });

    expect(request.id, 'bp-1');
    expect(request.exchangeId, 'ex-1');
    expect(request.method, 'POST');
    expect(request.url, 'https://example.com/api');
    expect(request.headers.single.name, 'Content-Type');
    expect(request.headers.single.value, 'application/json');
    expect(request.body, '{"ok":true}');
    expect(request.timestamp, DateTime.utc(2026, 8, 10, 10));
  });

  test('fromMap handles missing body and headers', () {
    final request = BreakpointRequest.fromMap({
      'id': 'bp-2',
      'exchangeId': 'ex-2',
      'method': 'GET',
      'url': 'https://example.com/',
      'timestamp': '2026-08-10T10:00:00Z',
    });

    expect(request.body, isNull);
    expect(request.headers, isEmpty);
  });

  test('host getter extracts from url', () {
    final request = BreakpointRequest.fromMap({
      'id': 'bp-3',
      'exchangeId': 'ex-3',
      'method': 'GET',
      'url': 'https://api.example.com/v1',
      'timestamp': '2026-08-10T10:00:00Z',
    });
    expect(request.host, 'api.example.com');
  });
}
