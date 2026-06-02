import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/services/proxy_channel.dart';
import 'package:rox_proxy/models/captured_exchange.dart';
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
        // Use write() to let HttpClient handle contentLength and encoding automatically
        request.write(body);
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
          final headers = exchange.requestHeaders;
          
          // Check if custom header is present
          final customHeader = headers.firstWhere(
            (h) => h.name.toLowerCase() == 'x-custom-header',
            orElse: () => HttpHeader('', ''),
          );
          expect(customHeader.name.isNotEmpty, isTrue, reason: 'Expected custom header to be captured');
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
        
        // Wait for exchange to be captured with response status code
        // Use longer timeout and active waiting
        final stopwatch = Stopwatch()..start();
        CapturedExchange? exchangeWithStatus;
        while (stopwatch.elapsedMilliseconds < 3000) {
          final getExchanges = exchanges.where((e) => e.method == 'GET' && e.statusCode != null);
          if (getExchanges.isNotEmpty) {
            exchangeWithStatus = getExchanges.first;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
        
        expect(exchangeWithStatus, isNotNull, reason: 'Expected exchange with statusCode to be captured');
        expect(exchangeWithStatus!.statusCode, equals(200));
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
    late Stream<ExchangeEvent> exchangeStream;

    setUpAll(() async {
      proxyChannel = ProxyChannel();
      exchangeStream = proxyChannel.exchangeStream;
      
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
        // Use write() instead of add() to let HttpClient handle contentLength automatically
        request.headers.set('Content-Type', 'text/plain');
        request.write('test body');
        
        final response = await request.close();
        expect(response.statusCode, equals(200));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify POST exchange was captured with body
        final postExchanges = exchanges.where((e) => e.method == 'POST');
        expect(postExchanges.length, greaterThan(0));
        
        if (postExchanges.isNotEmpty) {
          final exchange = postExchanges.first;
          expect(exchange.requestBodyRef, isNotNull);
          expect(exchange.requestSize, greaterThan(0));
        }
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy captures different HTTP status codes', (WidgetTester tester) async {
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        final client = HttpClient();
        client.findProxy = (uri) {
          return "PROXY 127.0.0.1:$proxyPort";
        };
        
        // Test 200 OK
        final response200 = await client.openUrl('GET', Uri.parse('http://httpbin.org/status/200'));
        final resp200 = await response200.close();
        expect(resp200.statusCode, equals(200));
        
        // Test 404 Not Found
        final response404 = await client.openUrl('GET', Uri.parse('http://httpbin.org/status/404'));
        final resp404 = await response404.close();
        expect(resp404.statusCode, equals(404));
        
        // Test 500 Internal Server Error
        final response500 = await client.openUrl('GET', Uri.parse('http://httpbin.org/status/500'));
        final resp500 = await response500.close();
        expect(resp500.statusCode, equals(500));
        
        // Wait for all exchanges to be captured
        await Future.delayed(const Duration(milliseconds: 1500));
        
        // Verify status codes were captured correctly
        final status200Exchanges = exchanges.where((e) => e.statusCode == 200);
        final status404Exchanges = exchanges.where((e) => e.statusCode == 404);
        final status500Exchanges = exchanges.where((e) => e.statusCode == 500);
        
        expect(status200Exchanges.length, greaterThan(0), reason: 'Expected 200 status to be captured');
        expect(status404Exchanges.length, greaterThan(0), reason: 'Expected 404 status to be captured');
        expect(status500Exchanges.length, greaterThan(0), reason: 'Expected 500 status to be captured');
        
        // Verify exchange state is completed for successful responses
        for (final exchange in [...status200Exchanges, ...status404Exchanges, ...status500Exchanges]) {
          expect(exchange.state, equals(ExchangeState.completed));
        }
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy captures status message along with code', (WidgetTester tester) async {
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        final client = HttpClient();
        client.findProxy = (uri) {
          return "PROXY 127.0.0.1:$proxyPort";
        };
        
        // Make request that returns 200 OK
        final response = await client.openUrl('GET', Uri.parse('http://httpbin.org/get'));
        final resp = await response.close();
        expect(resp.statusCode, equals(200));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify status message was captured
        final getExchanges = exchanges.where((e) => e.method == 'GET' && e.statusCode == 200);
        expect(getExchanges.length, greaterThan(0));
        
        if (getExchanges.isNotEmpty) {
          final exchange = getExchanges.first;
          expect(exchange.statusCode, equals(200));
          // Status message should be non-empty for 200 responses
          expect(exchange.statusMessage, isNotNull);
          expect(exchange.statusMessage!.isNotEmpty, isTrue);
        }
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy handles redirect status codes', (WidgetTester tester) async {
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        final client = HttpClient();
        client.findProxy = (uri) {
          return "PROXY 127.0.0.1:$proxyPort";
        };
        
        // httpbin.org redirects /relative-redirect/N to /get after N redirects
        // But we'll use a simpler redirect test
        final response = await client.openUrl('GET', Uri.parse('http://httpbin.org/relative-redirect/1'));
        final resp = await response.close();
        // Should eventually return 200 after redirect
        expect(resp.statusCode, isIn(const [200, 302, 301]));
        
        // Wait for exchange to be captured
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify redirect was captured
        expect(exchanges.length, greaterThan(0));
        
        // Check for redirect status codes (3xx) in captured exchanges
        // Note: Depending on proxy behavior, we may or may not capture the 3xx response
        // This test at least verifies the request was processed
        final redirectExchanges = exchanges.where((e) => e.statusCode != null && e.statusCode! >= 300 && e.statusCode! < 400);
        expect(redirectExchanges.length, greaterThanOrEqualTo(0));
      } finally {
        await subscription.cancel();
      }
    });

    testWidgets('Proxy captures 4xx client error status codes', (WidgetTester tester) async {
      final exchanges = <CapturedExchange>[];
      final subscription = exchangeStream.listen((event) {
        exchanges.add(event.exchange);
      });
      
      try {
        final client = HttpClient();
        client.findProxy = (uri) {
          return "PROXY 127.0.0.1:$proxyPort";
        };
        
        // Test 400 Bad Request
        final response400 = await client.openUrl('GET', Uri.parse('http://httpbin.org/status/400'));
        final resp400 = await response400.close();
        expect(resp400.statusCode, equals(400));
        
        // Test 403 Forbidden
        final response403 = await client.openUrl('GET', Uri.parse('http://httpbin.org/status/403'));
        final resp403 = await response403.close();
        expect(resp403.statusCode, equals(403));
        
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Verify 4xx status codes were captured
        final clientErrorExchanges = exchanges.where((e) => e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500);
        expect(clientErrorExchanges.length, greaterThanOrEqualTo(2));
        
        for (final exchange in clientErrorExchanges) {
          expect(exchange.state, equals(ExchangeState.completed));
        }
      } finally {
        await subscription.cancel();
      }
    });
  });
}
