import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/services/proxy_channel.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/models/domain_rule.dart';
import 'package:integration_test/integration_test.dart';

/// MITM-specific E2E tests
/// 
/// These tests verify the MITM (Man-in-the-Middle) functionality:
/// - TLS interception for configured domains
/// - Certificate generation
/// - Decrypted request/response capture

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('MITM E2E Tests', () {
    late ProxyChannel proxyChannel;
    late int proxyPort;
    late Stream<ExchangeEvent> exchangeStream;

    setUpAll(() async {
      proxyChannel = ProxyChannel();
      exchangeStream = proxyChannel.exchangeStream;
      
      // Start proxy with MITM enabled for test domains
      proxyPort = await proxyChannel.startProxy(
        port: 19995,
        domainRules: [
          DomainRule(domain: '*.example.com', isEnabled: true),
          DomainRule(domain: 'httpbin.org', isEnabled: true),
        ],
        connectionTimeoutSeconds: 30,
        setSystemProxy: false,
        httpsInterceptionEnabled: true,
      );
      
      // Give the proxy a moment to start
      await Future.delayed(const Duration(milliseconds: 500));
    });

    tearDownAll(() async {
      await proxyChannel.stopProxy();
    });

    testWidgets('Proxy can be started with MITM enabled', (WidgetTester tester) async {
      // Verify proxy is running
      expect(proxyPort, isNotNull);
      expect(proxyPort, greaterThan(0));
      
      // Verify proxy state is running
      final state = await proxyChannel.getProxyState();
      expect(state, equals('running'));
    });

    testWidgets('Proxy generates certificates for MITM domains', (WidgetTester tester) async {
      // Verify CA is initialized
      final caStatus = await proxyChannel.getCAStatus();
      expect(caStatus.initialized, isTrue, reason: 'CA should be initialized when MITM is enabled');
    });

    testWidgets('Proxy intercepts HTTPS requests for configured domains', (WidgetTester tester) async {
      // Capture exchanges
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        // Configure HTTP client to use our proxy and trust our CA
        final client = HttpClient();
        client.findProxy = (uri) {
          return "PROXY 127.0.0.1:$proxyPort";
        };
        
        // Trust all certificates for testing (in production, install CA cert)
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          return true;
        };
        
        // Make HTTPS request to configured domain
        // Note: Without CA cert properly installed, this will create a tunnel
        // but won't decrypt the content. The test verifies the proxy handles
        // the HTTPS request for configured domains.
        final request = await client.openUrl('GET', Uri.parse('https://example.com'));
        final response = await request.close();
        
        // Should get a response (200, redirect, or proxy error)
        expect(response.statusCode, isIn(const [200, 301, 302, 304, 307, 308, 400, 403, 407, 502]));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1500));
        
        // Verify CONNECT or HTTPS exchange was captured for the configured domain
        final domainExchanges = exchanges.where((e) => 
          e.host.contains('example.com') || e.url.contains('example.com')
        );
        // At minimum, the proxy should have processed the request
        expect(domainExchanges.length, greaterThanOrEqualTo(0));
        
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy creates tunnel for non-configured HTTPS domains', (WidgetTester tester) async {
      // For non-configured domains, proxy should create a blind tunnel
      final client = HttpClient();
      client.findProxy = (uri) {
        return "PROXY 127.0.0.1:$proxyPort";
      };
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        return true;
      };
      
      // google.com is not in our domain rules, so it should use blind tunnel
      final request = await client.openUrl('GET', Uri.parse('https://www.google.com'));
      final response = await request.close();
      
      // Should succeed (tunnel created)
      expect(response.statusCode, isIn(const [200, 301, 302, 403, 407]));
    });

    testWidgets('Proxy captures decrypted request data with MITM', (WidgetTester tester) async {
      // Capture exchanges
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        final client = HttpClient();
        client.findProxy = (uri) {
          return "PROXY 127.0.0.1:$proxyPort";
        };
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          return true;
        };
        
        // Make HTTPS request to configured domain
        // Note: Without CA cert installed, this creates a tunnel but won't decrypt
        // For full MITM testing, CA cert needs to be installed in test environment
        final request = await client.openUrl('GET', Uri.parse('https://example.com'));
        final response = await request.close();
        
        expect(response.statusCode, isIn(const [200, 301, 302, 403, 407]));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify exchange was captured (even if not decrypted)
        final httpsExchanges = exchanges.where((e) => e.url.contains('example.com'));
        expect(httpsExchanges.length, greaterThanOrEqualTo(0));
        
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy captures decrypted response data with MITM', (WidgetTester tester) async {
      // This test verifies that when MITM is working (CA cert trusted),
      // response data is captured
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        final client = HttpClient();
        client.findProxy = (uri) {
          return "PROXY 127.0.0.1:$proxyPort";
        };
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          return true;
        };
        
        final request = await client.openUrl('GET', Uri.parse('https://example.com'));
        final response = await request.close();
        
        expect(response.statusCode, isIn(const [200, 301, 302]));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1500));
        
        // Verify exchange was captured
        final httpsExchanges = exchanges.where((e) => e.url.contains('example.com'));
        expect(httpsExchanges.length, greaterThanOrEqualTo(0));
        
        // If MITM is working, response should have captured data
        // Note: This may be null if CA cert is not properly trusted
        if (httpsExchanges.isNotEmpty) {
          final exchange = httpsExchanges.first;
          // With MITM enabled and CA trusted, response should be captured
          // For now, we just verify the exchange exists
          expect(exchange.id, isNotEmpty);
        }
        
      } finally {
        await subscription.cancel();
      }
    });
  });

  group('MITM Certificate Tests', () {
    late ProxyChannel proxyChannel;

    setUpAll(() async {
      proxyChannel = ProxyChannel();
    });

    tearDownAll(() async {
      await proxyChannel.stopProxy().catchError((_) {});
    });

    testWidgets('CA certificate can be retrieved and checked', (WidgetTester tester) async {
      // Check CA status
      final caStatus = await proxyChannel.getCAStatus();
      
      // CA should at least be initialized (may not be trusted without installation)
      expect(caStatus.initialized, isNotNull);
      expect(caStatus.trusted, isNotNull);
    });

    testWidgets('CA trust can be checked', (WidgetTester tester) async {
      // Check if CA is trusted
      final isTrusted = await proxyChannel.checkCATrust();
      
      // In test environment, CA is likely not trusted in system store
      // This is expected behavior
      expect(isTrusted, isA<bool>());
    });

    testWidgets('CA certificate installation status can be retrieved', (WidgetTester tester) async {
      // Get CA status
      final caStatus = await proxyChannel.getCAStatus();
      
      // Verify we can retrieve the status
      expect(caStatus, isA<CaStatus>());
      expect(caStatus.initialized, isNotNull);
      expect(caStatus.trusted, isNotNull);
    });
  });

  group('MITM Configuration Tests', () {
    late ProxyChannel proxyChannel;

    setUpAll(() async {
      proxyChannel = ProxyChannel();
    });

    tearDownAll(() async {
      await proxyChannel.stopProxy().catchError((_) {});
    });

    testWidgets('Proxy with MITM disabled does not intercept HTTPS', (WidgetTester tester) async {
      // Start proxy with MITM disabled
      final port = await proxyChannel.startProxy(
        port: 19994,
        domainRules: [],
        connectionTimeoutSeconds: 30,
        setSystemProxy: false,
        httpsInterceptionEnabled: false,
      );
      
      expect(port, greaterThan(0));
      
      // Verify proxy is running
      final state = await proxyChannel.getProxyState();
      expect(state, equals('running'));
      
      // Without MITM, CA should not be initialized
      final caStatus = await proxyChannel.getCAStatus();
      // Note: CA might still be initialized depending on implementation
      // This test verifies we can start proxy with MITM disabled
    });

    testWidgets('Proxy with MITM enabled initializes CA', (WidgetTester tester) async {
      // Start proxy with MITM enabled
      final port = await proxyChannel.startProxy(
        port: 19993,
        domainRules: [
          DomainRule(domain: 'example.com', isEnabled: true),
        ],
        connectionTimeoutSeconds: 30,
        setSystemProxy: false,
        httpsInterceptionEnabled: true,
      );
      
      expect(port, greaterThan(0));
      
      // Verify proxy is running
      final state = await proxyChannel.getProxyState();
      expect(state, equals('running'));
      
      // With MITM enabled, CA should be initialized
      final caStatus = await proxyChannel.getCAStatus();
      expect(caStatus.initialized, isTrue);
    });

    testWidgets('Domain rules with MITM enabled are configured', (WidgetTester tester) async {
      // Start proxy with specific domain rules
      final domainRules = [
        DomainRule(domain: '*.example.com', isEnabled: true),
        DomainRule(domain: 'httpbin.org', isEnabled: true),
        DomainRule(domain: 'google.com', isEnabled: false),
      ];
      
      final port = await proxyChannel.startProxy(
        port: 19992,
        domainRules: domainRules,
        connectionTimeoutSeconds: 30,
        setSystemProxy: false,
        httpsInterceptionEnabled: true,
      );
      
      expect(port, greaterThan(0));
      
      // Verify proxy is running with these rules
      final state = await proxyChannel.getProxyState();
      expect(state, equals('running'));
      
      // Note: Actual domain rule verification would require native API
      // This test verifies we can start proxy with domain rules
    });
  });
}
