import 'captured_exchange.dart';

/// Notifica di risposta sospesa a un breakpoint (core → UI).
class ResponseBreakpoint {
  final String id;
  final String exchangeId;
  final String method;
  final String url;
  final int statusCode;
  final String? statusMessage;
  final List<HttpHeader> headers;
  final String? body;
  final DateTime timestamp;

  const ResponseBreakpoint({
    required this.id,
    required this.exchangeId,
    required this.method,
    required this.url,
    required this.statusCode,
    this.statusMessage,
    required this.headers,
    this.body,
    required this.timestamp,
  });

  /// Host estratto dall'URL (per il titolo del dialog).
  String get host => Uri.tryParse(url)?.host ?? url;

  factory ResponseBreakpoint.fromMap(Map<Object?, Object?> raw) {
    final map = Map<String, dynamic>.from(raw);
    return ResponseBreakpoint(
      id: map['id'] as String,
      exchangeId: map['exchangeId'] as String,
      method: map['method'] as String,
      url: map['url'] as String,
      statusCode: map['statusCode'] as int,
      statusMessage: map['statusMessage'] as String?,
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
