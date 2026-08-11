import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';

CapturedExchange exchange({
  String id = 'ex-1',
  String method = 'GET',
  String url = 'https://example.com/path',
  String path = '/path',
}) => CapturedExchange(
  id: id,
  startTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  method: method,
  url: url,
  scheme: 'https',
  host: 'example.com',
  port: 443,
  path: path,
  requestHeaders: const [HttpHeader('Host', 'example.com')],
  requestSize: 0,
  isHTTPS: true,
  isMITMDecrypted: true,
  isBreakpoint: true,
);

void main() {
  test(
    'applyUpdate recepisce URL/metodo/path/header modificati al breakpoint',
    () {
      final current = exchange();
      final updated = exchange(
        method: 'POST',
        url: 'https://example.com/pathe',
        path: '/pathe',
      );

      current.applyUpdate(updated);

      expect(current.method, 'POST');
      expect(current.url, 'https://example.com/pathe');
      expect(current.path, '/pathe');
      expect(current.requestHeaders.single.name, 'Host');
    },
  );

  test('applyUpdate aggiorna stato e codice di risposta', () {
    final current = exchange();
    final updated = exchange();
    updated.statusCode = 400;
    updated.state = ExchangeState.failed;
    updated.errorMessage = 'Cancelled by user (breakpoint)';
    updated.endTime = DateTime.fromMillisecondsSinceEpoch(1700000001000);

    current.applyUpdate(updated);

    expect(current.statusCode, 400);
    expect(current.state, ExchangeState.failed);
    expect(current.errorMessage, 'Cancelled by user (breakpoint)');
    expect(current.endTime, isNotNull);
  });

  test('fromMap parses isBreakpoint con default false', () {
    final withFlag = CapturedExchange.fromMap({
      'id': 'ex-1',
      'startTime': 1700000000000,
      'method': 'GET',
      'url': 'https://example.com/',
      'scheme': 'https',
      'host': 'example.com',
      'port': 443,
      'path': '/',
      'requestHeaders': [],
      'requestSize': 0,
      'isHTTPS': true,
      'isMITMDecrypted': true,
      'isBreakpoint': true,
      'state': 'inProgress',
    });
    expect(withFlag.isBreakpoint, isTrue);

    final noFlag = CapturedExchange.fromMap({
      'id': 'ex-2',
      'startTime': 1700000000000,
      'method': 'GET',
      'url': 'https://example.com/',
      'scheme': 'https',
      'host': 'example.com',
      'port': 443,
      'path': '/',
      'requestHeaders': [],
      'requestSize': 0,
      'isHTTPS': true,
      'isMITMDecrypted': true,
      'state': 'inProgress',
    });
    expect(noFlag.isBreakpoint, isFalse);
  });
}
