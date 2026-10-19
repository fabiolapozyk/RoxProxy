import 'dart:convert';
import 'dart:typed_data';

import '../models/captured_exchange.dart';
import '../utils/query_params.dart';

/// Resolves a native body reference to its raw bytes, or null when unavailable.
typedef HarBodyReader = Future<Uint8List?> Function(String ref);

/// Decodes a content-encoded body (gzip/deflate). Returns null when the encoding
/// is not supported (e.g. Brotli), so the caller can fall back to raw bytes.
typedef HarDecompressor =
    Future<Uint8List?> Function(Uint8List data, String encoding);

/// Builds HAR 1.2 documents from captured exchanges (issue #10).
///
/// The output is meant for interchange with other HTTP inspectors (Charles,
/// Proxyman, browser DevTools), so bodies are stored decoded when possible and
/// base64-encoded when they are binary or undecodable.
class HarExporter {
  const HarExporter();

  static const String harVersion = '1.2';
  static const String creatorName = 'RoxProxy';

  /// HAR requires an httpVersion; the capture model does not track it yet, so
  /// entries are reported as HTTP/1.1 (documented limitation, see issue #10).
  static const String _httpVersion = 'HTTP/1.1';

  Future<Map<String, dynamic>> build({
    required List<CapturedExchange> exchanges,
    required HarBodyReader readBody,
    required HarDecompressor decompress,
    String creatorVersion = '0.0.0',
  }) async {
    final entries = <Map<String, dynamic>>[];
    for (final exchange in exchanges) {
      entries.add(await _entry(exchange, readBody, decompress));
    }
    return {
      'log': {
        'version': harVersion,
        'creator': {'name': creatorName, 'version': creatorVersion},
        'entries': entries,
      },
    };
  }

  Future<Map<String, dynamic>> _entry(
    CapturedExchange exchange,
    HarBodyReader readBody,
    HarDecompressor decompress,
  ) async {
    final requestBody = await _resolve(exchange.requestBodyRef, readBody);
    final responseBody = await _resolve(exchange.responseBodyRef, readBody);

    final responseHeaders = _headers(exchange.responseHeaders ?? const []);
    final contentEncoding = _headerValue(responseHeaders, 'content-encoding');

    var contentBytes = responseBody;
    var decoded = false;
    final headers = [...responseHeaders];
    if (contentBytes != null && contentEncoding != null) {
      final decompressed = await decompress(contentBytes, contentEncoding);
      if (decompressed != null) {
        contentBytes = decompressed;
        decoded = true;
      }
    }

    // Once decompressed, the entry must not advertise the old encoding.
    if (decoded) {
      headers.removeWhere(
        (h) => (h['name'] as String).toLowerCase() == 'content-encoding',
      );
    }

    final requestContent = requestBody == null
        ? null
        : _harContent(requestBody);
    final responseContent = contentBytes == null
        ? null
        : _harContent(contentBytes);

    final mimetype = _headerValue(headers, 'content-type') ?? '';
    final duration = exchange.duration?.inMilliseconds ?? 0;

    return {
      'startedDateTime': exchange.startTime.toUtc().toIso8601String(),
      'time': duration < 0 ? 0 : duration,
      'request': {
        'method': exchange.method,
        'url': exchange.url,
        'httpVersion': _httpVersion,
        'cookies': <Map<String, dynamic>>[],
        'headers': _headers(exchange.requestHeaders),
        'queryString': _queryString(exchange.url),
        if (requestContent != null)
          'postData': {
            'mimeType':
                _headerValue(
                  _headers(exchange.requestHeaders),
                  'content-type',
                ) ??
                '',
            ...requestContent,
          },
        'headersSize': -1,
        'bodySize': exchange.requestSize,
      },
      'response': {
        'status': exchange.statusCode ?? 0,
        'statusText': exchange.statusMessage ?? '',
        'httpVersion': _httpVersion,
        'cookies': <Map<String, dynamic>>[],
        'headers': headers,
        'content': {
          'size': contentBytes?.length ?? 0,
          'mimeType': mimetype,
          if (responseContent != null) ...responseContent,
        },
        'redirectURL': _headerValue(headers, 'location') ?? '',
        'headersSize': -1,
        'bodySize': exchange.responseSize ?? responseBody?.length ?? 0,
      },
      'cache': <String, dynamic>{},
      'timings': {
        // The model only tracks total duration: report it as "wait".
        'send': 0,
        'wait': duration < 0 ? 0 : duration,
        'receive': 0,
      },
      // RoxProxy metadata not representable in standard HAR, kept in a custom
      // `_`-prefixed field so the document stays a valid HAR 1.2 (issues #10/#13).
      '_roxProxy': {
        'id': exchange.id,
        'isMITMDecrypted': exchange.isMITMDecrypted,
        'isMapLocal': exchange.isMapLocal,
        'isBreakpoint': exchange.isBreakpoint,
        'isResponseBreakpoint': exchange.isResponseBreakpoint,
        if (exchange.errorMessage != null) 'error': exchange.errorMessage,
      },
      if (_isTruncated(responseBody, exchange.responseSize)) '_truncated': true,
      if (contentEncoding != null && !decoded) '_encoding': contentEncoding,
    };
  }

  static Future<Uint8List?> _resolve(
    String? ref,
    HarBodyReader readBody,
  ) async {
    if (ref == null) return null;
    return readBody(ref);
  }

  /// Encodes body bytes as HAR text when they are valid UTF-8, base64 otherwise.
  static Map<String, dynamic> _harContent(Uint8List bytes) {
    final text = _tryUtf8(bytes);
    if (text != null) return {'text': text};
    return {'text': base64Encode(bytes), 'encoding': 'base64'};
  }

  static String? _tryUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  static List<Map<String, String>> _headers(List<HttpHeader> headers) => [
    for (final h in headers) {'name': h.name, 'value': h.value},
  ];

  static String? _headerValue(List<Map<String, String>> headers, String name) {
    for (final h in headers) {
      if ((h['name'] as String).toLowerCase() == name) {
        return h['value'] as String;
      }
    }
    return null;
  }

  static List<Map<String, String>> _queryString(String url) {
    final params = parseQueryParameters(queryStringOf(url));
    return [
      for (final p in params) {'name': p.name, 'value': p.value},
    ];
  }

  static bool _isTruncated(Uint8List? bytes, int? fullSize) =>
      bytes != null && fullSize != null && fullSize > bytes.length;
}
