import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/domain_rule.dart';
import 'package:rox_proxy/models/proxy_settings.dart';

void main() {
  group('ProxySettings JSON', () {
    test('defaults enable auto-scroll of the request list', () {
      expect(ProxySettings().autoScrollRequestList, isTrue);
    });

    test('round-trips autoScrollRequestList', () {
      final settings = ProxySettings(autoScrollRequestList: false);
      final restored = ProxySettings.fromJson(settings.toJson());
      expect(restored.autoScrollRequestList, isFalse);
    });

    test('defaults autoScrollRequestList to true for legacy files', () {
      final legacy = {
        'port': 9090,
        'domainRules': <Object>[],
        'isRecording': true,
        'maxExchanges': 500,
      };
      final restored = ProxySettings.fromJson(legacy);
      expect(restored.autoScrollRequestList, isTrue);
      expect(restored.port, 9090);
      expect(restored.domainRules, isEmpty);
    });

    test('copyWith keeps existing values untouched', () {
      final settings = ProxySettings(
        port: 8081,
        domainRules: [DomainRule(domain: 'example.com')],
        autoScrollRequestList: false,
      );
      final copy = settings.copyWith(autoScrollRequestList: true);
      expect(copy.autoScrollRequestList, isTrue);
      expect(copy.port, 8081);
      expect(copy.domainRules.single.domain, 'example.com');
    });
  });
}
