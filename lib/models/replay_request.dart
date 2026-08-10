import 'captured_exchange.dart';

class ReplayRequest {
  final String originalExchangeId;
  String method;
  String url;
  List<HttpHeader> headers;
  String? body;
  bool followRedirects;

  ReplayRequest({
    required this.originalExchangeId,
    required this.method,
    required this.url,
    required this.headers,
    this.body,
    this.followRedirects = true,
  });

  factory ReplayRequest.fromExchange(CapturedExchange exchange) {
    // Try to get cached body first
    String? body;
    if (exchange.cachedRequestBody != null) {
      body = String.fromCharCodes(exchange.cachedRequestBody!);
    }

    return ReplayRequest(
      originalExchangeId: exchange.id,
      method: exchange.method,
      url: exchange.url,
      headers: List.from(exchange.requestHeaders),
      body: body,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'originalExchangeId': originalExchangeId,
      'method': method,
      'url': url,
      'headers': headers
          .map((h) => {'name': h.name, 'value': h.value})
          .toList(),
      'body': body,
      'followRedirects': followRedirects,
    };
  }
}
