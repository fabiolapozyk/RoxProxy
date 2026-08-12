import 'captured_exchange.dart';

/// Notification of a suspended request (core → UI), RF2.3/RF3.1.
class BreakpointRequest {
  final String id;
  final String exchangeId;
  final String method;
  final String url;
  final List<HttpHeader> headers;
  final String? body;
  final DateTime timestamp;

  const BreakpointRequest({
    required this.id,
    required this.exchangeId,
    required this.method,
    required this.url,
    required this.headers,
    this.body,
    required this.timestamp,
  });

  /// Host estratto dall'URL (per il titolo del dialog).
  String get host => Uri.tryParse(url)?.host ?? url;

  factory BreakpointRequest.fromMap(Map<Object?, Object?> raw) {
    final map = Map<String, dynamic>.from(raw);
    return BreakpointRequest(
      id: map['id'] as String,
      exchangeId: map['exchangeId'] as String,
      method: map['method'] as String,
      url: map['url'] as String,
      headers: _parseHeaders(map['headers']),
      body: map['body'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  static List<HttpHeader> _parseHeaders(dynamic raw) {
    if (raw == null) return [];
    final list = raw as List<dynamic>;
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return HttpHeader(m['name'] as String, m['value'] as String);
    }).toList();
  }
}
