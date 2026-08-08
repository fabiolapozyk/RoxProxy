import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/services/proxy_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const controlChannel = MethodChannel('com.roxproxy/control');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, null);
  });

  group('Certificate Tests', () {
    late ProxyChannel proxyChannel;

    setUp(() {
      proxyChannel = ProxyChannel();
    });

    test('installCACertificate should return true on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'installCACertificate');
        return {'trusted': true};
      });

      final result = await proxyChannel.installCACertificate();
      expect(result, isTrue);
    });

    test('installCACertificate should return false when untrusted', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async => null);

      final result = await proxyChannel.installCACertificate();
      expect(result, isFalse);
    });

    test('checkCATrust should return the trust boolean', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'checkCATrust');
        return {'trusted': true};
      });

      final result = await proxyChannel.checkCATrust();
      expect(result, isTrue);
    });

    test('getCAStatus should return a valid CaStatus object', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async {
        expect(call.method, 'getCAStatus');
        return {'initialized': true, 'trusted': true};
      });

      final result = await proxyChannel.getCAStatus();
      expect(result, isA<CaStatus>());
      expect(result.initialized, isTrue);
      expect(result.trusted, isTrue);
    });

    test('getCAStatus should default to uninitialized/untrusted', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (call) async => null);

      final result = await proxyChannel.getCAStatus();
      expect(result.initialized, isFalse);
      expect(result.trusted, isFalse);
    });
  });
}
