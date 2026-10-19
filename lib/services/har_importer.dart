import 'dart:convert';
import 'dart:typed_data';

import '../models/captured_exchange.dart';
import '../utils/uuid.dart';

/// Raised when a file is not a readable HAR document.
class HarFormatException implements Exception {
  final String message;
  const HarFormatException(this.message);

  @override
  String toString() => message;
}

/// One HAR entry converted back to the app model, with decoded bodies.
class ImportedExchange {
  final CapturedExchange exchange;
  final Uint8List? requestBody;
  final Uint8List? responseBody;

  const ImportedExchange({
    required this.exchange,
    this.requestBody,
    this.responseBody,
  });
}

/// Parses HAR 1.2 documents into [ImportedExchange]s, so a capture produced by
/// RoxProxy or by any other tool (Chrome, Charles, Proxyman, mitmproxy…) can be
/// reopened offline (issues #10 and #13).
///
/// The parser is deliberately tolerant: standard HAR fields are used when
/// present, with sensible fallbacks for the variations found in the wild.
/// RoxProxy-specific metadata is read from the `_roxProxy` custom field and is
/// optional.
class HarImporter {
  const HarImporter();

  static const String _metaKey = '_roxProxy';

  List<ImportedExchange> parse(String contents) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException catch (e) {
      throw HarFormatException('Invalid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const HarFormatException('The file is not a HAR object');
    }
    final log = decoded['log'];
    if (log is! Map) {
      throw const HarFormatException('Missing "log" object');
    }
    final entries = log['entries'];
    if (entries is! List) {
      throw const HarFormatException('Missing "entries" array');
    }
    return [
      for (final entry in entries)
        if (entry is Map) _entry(Map<String, dynamic>.from(entry)),
    ];
  }

  ImportedExchange _entry(Map<String, dynamic> entry) {
    final request = _map(entry['request']);
    final response = _map(entry['response']);
    final meta = _map(entry[_metaKey]);

    final url = request['url'] as String? ?? '';
    final parsed = Uri.tryParse(url);
    final rawRequestHeaders = _headers(request['headers']);
    final rawResponseHeaders = _headers(response['headers']);

    final scheme = _scheme(parsed, rawRequestHeaders);
    final host = parsed?.host.isNotEmpty == true
        ? parsed!.host
        : _hostHeader(rawRequestHeaders);
    final port = parsed?.hasPort == true
        ? parsed!.port
        : (scheme == 'https' ? 443 : 80);
    final path = parsed == null
        ? '/'
        : (parsed.path.isEmpty ? '/' : parsed.path) +
              (parsed.query.isEmpty ? '' : '?${parsed.query}');

    final startTime =
        DateTime.tryParse(
          entry['startedDateTime'] as String? ?? '',
        )?.toLocal() ??
        DateTime.now();
    final durationMs = (entry['time'] as num?)?.toInt() ?? 0;
    final endTime = durationMs > 0
        ? startTime.add(Duration(milliseconds: durationMs))
        : null;

    final requestBody = _postDataBody(request['postData']);
    final responseBody = _contentBody(response['content']);
    // Foreign HARs sometimes keep `content-encoding` while storing the already
    // decoded text; the body viewer would try to decode it a second time.
    final requestHeaders =
        requestBody != null && !_isBase64Payload(request['postData'])
        ? _stripLengthHeaders(rawRequestHeaders)
        : rawRequestHeaders;
    final responseHeaders =
        responseBody != null && !_isBase64Payload(response['content'])
        ? _stripLengthHeaders(rawResponseHeaders)
        : rawResponseHeaders;

    final status = (response['status'] as num?)?.toInt();
    final statusCode = (status == null || status == 0) ? null : status;
    final error = meta['error'] as String?;
    final state = error != null
        ? ExchangeState.failed
        : (statusCode != null
              ? ExchangeState.completed
              : ExchangeState.inProgress);

    final exchange = CapturedExchange(
      id: meta['id'] as String? ?? UUID.v4(),
      startTime: startTime,
      endTime: endTime,
      method: request['method'] as String? ?? 'GET',
      url: url,
      scheme: scheme,
      host: host,
      port: port,
      path: path,
      requestHeaders: requestHeaders,
      requestSize: _size(request['bodySize'], requestBody?.length ?? 0),
      statusCode: statusCode,
      statusMessage: response['statusText'] as String?,
      responseHeaders: responseHeaders.isEmpty ? null : responseHeaders,
      responseSize: _nullableSize(
        response['bodySize'],
        _nullableSize(_map(response['content'])['size'], responseBody?.length),
      ),
      isHTTPS: scheme == 'https',
      isMITMDecrypted: meta['isMITMDecrypted'] as bool? ?? scheme == 'https',
      isMapLocal: meta['isMapLocal'] as bool? ?? false,
      isBreakpoint: meta['isBreakpoint'] as bool? ?? false,
      isResponseBreakpoint: meta['isResponseBreakpoint'] as bool? ?? false,
      state: state,
      errorMessage: error,
    );

    return ImportedExchange(
      exchange: exchange,
      requestBody: requestBody,
      responseBody: responseBody,
    );
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<HttpHeader> _headers(dynamic raw) {
    if (raw is! List) return const [];
    final headers = <HttpHeader>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name'];
      if (name is! String) continue;
      headers.add(HttpHeader(name, '${item['value'] ?? ''}'));
    }
    return headers;
  }

  static String _scheme(Uri? uri, List<HttpHeader> headers) {
    if (uri != null && uri.scheme.isNotEmpty) return uri.scheme;
    final host = _hostHeader(headers);
    if (host.endsWith(':443')) return 'https';
    return 'http';
  }

  static String _hostHeader(List<HttpHeader> headers) {
    for (final h in headers) {
      if (h.name.toLowerCase() == 'host') return h.value;
    }
    return '';
  }

  static Uint8List? _contentBody(dynamic raw) {
    final content = _map(raw);
    final text = content['text'];
    if (text is! String || text.isEmpty) return null;
    if (_isBase64(content['encoding']) || _isBase64(content['_encoding'])) {
      return _decodeBase64(text);
    }
    return Uint8List.fromList(utf8.encode(text));
  }

  static Uint8List? _postDataBody(dynamic raw) {
    final postData = _map(raw);
    final text = postData['text'];
    if (text is String && text.isNotEmpty) {
      if (_isBase64(postData['encoding']) || _isBase64(postData['_encoding'])) {
        return _decodeBase64(text);
      }
      return Uint8List.fromList(utf8.encode(text));
    }
    final params = postData['params'];
    if (params is List && params.isNotEmpty) {
      final pairs = <String>[];
      for (final p in params) {
        if (p is! Map) continue;
        final name = p['name'];
        if (name is! String) continue;
        pairs.add('$name=${p['value'] ?? ''}');
      }
      if (pairs.isNotEmpty) {
        return Uint8List.fromList(utf8.encode(pairs.join('&')));
      }
    }
    return null;
  }

  static bool _isBase64(dynamic encoding) => encoding == 'base64';

  static bool _isBase64Payload(dynamic container) {
    final map = _map(container);
    return _isBase64(map['encoding']) || _isBase64(map['_encoding']);
  }

  /// Drops headers that no longer describe a body whose text we decoded.
  static List<HttpHeader> _stripLengthHeaders(List<HttpHeader> headers) => [
    for (final header in headers)
      if (header.name.toLowerCase() != 'content-encoding' &&
          header.name.toLowerCase() != 'content-length')
        header,
  ];

  static Uint8List? _decodeBase64(String text) {
    try {
      return base64Decode(text);
    } on FormatException {
      return null;
    }
  }

  static int _size(dynamic raw, int fallback) =>
      _nullableSize(raw, fallback) ?? fallback;

  static int? _nullableSize(dynamic raw, int? fallback) {
    if (raw is num) {
      final value = raw.toInt();
      if (value >= 0) return value;
    }
    return fallback;
  }
}
