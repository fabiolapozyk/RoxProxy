import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/services/har_exporter.dart';
import 'package:rox_proxy/services/har_importer.dart';

CapturedExchange buildExchange({
  String id = 'ex-1',
  String method = 'GET',
  String url = 'https://example.com/a?b=2&a=1',
  int statusCode = 200,
  int requestSize = 0,
  int? responseSize,
}) => CapturedExchange(
  id: id,
  startTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  endTime: DateTime.fromMillisecondsSinceEpoch(1700000000250),
  method: method,
  url: url,
  scheme: 'https',
  host: 'example.com',
  port: 443,
  path:
      Uri.parse(url).path +
      (Uri.parse(url).query.isEmpty ? '' : '?${Uri.parse(url).query}'),
  requestHeaders: const [HttpHeader('Host', 'example.com')],
  requestSize: requestSize,
  statusCode: statusCode,
  statusMessage: 'OK',
  responseHeaders: const [HttpHeader('Content-Type', 'text/plain')],
  responseSize: responseSize,
  isHTTPS: true,
  isMITMDecrypted: true,
  state: ExchangeState.completed,
);

Future<String> exportHar(
  List<CapturedExchange> exchanges,
  Map<String, Uint8List> bodies,
) async {
  final har = await const HarExporter().build(
    exchanges: exchanges,
    readBody: (ref) async => bodies[ref],
    decompress: (data, encoding) async => null,
    creatorVersion: '0.3.0+1',
  );
  return const JsonEncoder.withIndent('  ').convert(har);
}

void main() {
  const importer = HarImporter();

  test(
    'round-trips an exported capture preserving fields and bodies',
    () async {
      final exchange = buildExchange(
        method: 'POST',
        requestSize: 7,
        responseSize: 5,
      );
      exchange.requestBodyRef = 'req';
      exchange.responseBodyRef = 'res';
      exchange.isMapLocal = true;
      exchange.isBreakpoint = true;

      final contents = await exportHar(
        [exchange],
        {
          'req': Uint8List.fromList(utf8.encode('{"a":1}')),
          'res': Uint8List.fromList(utf8.encode('hello')),
        },
      );

      final imported = importer.parse(contents);
      expect(imported, hasLength(1));
      final item = imported.single;
      final e = item.exchange;

      expect(e.id, 'ex-1');
      expect(e.method, 'POST');
      expect(e.url, 'https://example.com/a?b=2&a=1');
      expect(e.scheme, 'https');
      expect(e.host, 'example.com');
      expect(e.port, 443);
      expect(e.path, '/a?b=2&a=1');
      expect(e.statusCode, 200);
      expect(e.statusMessage, 'OK');
      expect(e.state, ExchangeState.completed);
      expect(e.isHTTPS, isTrue);
      expect(e.isMITMDecrypted, isTrue);
      expect(e.isMapLocal, isTrue);
      expect(e.isBreakpoint, isTrue);
      expect(e.startTime.toUtc().millisecondsSinceEpoch, 1700000000000);
      expect(e.duration?.inMilliseconds, 250); // from startedDateTime + time
      expect(e.requestHeaders.single.name, 'Host');

      expect(item.requestBody, Uint8List.fromList(utf8.encode('{"a":1}')));
      expect(item.responseBody, Uint8List.fromList(utf8.encode('hello')));
    },
  );

  test('round-trips binary bodies through base64', () async {
    final exchange = buildExchange();
    exchange.responseBodyRef = 'res';
    exchange.responseSize = 3;

    final contents = await exportHar(
      [exchange],
      {
        'res': Uint8List.fromList([0xFF, 0xFE, 0x00]),
      },
    );

    final item = importer.parse(contents).single;
    expect(item.responseBody, Uint8List.fromList([0xFF, 0xFE, 0x00]));
  });

  test('imports a foreign HAR without RoxProxy metadata', () {
    const foreign = '''
{
  "log": {
    "version": "1.2",
    "creator": {"name": "Chrome", "version": "1"},
    "entries": [
      {
        "startedDateTime": "2024-05-01T10:00:00.000Z",
        "time": 12.5,
        "request": {
          "method": "GET",
          "url": "https://example.com/a?x=1",
          "httpVersion": "HTTP/1.1",
          "headers": [{"name": "Host", "value": "example.com"}],
          "queryString": [{"name": "x", "value": "1"}],
          "headersSize": -1,
          "bodySize": 0
        },
        "response": {
          "status": 200,
          "statusText": "OK",
          "httpVersion": "HTTP/1.1",
          "headers": [{"name": "Content-Type", "value": "application/json"}],
          "content": {"size": 7, "mimeType": "application/json", "text": "eyJhIjoxfQ==", "encoding": "base64"},
          "redirectURL": "",
          "headersSize": -1,
          "bodySize": 7
        },
        "cache": {},
        "timings": {"send": 0, "wait": 12.5, "receive": 0}
      }
    ]
  }
}
''';

    final item = importer.parse(foreign).single;
    expect(item.exchange.id, isNotEmpty);
    expect(item.exchange.scheme, 'https');
    expect(item.exchange.host, 'example.com');
    expect(item.exchange.port, 443);
    expect(item.exchange.path, '/a?x=1');
    expect(item.exchange.statusCode, 200);
    // Without metadata, an HTTPS capture is assumed decrypted.
    expect(item.exchange.isMITMDecrypted, isTrue);
    expect(item.exchange.isMapLocal, isFalse);
    expect(item.responseBody, Uint8List.fromList(utf8.encode('{"a":1}')));
  });

  test('rebuilds a form body from postData params', () {
    const har = '''
{
  "log": {"version": "1.2", "creator": {"name": "x", "version": "1"}, "entries": [
    {
      "startedDateTime": "2024-05-01T10:00:00.000Z",
      "time": 0,
      "request": {
        "method": "POST",
        "url": "http://example.com/form",
        "headers": [{"name": "Host", "value": "example.com"}],
        "postData": {
          "mimeType": "application/x-www-form-urlencoded",
          "params": [{"name": "a", "value": "1"}, {"name": "b", "value": "2"}]
        },
        "headersSize": -1,
        "bodySize": 7
      },
      "response": {"status": 204, "statusText": "No Content", "headers": [], "content": {"size": 0}, "headersSize": -1, "bodySize": 0},
      "cache": {},
      "timings": {"send": 0, "wait": 0, "receive": 0}
    }
  ]}
}
''';

    final item = importer.parse(har).single;
    expect(item.requestBody, Uint8List.fromList(utf8.encode('a=1&b=2')));
    expect(item.exchange.scheme, 'http');
    expect(item.exchange.port, 80);
    expect(item.exchange.isHTTPS, isFalse);
  });

  test('restores a failed state from the metadata error field', () async {
    final exchange = buildExchange(statusCode: 0);
    exchange.statusCode = null;
    exchange.state = ExchangeState.failed;
    exchange.errorMessage = 'Cancelled by user (breakpoint)';

    final contents = await exportHar([exchange], {});
    final item = importer.parse(contents).single;

    expect(item.exchange.state, ExchangeState.failed);
    expect(item.exchange.errorMessage, 'Cancelled by user (breakpoint)');
    expect(item.exchange.statusCode, isNull);
  });

  test('strips residual content-encoding when the body is already text', () {
    const har = '''
{
  "log": {"version": "1.2", "creator": {"name": "x", "version": "1"}, "entries": [
    {
      "startedDateTime": "2024-05-01T10:00:00.000Z",
      "time": 1,
      "request": {
        "method": "GET",
        "url": "https://example.com/",
        "headers": [{"name": "Host", "value": "example.com"}],
        "headersSize": -1,
        "bodySize": 0
      },
      "response": {
        "status": 200,
        "statusText": "OK",
        "headers": [
          {"name": "Content-Type", "value": "text/plain"},
          {"name": "Content-Encoding", "value": "gzip"},
          {"name": "Content-Length", "value": "5"}
        ],
        "content": {"size": 5, "mimeType": "text/plain", "text": "hello"},
        "headersSize": -1,
        "bodySize": 5
      },
      "cache": {},
      "timings": {"send": 0, "wait": 1, "receive": 0}
    }
  ]}
}
''';

    final item = importer.parse(har).single;
    expect(item.responseBody, Uint8List.fromList(utf8.encode('hello')));
    expect(
      item.exchange.responseHeaders!.map((h) => h.name.toLowerCase()),
      isNot(contains('content-encoding')),
    );
    expect(
      item.exchange.responseHeaders!.map((h) => h.name.toLowerCase()),
      isNot(contains('content-length')),
    );
  });

  group('invalid input', () {
    test('rejects non-JSON content', () {
      expect(() => importer.parse('nope'), throwsA(isA<HarFormatException>()));
    });

    test('rejects a document without a log object', () {
      expect(
        () => importer.parse('{"foo":1}'),
        throwsA(isA<HarFormatException>()),
      );
    });

    test('rejects a log without entries', () {
      expect(
        () => importer.parse('{"log":{"version":"1.2"}}'),
        throwsA(isA<HarFormatException>()),
      );
    });

    test('rejects a JSON array', () {
      expect(() => importer.parse('[]'), throwsA(isA<HarFormatException>()));
    });
  });
}
