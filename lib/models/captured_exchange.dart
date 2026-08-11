import 'dart:typed_data';

class HttpHeader {
  final String name;
  final String value;
  const HttpHeader(this.name, this.value);
}

enum ExchangeState { inProgress, completed, failed }

class CapturedExchange {
  final String id;
  final DateTime startTime;
  DateTime? endTime;
  String method;
  String url;
  final String scheme;
  final String host;
  final int port;
  String path;
  List<HttpHeader> requestHeaders;
  String? requestBodyRef;
  final int requestSize;
  int? statusCode;
  String? statusMessage;
  List<HttpHeader>? responseHeaders;
  String? responseBodyRef;
  int? responseSize;
  final bool isHTTPS;
  final bool isMITMDecrypted;
  final bool isMapLocal;
  final bool isBreakpoint;
  ExchangeState state;
  String? errorMessage;

  // Lazily fetched body bytes (cached after first fetch)
  Uint8List? _cachedRequestBody;
  Uint8List? _cachedResponseBody;

  Uint8List? get cachedRequestBody => _cachedRequestBody;
  Uint8List? get cachedResponseBody => _cachedResponseBody;
  void setCachedRequestBody(Uint8List data) => _cachedRequestBody = data;
  void setCachedResponseBody(Uint8List data) => _cachedResponseBody = data;

  Duration? get duration => endTime?.difference(startTime);

  CapturedExchange({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.method,
    required this.url,
    required this.scheme,
    required this.host,
    required this.port,
    required this.path,
    required this.requestHeaders,
    this.requestBodyRef,
    required this.requestSize,
    this.statusCode,
    this.statusMessage,
    this.responseHeaders,
    this.responseBodyRef,
    this.responseSize,
    required this.isHTTPS,
    required this.isMITMDecrypted,
    this.isMapLocal = false,
    this.isBreakpoint = false,
    this.state = ExchangeState.inProgress,
    this.errorMessage,
  });

  factory CapturedExchange.fromMap(Map<Object?, Object?> raw) {
    final map = Map<String, dynamic>.from(raw);
    return CapturedExchange(
      id: map['id'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(
        (map['startTime'] as num).toInt(),
      ),
      endTime: map['endTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['endTime'] as num).toInt())
          : null,
      method: map['method'] as String,
      url: map['url'] as String,
      scheme: map['scheme'] as String,
      host: map['host'] as String,
      port: map['port'] as int,
      path: map['path'] as String,
      requestHeaders: _parseHeaders(map['requestHeaders']),
      requestBodyRef: map['requestBodyRef'] as String?,
      requestSize: map['requestSize'] as int,
      statusCode: map['statusCode'] as int?,
      statusMessage: map['statusMessage'] as String?,
      responseHeaders: map['responseHeaders'] != null
          ? _parseHeaders(map['responseHeaders'])
          : null,
      responseBodyRef: map['responseBodyRef'] as String?,
      responseSize: map['responseSize'] as int?,
      isHTTPS: map['isHTTPS'] as bool,
      isMITMDecrypted: map['isMITMDecrypted'] as bool,
      isMapLocal: map['isMapLocal'] as bool? ?? false,
      isBreakpoint: map['isBreakpoint'] as bool? ?? false,
      state: _parseState(map['state'] as String),
      errorMessage: map['errorMessage'] as String?,
    );
  }

  /// Merges updated fields from a channel "update" event into this exchange.
  void applyUpdate(CapturedExchange updated) {
    // La richiesta può essere stata modificata al breakpoint (RF4): metodo,
    // URL, path e header vengono recepiti così come inviati dal core.
    method = updated.method;
    url = updated.url;
    path = updated.path;
    requestHeaders = updated.requestHeaders;
    endTime = updated.endTime;
    statusCode = updated.statusCode;
    statusMessage = updated.statusMessage;
    responseHeaders = updated.responseHeaders;
    responseSize = updated.responseSize;
    state = updated.state;
    errorMessage = updated.errorMessage;
    // Update body ref and invalidate cached bytes so BodyTab re-fetches.
    if (updated.responseBodyRef != null) {
      responseBodyRef = updated.responseBodyRef;
      _cachedResponseBody = null;
    }
    if (updated.requestBodyRef != null) {
      requestBodyRef = updated.requestBodyRef;
      _cachedRequestBody = null;
    }
  }

  static List<HttpHeader> _parseHeaders(dynamic raw) {
    if (raw == null) return [];
    final list = raw as List<dynamic>;
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return HttpHeader(m['name'] as String, m['value'] as String);
    }).toList();
  }

  static ExchangeState _parseState(String s) => switch (s) {
    'completed' => ExchangeState.completed,
    'failed' => ExchangeState.failed,
    _ => ExchangeState.inProgress,
  };
}
