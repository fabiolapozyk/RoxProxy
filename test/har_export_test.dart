import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/services/har_exporter.dart';

CapturedExchange buildExchange({
  String id = 'ex-1',
  String method = 'GET',
  String url = 'https://example.com/a?b=2&a=1&a=3',
  String? requestBodyRef,
  String? responseBodyRef,
  List<HttpHeader>? responseHeaders,
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
  path: '/a?b=2&a=1&a=3',
  requestHeaders: const [HttpHeader('Host', 'example.com')],
  requestBodyRef: requestBodyRef,
  requestSize: requestSize,
  statusCode: 200,
  statusMessage: 'OK',
  responseHeaders:
      responseHeaders ??
      const [HttpHeader('Content-Type', 'text/plain; charset=utf-8')],
  responseBodyRef: responseBodyRef,
  responseSize: responseSize,
  isHTTPS: true,
  isMITMDecrypted: true,
  state: ExchangeState.completed,
);

Future<Uint8List?> _noBody(String ref) async => null;

Future<Uint8List?> _noDecompress(Uint8List data, String encoding) async => null;

Map<String, dynamic> _entry(Map<String, dynamic> har) =>
    ((har['log'] as Map)['entries'] as List).single as Map<String, dynamic>;

void main() {
  const exporter = HarExporter();

  test('emits a HAR 1.2 envelope with creator and one entry', () async {
    final har = await exporter.build(
      exchanges: [buildExchange()],
      readBody: _noBody,
      decompress: _noDecompress,
      creatorVersion: '0.3.0+1',
    );

    final log = har['log'] as Map;
    expect(log['version'], '1.2');
    expect(log['creator'], {'name': 'RoxProxy', 'version': '0.3.0+1'});
    expect(log['entries'], hasLength(1));

    final entry = _entry(har);
    expect(entry['startedDateTime'], '2023-11-14T22:13:20.000Z');
    expect(entry['time'], 250);
    expect(entry['request']['method'], 'GET');
    expect(entry['response']['status'], 200);
    expect(entry['response']['statusText'], 'OK');
    expect(entry['timings'], {'send': 0, 'wait': 250, 'receive': 0});
    expect(entry['cache'], isEmpty);
  });

  test('preserves query-string order and repeated keys', () async {
    final har = await exporter.build(
      exchanges: [buildExchange()],
      readBody: _noBody,
      decompress: _noDecompress,
    );

    expect(_entry(har)['request']['queryString'], [
      {'name': 'b', 'value': '2'},
      {'name': 'a', 'value': '1'},
      {'name': 'a', 'value': '3'},
    ]);
  });

  test('encodes UTF-8 bodies as text and binary bodies as base64', () async {
    final bodies = <String, Uint8List>{
      'text': Uint8List.fromList(utf8.encode('{"ok":true}')),
      'bin': Uint8List.fromList([0xFF, 0xFE, 0x00]),
    };

    final har = await exporter.build(
      exchanges: [
        buildExchange(id: 't', requestBodyRef: 'text', responseBodyRef: 'text'),
        buildExchange(id: 'b', responseBodyRef: 'bin'),
      ],
      readBody: (ref) async => bodies[ref],
      decompress: _noDecompress,
    );

    final entries = (har['log'] as Map)['entries'] as List;
    final textEntry = entries[0] as Map;
    final binaryEntry = entries[1] as Map;

    expect(textEntry['request']['postData']['text'], '{"ok":true}');
    expect(textEntry['request']['postData'].containsKey('encoding'), isFalse);
    expect(textEntry['response']['content']['text'], '{"ok":true}');

    expect(binaryEntry['response']['content']['encoding'], 'base64');
    expect(
      binaryEntry['response']['content']['text'],
      base64Encode([0xFF, 0xFE, 0x00]),
    );
  });

  test(
    'decompresses gzip bodies and drops the stale content-encoding',
    () async {
      final compressed = Uint8List.fromList([1, 2, 3]);
      final plain = Uint8List.fromList(utf8.encode('hello'));

      final har = await exporter.build(
        exchanges: [
          buildExchange(
            responseBodyRef: 'gz',
            responseSize: 3,
            responseHeaders: const [
              HttpHeader('Content-Type', 'text/plain'),
              HttpHeader('Content-Encoding', 'gzip'),
            ],
          ),
        ],
        readBody: (_) async => compressed,
        decompress: (data, encoding) async {
          expect(encoding, 'gzip');
          return plain;
        },
      );

      final entry = _entry(har);
      expect(entry['response']['content']['text'], 'hello');
      expect(entry['response']['content']['size'], 5);
      expect(entry['response']['bodySize'], 3);
      expect(
        (entry['response']['headers'] as List).any(
          (h) => (h as Map)['name'] == 'Content-Encoding',
        ),
        isFalse,
      );
    },
  );

  test('falls back to raw bytes when the encoding is unsupported', () async {
    final raw = Uint8List.fromList([0xFF, 0x01]);

    final har = await exporter.build(
      exchanges: [
        buildExchange(
          responseBodyRef: 'br',
          responseHeaders: const [
            HttpHeader('Content-Type', 'text/plain'),
            HttpHeader('Content-Encoding', 'br'),
          ],
        ),
      ],
      readBody: (_) async => raw,
      decompress: (data, encoding) async => null,
    );

    final entry = _entry(har);
    expect(entry['_encoding'], 'br');
    expect(entry['response']['content']['encoding'], 'base64');
    expect(
      (entry['response']['headers'] as List).any(
        (h) => (h as Map)['name'] == 'Content-Encoding',
      ),
      isTrue,
    );
  });

  test('marks truncated bodies and reports the real size', () async {
    final har = await exporter.build(
      exchanges: [buildExchange(responseBodyRef: 'part', responseSize: 1000)],
      readBody: (_) async => Uint8List.fromList([1, 2, 3]),
      decompress: _noDecompress,
    );

    final entry = _entry(har);
    expect(entry['_truncated'], isTrue);
    expect(entry['response']['bodySize'], 1000);
    expect(entry['response']['content']['size'], 3);
  });

  test('handles an in-flight exchange without status or duration', () async {
    final exchange = buildExchange();
    exchange.endTime = null;
    exchange.statusCode = null;
    exchange.statusMessage = null;
    exchange.state = ExchangeState.inProgress;

    final har = await exporter.build(
      exchanges: [exchange],
      readBody: _noBody,
      decompress: _noDecompress,
    );

    final entry = _entry(har);
    expect(entry['time'], 0);
    expect(entry['response']['status'], 0);
    expect(entry['timings'], {'send': 0, 'wait': 0, 'receive': 0});
  });

  test('embeds RoxProxy metadata in the _roxProxy custom field', () async {
    final exchange = buildExchange()
      ..isMapLocal = true
      ..isBreakpoint = true
      ..isResponseBreakpoint = true
      ..state = ExchangeState.failed
      ..errorMessage = 'boom';

    final har = await exporter.build(
      exchanges: [exchange],
      readBody: _noBody,
      decompress: _noDecompress,
    );

    final meta = _entry(har)['_roxProxy'] as Map;
    expect(meta['id'], 'ex-1');
    expect(meta['isMITMDecrypted'], isTrue);
    expect(meta['isMapLocal'], isTrue);
    expect(meta['isBreakpoint'], isTrue);
    expect(meta['isResponseBreakpoint'], isTrue);
    expect(meta['error'], 'boom');
  });
}
