import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/response_breakpoint.dart';

void main() {
  test('fromMap parses a full response notification', () {
    final response = ResponseBreakpoint.fromMap({
      'id': 'rb-1',
      'exchangeId': 'ex-1',
      'type': 'response',
      'method': 'GET',
      'url': 'https://example.com/api',
      'statusCode': 404,
      'statusMessage': 'Not Found',
      'headers': [
        {'name': 'Content-Type', 'value': 'application/json'},
      ],
      'body': '{"error":true}',
      'timestamp': '2026-08-10T10:00:00Z',
    });

    expect(response.id, 'rb-1');
    expect(response.exchangeId, 'ex-1');
    expect(response.method, 'GET');
    expect(response.url, 'https://example.com/api');
    expect(response.statusCode, 404);
    expect(response.statusMessage, 'Not Found');
    expect(response.headers.single.name, 'Content-Type');
    expect(response.body, '{"error":true}');
    expect(response.host, 'example.com');
    expect(response.timestamp, DateTime.utc(2026, 8, 10, 10));
  });

  test('fromMap handles missing body, message and headers', () {
    final response = ResponseBreakpoint.fromMap({
      'id': 'rb-2',
      'exchangeId': 'ex-2',
      'method': 'GET',
      'url': 'https://example.com/',
      'statusCode': 200,
      'timestamp': '2026-08-10T10:00:00Z',
    });

    expect(response.body, isNull);
    expect(response.statusMessage, isNull);
    expect(response.headers, isEmpty);
  });
}
