import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_rule.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/models/domain_rule.dart';
import 'package:rox_proxy/models/map_local_rule.dart';
import 'package:rox_proxy/providers/exchange_provider.dart';
import 'package:rox_proxy/providers/proxy_channel_provider.dart';
import 'package:rox_proxy/providers/session_provider.dart';
import 'package:rox_proxy/services/har_exporter.dart';
import 'package:rox_proxy/services/har_importer.dart';
import 'package:rox_proxy/services/proxy_channel.dart';
import 'package:rox_proxy/ui/offline/offline_session_view.dart';

class _FakeProxyChannel extends ProxyChannel {
  final Map<String, Uint8List> bodies = {};
  final List<String> released = [];
  final _events = StreamController<ExchangeEvent>.broadcast();

  int storeCalls = 0;
  int releaseAllCalls = 0;

  @override
  Stream<ExchangeEvent> get exchangeStream => _events.stream;

  void emit(ExchangeEvent event) => _events.add(event);

  @override
  Future<Uint8List?> fetchBody(String ref) async => bodies[ref];

  @override
  Future<String?> storeBody(Uint8List data) async {
    final ref = 'imported-${++storeCalls}';
    bodies[ref] = data;
    return ref;
  }

  @override
  Future<void> releaseBody(String ref) async {
    released.add(ref);
    bodies.remove(ref);
  }

  @override
  Future<void> releaseAllBodies() async {
    releaseAllCalls++;
    bodies.clear();
  }

  @override
  Future<String?> getAppVersion() async => '9.9.9+9';

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

CapturedExchange buildExchange({required String id, required String url}) =>
    CapturedExchange(
      id: id,
      startTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      endTime: DateTime.fromMillisecondsSinceEpoch(1700000000100),
      method: 'GET',
      url: url,
      scheme: 'https',
      host: Uri.parse(url).host,
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

Future<String> writeHar(
  Directory dir,
  String name, {
  required List<CapturedExchange> exchanges,
  bool withBody = true,
}) async {
  final bodies = <String, Uint8List>{};
  for (final exchange in exchanges) {
    if (!withBody) continue;
    exchange.responseBodyRef = 'ref-${exchange.id}';
    exchange.responseSize = 2;
    bodies['ref-${exchange.id}'] = Uint8List.fromList([1, 2]);
  }
  final har = await const HarExporter().build(
    exchanges: exchanges,
    readBody: (ref) async => bodies[ref],
    decompress: (data, encoding) async => null,
    creatorVersion: '9.9.9+9',
  );
  final path = '${dir.path}/$name';
  await File(path).writeAsString(jsonEncode(har));
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeProxyChannel channel;
  late ProviderContainer container;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('offline_session');
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

  test(
    'open imports the HAR, stores its bodies and shows the session',
    () async {
      final path = await writeHar(
        tempDir,
        'session.har',
        exchanges: [
          buildExchange(id: 'ex-1', url: 'https://alpha.test/one'),
          buildExchange(id: 'ex-2', url: 'https://beta.test/two'),
        ],
      );

      final count = await container
          .read(offlineSessionProvider.notifier)
          .open(path);

      expect(count, 2);
      final session = container.read(offlineSessionProvider);
      expect(session, isNotNull);
      expect(session!.fileName, 'session.har');
      expect(session.exchanges, hasLength(2));
      expect(channel.storeCalls, 2);
      for (final exchange in session.exchanges) {
        expect(exchange.responseBodyRef, isNotNull);
        expect(channel.bodies[exchange.responseBodyRef!], isNotNull);
      }
    },
  );

  test('filter and selection operate on the session only', () async {
    final path = await writeHar(
      tempDir,
      'session.har',
      exchanges: [
        buildExchange(id: 'ex-1', url: 'https://alpha.test/one'),
        buildExchange(id: 'ex-2', url: 'https://beta.test/two'),
      ],
    );
    final notifier = container.read(offlineSessionProvider.notifier);
    await notifier.open(path);

    notifier.setFilter('alpha');
    expect(container.read(offlineSessionProvider)!.filtered, hasLength(1));

    notifier.select('ex-2');
    expect(container.read(offlineSessionProvider)!.selected!.id, 'ex-2');
  });

  test('the live capture keeps running while a session is open', () async {
    // Make sure the live notifier is subscribed before traffic arrives.
    container.read(exchangeListProvider.notifier);
    channel.emit(
      ExchangeEvent(
        'new',
        buildExchange(id: 'live-1', url: 'https://live.test/1'),
      ),
    );
    await pumpEventQueue();
    expect(container.read(exchangeListProvider), hasLength(1));

    final path = await writeHar(
      tempDir,
      'session.har',
      exchanges: [buildExchange(id: 'ex-1', url: 'https://alpha.test/one')],
    );
    await container.read(offlineSessionProvider.notifier).open(path);

    // The proxy was never stopped and new traffic keeps being captured.
    channel.emit(
      ExchangeEvent(
        'new',
        buildExchange(id: 'live-2', url: 'https://live.test/2'),
      ),
    );
    await pumpEventQueue();
    expect(container.read(exchangeListProvider), hasLength(2));
    expect(container.read(exchangeListProvider).last.id, 'live-2');

    await container.read(offlineSessionProvider.notifier).close();
    expect(container.read(exchangeListProvider), hasLength(2));
  });

  test('close releases only the session bodies, not the live ones', () async {
    final path = await writeHar(
      tempDir,
      'session.har',
      exchanges: [buildExchange(id: 'ex-1', url: 'https://alpha.test/one')],
    );
    final notifier = container.read(offlineSessionProvider.notifier);
    await notifier.open(path);
    final refs = container.read(offlineSessionProvider)!.bodyRefs;
    expect(refs, isNotEmpty);

    await notifier.close();

    expect(container.read(offlineSessionProvider), isNull);
    expect(channel.released, refs);
    // releaseAllBodies would also wipe live bodies: it must not be used here.
    expect(channel.releaseAllCalls, 0);
  });

  test('opening another session releases the previous one', () async {
    final first = await writeHar(
      tempDir,
      'first.har',
      exchanges: [buildExchange(id: 'ex-1', url: 'https://alpha.test/one')],
    );
    final second = await writeHar(
      tempDir,
      'second.har',
      exchanges: [buildExchange(id: 'ex-2', url: 'https://beta.test/two')],
    );

    final notifier = container.read(offlineSessionProvider.notifier);
    await notifier.open(first);
    final firstRefs = container.read(offlineSessionProvider)!.bodyRefs;

    await notifier.open(second);

    expect(channel.released, containsAll(firstRefs));
    expect(container.read(offlineSessionProvider)!.fileName, 'second.har');
    expect(container.read(offlineSessionProvider)!.exchanges.single.id, 'ex-2');
  });

  test('a malformed file throws and leaves the session closed', () async {
    final path = '${tempDir.path}/broken.har';
    await File(path).writeAsString('not a har');

    await expectLater(
      container.read(offlineSessionProvider.notifier).open(path),
      throwsA(isA<HarFormatException>()),
    );
    expect(container.read(offlineSessionProvider), isNull);
  });

  testWidgets('the offline view shows the banner and returns to live', (
    tester,
  ) async {
    late String path;
    // Real file I/O must run outside the fake-async test zone.
    await tester.runAsync(() async {
      path = await writeHar(
        tempDir,
        'session.har',
        exchanges: [buildExchange(id: 'ex-1', url: 'https://alpha.test/one')],
      );
      await container.read(offlineSessionProvider.notifier).open(path);
    });

    expect(
      container.read(offlineSessionProvider)!.exchanges.single.state,
      ExchangeState.completed,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final session = ref.watch(offlineSessionProvider);
                return session == null
                    ? const Text('live')
                    : OfflineSessionView(session: session);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Offline session (read-only)'), findsOneWidget);
    expect(find.textContaining('session.har'), findsOneWidget);
    expect(find.text('alpha.test'), findsOneWidget);

    await tester.tap(find.text('Back to live'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('live'), findsOneWidget);
    expect(container.read(offlineSessionProvider), isNull);
  });
}
