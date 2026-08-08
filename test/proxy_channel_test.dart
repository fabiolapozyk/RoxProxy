import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/domain_rule.dart';
import 'package:rox_proxy/models/map_local_rule.dart';
import 'package:rox_proxy/services/proxy_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const controlChannel = MethodChannel('com.roxproxy/control');
  const exchangesChannel = EventChannel('com.roxproxy/exchanges');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(exchangesChannel, null);
  });

  group('ProxyChannel Tests', () {
    late ProxyChannel proxyChannel;

    setUp(() {
      proxyChannel = ProxyChannel();
    });

    test('startProxy should return the port on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'startProxy');
        expect((call.arguments as Map)['port'], 8888);
        expect((call.arguments as Map)['connectionTimeoutSeconds'], 30);
        expect((call.arguments as Map)['setSystemProxy'], false);
        expect((call.arguments as Map)['httpsInterceptionEnabled'], true);
        expect((call.arguments as Map)['domainRules'], isA<List>());
        return {'port': 8888};
      });

      final result = await proxyChannel.startProxy(
        port: 8888,
        domainRules: [DomainRule(domain: 'example.com')],
        connectionTimeoutSeconds: 30,
        setSystemProxy: false,
        httpsInterceptionEnabled: true,
      );
      expect(result, 8888);
    });

    test('startProxy should forward Map Local rules', () async {
      Map<String, dynamic>? capturedArgs;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'startProxy');
        capturedArgs = Map<String, dynamic>.from(call.arguments as Map);
        return {'port': 8080};
      });

      await proxyChannel.startProxy(
        port: 8080,
        domainRules: const [],
        connectionTimeoutSeconds: 30,
        setSystemProxy: true,
        httpsInterceptionEnabled: true,
        mapLocalRules: [
          MapLocalRule(
            hostPattern: '*.example.com',
            pathPattern: '/api/**',
            httpMethod: 'GET',
            filePath: '/tmp/mock.json',
            statusCode: 201,
            contentType: 'application/json',
            customHeaders: {'X-Mock': '1'},
            isEnabled: false,
            isCaseSensitive: false,
            useRegex: true,
          ),
        ],
      );

      final rules = capturedArgs!['mapLocalRules'] as List;
      expect(rules.length, 1);
      final rule = Map<String, dynamic>.from(rules.single as Map);
      expect(rule['hostPattern'], '*.example.com');
      expect(rule['pathPattern'], '/api/**');
      expect(rule['httpMethod'], 'GET');
      expect(rule['filePath'], '/tmp/mock.json');
      expect(rule['statusCode'], 201);
      expect(rule['contentType'], 'application/json');
      expect(rule['customHeaders'], {'X-Mock': '1'});
      expect(rule['isEnabled'], isFalse);
      expect(rule['isCaseSensitive'], isFalse);
      expect(rule['useRegex'], isTrue);
      expect(rule['id'], isNotEmpty);
    });

    test('startProxy defaults to no Map Local rules', () async {
      Map<String, dynamic>? capturedArgs;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        capturedArgs = Map<String, dynamic>.from(call.arguments as Map);
        return {'port': 8080};
      });

      await proxyChannel.startProxy(
        port: 8080,
        domainRules: const [],
        connectionTimeoutSeconds: 30,
        setSystemProxy: true,
        httpsInterceptionEnabled: true,
      );
      expect(capturedArgs!['mapLocalRules'], isEmpty);
    });

    test('startProxy should fall back to the requested port', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async => null);

      final result = await proxyChannel.startProxy(
        port: 9999,
        domainRules: const [],
        connectionTimeoutSeconds: 15,
        setSystemProxy: true,
        httpsInterceptionEnabled: false,
      );
      expect(result, 9999);
    });

    test('stopProxy should invoke the channel', () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'stopProxy');
        called = true;
        return null;
      });

      await proxyChannel.stopProxy();
      expect(called, isTrue);
    });

    test('configureSystemProxy should forward args', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'configureSystemProxy');
        expect((call.arguments as Map)['enabled'], true);
        expect((call.arguments as Map)['port'], 8888);
        return null;
      });

      await proxyChannel.configureSystemProxy(enabled: true, port: 8888);
    });

    test('getProxyState should return the state string', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'getProxyState');
        return {'state': 'running'};
      });

      final result = await proxyChannel.getProxyState();
      expect(result, 'running');
    });

    test('getProxyState should default to stopped', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async => null);

      final result = await proxyChannel.getProxyState();
      expect(result, 'stopped');
    });

    test('fetchBody should return raw bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'fetchBody');
        expect((call.arguments as Map)['ref'], 'body-ref-1');
        return bytes;
      });

      final result = await proxyChannel.fetchBody('body-ref-1');
      expect(result, bytes);
    });

    test('releaseBody should invoke the channel', () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'releaseBody');
        expect((call.arguments as Map)['ref'], 'body-ref-1');
        called = true;
        return null;
      });

      await proxyChannel.releaseBody('body-ref-1');
      expect(called, isTrue);
    });

    test('releaseAllBodies should invoke the channel', () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'releaseAllBodies');
        called = true;
        return null;
      });

      await proxyChannel.releaseAllBodies();
      expect(called, isTrue);
    });

    test('decompressBody should forward data and encoding', () async {
      final compressed = Uint8List.fromList([0x1f, 0x8b, 0x08]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'decompressBody');
        expect((call.arguments as Map)['data'], compressed);
        expect((call.arguments as Map)['encoding'], 'gzip');
        return Uint8List.fromList([72, 105]);
      });

      final result = await proxyChannel.decompressBody(compressed, 'gzip');
      expect(result, Uint8List.fromList([72, 105]));
    });

    test('replayRequest should return the exchange id', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'replayRequest');
        return {'exchangeId': 'exchange-42'};
      });

      final result = await proxyChannel.replayRequest({'url': 'https://a'});
      expect(result, 'exchange-42');
    });

    test('exchangeStream should parse events from the EventChannel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(exchangesChannel, MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success({
            'type': 'new',
            'exchange': {
              'id': 'ex-1',
              'startTime': 1700000000000,
              'method': 'GET',
              'url': 'https://example.com/path',
              'scheme': 'https',
              'host': 'example.com',
              'port': 443,
              'path': '/path',
              'requestHeaders': [
                {'name': 'Host', 'value': 'example.com'},
              ],
              'requestSize': 0,
              'isHTTPS': true,
              'isMITMDecrypted': true,
              'isMapLocal': true,
              'state': 'inProgress',
            },
          });
        },
      ));

      final event = await proxyChannel.exchangeStream.first;
      expect(event.type, 'new');
      expect(event.exchange.id, 'ex-1');
      expect(event.exchange.method, 'GET');
      expect(event.exchange.host, 'example.com');
      expect(event.exchange.isHTTPS, isTrue);
      expect(event.exchange.isMITMDecrypted, isTrue);
      expect(event.exchange.isMapLocal, isTrue);
      expect(event.exchange.requestHeaders.single.name, 'Host');
    });

    test('exchangeStream defaults isMapLocal to false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(exchangesChannel, MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success({
            'type': 'update',
            'exchange': {
              'id': 'ex-2',
              'startTime': 1700000000000,
              'method': 'GET',
              'url': 'http://example.com/',
              'scheme': 'http',
              'host': 'example.com',
              'port': 80,
              'path': '/',
              'requestHeaders': [],
              'requestSize': 0,
              'isHTTPS': false,
              'isMITMDecrypted': false,
              'state': 'completed',
            },
          });
        },
      ));

      final event = await proxyChannel.exchangeStream.first;
      expect(event.exchange.isMapLocal, isFalse);
    });
  });
}
