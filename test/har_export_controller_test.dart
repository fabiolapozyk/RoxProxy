import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_rule.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/models/domain_rule.dart';
import 'package:rox_proxy/models/map_local_rule.dart';
import 'package:rox_proxy/providers/har_export_provider.dart';
import 'package:rox_proxy/providers/proxy_channel_provider.dart';
import 'package:rox_proxy/services/proxy_channel.dart';

class _FakeProxyChannel extends ProxyChannel {
  final Map<String, Uint8List> bodies = {};
  final _events = StreamController<ExchangeEvent>.broadcast();

  @override
  Stream<ExchangeEvent> get exchangeStream => _events.stream;

  @override
  Future<Uint8List?> fetchBody(String ref) async => bodies[ref];

  @override
  Future<Uint8List?> decompressBody(Uint8List data, String encoding) async =>
      // Echo the input length so tests can tell which bytes were decompressed.
      Uint8List.fromList(utf8.encode('len:${data.length}'));

  @override
  Future<String?> getAppVersion() async => '0.3.0+1';

  @override
  Future<int> startProxy({
    required int port,
    required List<DomainRule> domainRules,
    required int connectionTimeoutSeconds,
    required bool setSystemProxy,
    required bool httpsInterceptionEnabled,
    List<MapLocalRule> mapLocalRules = const [],
    bool breakpointEnabled = false,
    List<BreakpointRule> breakpointRules = const [],
  }) async => port;

  @override
  Future<void> stopProxy() async {}

  Future<void> dispose() => _events.close();
}

CapturedExchange buildExchange({
  required String id,
  required String url,
  String host = 'example.com',
}) => CapturedExchange(
  id: id,
  startTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  endTime: DateTime.fromMillisecondsSinceEpoch(1700000000100),
  method: 'GET',
  url: url,
  scheme: 'https',
  host: host,
  port: 443,
  path: Uri.parse(url).path,
  requestHeaders: const [],
  requestSize: 0,
  statusCode: 200,
  statusMessage: 'OK',
  responseHeaders: const [HttpHeader('Content-Type', 'text/plain')],
  responseSize: 0,
  isHTTPS: true,
  isMITMDecrypted: true,
  state: ExchangeState.completed,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeProxyChannel channel;
  late ProviderContainer container;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('har_export_controller');
    channel = _FakeProxyChannel();
    container = ProviderContainer(
      overrides: [proxyChannelProvider.overrideWithValue(channel)],
    );
  });

  tearDown(() async {
    container.dispose();
    await channel.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('exports every exchange of the given list', () async {
    final path = '${tempDir.path}/all.har';
    final count = await container
        .read(harExportControllerProvider)
        .export(
          path: path,
          exchanges: [
            buildExchange(id: 'a', url: 'https://alpha.test/one'),
            buildExchange(id: 'b', url: 'https://beta.test/two'),
          ],
        );

    expect(count, 2);
    final har = jsonDecode(File(path).readAsStringSync()) as Map;
    final log = har['log'] as Map;
    expect(log['creator']['version'], '0.3.0+1');
    expect(log['entries'], hasLength(2));
  });

  test('exports exactly the subset it is given (filtered case)', () async {
    final path = '${tempDir.path}/filtered.har';
    final count = await container
        .read(harExportControllerProvider)
        .export(
          path: path,
          exchanges: [buildExchange(id: 'a', url: 'https://alpha.test/one')],
        );

    expect(count, 1);
    final har = jsonDecode(File(path).readAsStringSync()) as Map;
    final entries = (har['log'] as Map)['entries'] as List;
    expect(entries, hasLength(1));
    expect((entries.single as Map)['request']['url'], contains('alpha.test'));
  });

  test('resolves bodies through the channel and decodes them', () async {
    channel.bodies['res'] = Uint8List.fromList([1, 2, 3]);
    final exchange = buildExchange(id: 'a', url: 'https://alpha.test/one');
    exchange.responseBodyRef = 'res';
    exchange.responseSize = 3;
    exchange.responseHeaders = const [
      HttpHeader('Content-Type', 'text/plain'),
      HttpHeader('Content-Encoding', 'gzip'),
    ];

    final path = '${tempDir.path}/bodies.har';
    await container
        .read(harExportControllerProvider)
        .export(path: path, exchanges: [exchange]);

    final har = jsonDecode(File(path).readAsStringSync()) as Map;
    final entry = ((har['log'] as Map)['entries'] as List).single as Map;
    expect(entry['response']['content']['text'], 'len:3');
  });

  test(
    'ignores the decompressed display cache and uses raw store bytes',
    () async {
      channel.bodies['res'] = Uint8List.fromList([1, 2, 3]);
      final exchange = buildExchange(id: 'a', url: 'https://alpha.test/one');
      exchange.responseBodyRef = 'res';
      exchange.responseSize = 3;
      exchange.responseHeaders = const [
        HttpHeader('Content-Type', 'text/plain'),
        HttpHeader('Content-Encoding', 'gzip'),
      ];
      // The Body tab caches decompressed bytes for rendering; they must not be
      // fed to the exporter (it would decompress them a second time).
      exchange.setCachedResponseBody(
        Uint8List.fromList(utf8.encode('a much longer decompressed body')),
      );

      final path = '${tempDir.path}/cache.har';
      await container
          .read(harExportControllerProvider)
          .export(path: path, exchanges: [exchange]);

      final har = jsonDecode(File(path).readAsStringSync()) as Map;
      final entry = ((har['log'] as Map)['entries'] as List).single as Map;
      // The fake decompressor echoes the input length: 3 proves the raw store
      // bytes were used, not the longer cached display bytes.
      expect(entry['response']['content']['text'], 'len:3');
    },
  );

  group('harExportSelection', () {
    final all = [
      buildExchange(id: 'a', url: 'https://alpha.test/one'),
      buildExchange(id: 'b', url: 'https://beta.test/two'),
    ];
    final filtered = [all.first];

    test('all returns the full list', () {
      expect(
        harExportSelection(
          scope: HarExportScope.all,
          all: all,
          filtered: filtered,
        ),
        all,
      );
    });

    test('filtered returns only the matching subset', () {
      expect(
        harExportSelection(
          scope: HarExportScope.filtered,
          all: all,
          filtered: filtered,
        ),
        filtered,
      );
    });
  });
}
