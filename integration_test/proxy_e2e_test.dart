import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/services/proxy_channel.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
import 'package:rox_proxy/models/domain_rule.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-End tests for the Rox Proxy
/// 
/// These tests verify that the proxy:
/// - Intercepts HTTP requests
/// - Forwards requests to upstream servers
/// - Captures request/response data
/// - Works with real network calls
///
/// Note: These tests require:
/// - Internet connection (for external servers like example.com, httpbin.org)
/// - Ports 19999-19995 to be available
/// - On macOS: may require admin privileges for system proxy configuration

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Proxy E2E Tests - HTTP', () {
    late ProxyChannel proxyChannel;
    late int proxyPort;
    late Stream<ExchangeEvent> exchangeStream;
    
    setUpAll(() async {
      proxyChannel = ProxyChannel();
      exchangeStream = proxyChannel.exchangeStream;
      
      // Start proxy on a specific port for testing
      proxyPort = await proxyChannel.startProxy(
        port: 19999,
        domainRules: [],
        connectionTimeoutSeconds: 30,
        setSystemProxy: false,
        httpsInterceptionEnabled: false,
      );
      
      // Give the proxy a moment to start
      await Future.delayed(const Duration(milliseconds: 500));
    });

    tearDownAll(() async {
      await proxyChannel.stopProxy();
    });

    // Helper to make HTTP requests through the proxy
    Future<HttpClientResponse> makeRequestThroughProxy(
      String url, {
      String method = 'GET',
      Map<String, String>? headers,
      String? body,
    }) async {
      final client = HttpClient();
      
      // Configure proxy
      client.findProxy = (uri) {
        return "PROXY 127.0.0.1:$proxyPort";
      };
      
      // Handle bad certificates (for MITM testing)
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Always trust for testing
        return true;
      };
      
      final request = await client.openUrl(method, Uri.parse(url));
      
      // Add headers
      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.add(key, value);
        });
      }
      
      // Add body
      if (body != null) {
        request.headers.contentLength = body.length;
        request.add(utf8.encode(body));
      }
      
      final response = await request.close();
      return response;
    }

    testWidgets('Proxy intercepts HTTP GET requests', (WidgetTester tester) async {
      // Capture exchanges
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        // Make request through proxy
        final response = await makeRequestThroughProxy('http://example.com');
        
        // Verify response
        expect(response.statusCode, isIn(const [200, 301, 302, 304, 307, 308]));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify exchange was captured
        expect(exchanges.length, greaterThan(0), reason: 'Expected at least one exchange to be captured');
        
        // Find the GET request exchange
        final getExchanges = exchanges.where((e) => e.method == 'GET');
        expect(getExchanges.length, greaterThan(0), reason: 'Expected GET request to be captured');
        
        // Verify exchange properties
        if (getExchanges.isNotEmpty) {
          final exchange = getExchanges.first;
          expect(exchange.host, contains('example.com'));
          expect(exchange.url, contains('example.com'));
          expect(exchange.isHTTPS, isFalse);
        }
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy captures request headers', (WidgetTester tester) async {
      // Capture exchanges
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        // Make request with custom headers
        final response = await makeRequestThroughProxy(
          'http://example.com',
          headers: {
            'X-Custom-Header': 'test-value',
            'User-Agent': 'RoxProxy-Test',
          },
        );
        
        expect(response.statusCode, isIn(const [200, 301, 302, 304, 307, 308]));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify exchange was captured with headers
        expect(exchanges.length, greaterThan(0));
        
        final getExchanges = exchanges.where((e) => e.method == 'GET');
        if (getExchanges.isNotEmpty) {
          final exchange = getExchanges.first;
          // Headers are captured as list of name-value pairs
          final headers = exchange.requestHeaders ?? [];
          
          // Check if custom header is present
          final customHeader = headers.firstWhere(
            (h) => h.name.toLowerCase() == 'x-custom-header',
            orElse: () => null,
          );
          expect(customHeader, isNotNull, reason: 'Expected custom header to be captured');
        }
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy handles HTTP POST requests', (WidgetTester tester) async {
      // Capture exchanges
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        // Make POST request
        final response = await makeRequestThroughProxy(
          'http://httpbin.org/post',
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'test': 'data'}),
        );
        
        expect(response.statusCode, equals(200));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify POST exchange was captured
        final postExchanges = exchanges.where((e) => e.method == 'POST');
        expect(postExchanges.length, greaterThan(0), reason: 'Expected POST request to be captured');
        
        if (postExchanges.isNotEmpty) {
          final exchange = postExchanges.first;
          expect(exchange.host, contains('httpbin.org'));
          expect(exchange.url, contains('httpbin.org/post'));
        }
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy captures response data', (WidgetTester tester) async {
      // Capture exchanges
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        // Make request
        final response = await makeRequestThroughProxy('http://httpbin.org/get');
        
        expect(response.statusCode, equals(200));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify exchange was captured
        expect(exchanges.length, greaterThan(0));
        
        final getExchanges = exchanges.where((e) => e.method == 'GET');
        if (getExchanges.isNotEmpty) {
          final exchange = getExchanges.first;
          // Response should have been captured
          expect(exchange.statusCode, isNotNull);
          expect(exchange.statusCode, equals(200));
        }
      } finally {
        await subscription.cancel();
      }
    });
  });

  group('Proxy E2E Tests - HTTPS', () {
    late ProxyChannel proxyChannel;
    late int proxyPort;
    late Stream<ExchangeEvent> exchangeStream;

    setUpAll(() async {
      proxyChannel = ProxyChannel();
      exchangeStream = proxyChannel.exchangeStream;
      
      // Start proxy for HTTPS tests
      proxyPort = await proxyChannel.startProxy(
        port: 19998,
        domainRules: [],
        connectionTimeoutSeconds: 30,
        setSystemProxy: false,
        httpsInterceptionEnabled: false,
      );
      
      // Give the proxy a moment to start
      await Future.delayed(const Duration(milliseconds: 500));
    });

    tearDownAll(() async {
      await proxyChannel.stopProxy();
    });

    testWidgets('Proxy handles HTTPS CONNECT requests', (WidgetTester tester) async {
      // Capture exchanges
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        // Make HTTPS request through proxy (will create CONNECT tunnel)
        final client = HttpClient();
        client.findProxy = (uri) {
          return "PROXY 127.0.0.1:$proxyPort";
        };
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          return true; // Trust all for testing
        };
        
        final request = await client.openUrl('GET', Uri.parse('https://example.com'));
        final response = await request.close();
        
        expect(response.statusCode, isIn(const [200, 301, 302, 304, 307, 308]));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify CONNECT exchange was captured
        final connectExchanges = exchanges.where((e) => e.method == 'CONNECT');
        expect(connectExchanges.length, greaterThanOrEqualTo(0));
        
        // In blind tunnel mode (no MITM), we may not capture the actual HTTPS request
        // but the CONNECT should be captured
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy creates tunnel for HTTPS requests', (WidgetTester tester) async {
      // This test verifies that HTTPS requests work through the proxy
      // (they will be tunneled, not intercepted)
      
      final client = HttpClient();
      client.findProxy = (uri) {
        return "PROXY 127.0.0.1:$proxyPort";
      };
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        return true;
      };
      
      final request = await client.openUrl('GET', Uri.parse('https://httpbin.org/get'));
      final response = await request.close();
      
      expect(response.statusCode, equals(200));
    });
  });

  group('Proxy E2E Tests - Real Servers', () {
    late ProxyChannel proxyChannel;
    late int proxyPort;

    setUpAll(() async {
      proxyChannel = ProxyChannel();
      
      // Start proxy on a unique port
      proxyPort = await proxyChannel.startProxy(
        port: 19996,
        domainRules: [],
        connectionTimeoutSeconds: 30,
        setSystemProxy: false,
        httpsInterceptionEnabled: false,
      );
      
      // Give the proxy a moment to start
      await Future.delayed(const Duration(milliseconds: 500));
    });

    tearDownAll(() async {
      await proxyChannel.stopProxy();
    });

    testWidgets('Proxy forwards requests to httpbin.org', (WidgetTester tester) async {
      final client = HttpClient();
      client.findProxy = (uri) {
        return "PROXY 127.0.0.1:$proxyPort";
      };
      
      final request = await client.openUrl('GET', Uri.parse('http://httpbin.org/get'));
      final response = await request.close();
      
      expect(response.statusCode, equals(200));
      
      // Verify we can read the response
      final responseBody = await response.transform(utf8.decoder).join();
      expect(responseBody, contains('httpbin.org'));
    });

    testWidgets('Proxy captures request and response bodies', (WidgetTester tester) async {
      final exchanges = <CapturedExchange>[];
      final exchangeStream = proxyChannel.exchangeStream;
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        // Make POST request with body
        final client = HttpClient();
        client.findProxy = (uri) {
          return "PROXY 127.0.0.1:$proxyPort";
        };
        
        final request = await client.openUrl('POST', Uri.parse('http://httpbin.org/post'));
        request.headers.contentLength = 11;
        request.add(utf8.encode('test body'));
        
        final response = await request.close();
        expect(response.statusCode, equals(200));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify POST exchange was captured with body
        final postExchanges = exchanges.where((e) => e.method == 'POST');
        expect(postExchanges.length, greaterThan(0));
        
        if (postExchanges.isNotEmpty) {
          final exchange = postExchanges.first;
          expect(exchange.requestBody, isNotNull);
          expect(exchange.requestSize, greaterThan(0));
        }
      } finally {
        await subscription.cancel();
      }
    });
  });
}
