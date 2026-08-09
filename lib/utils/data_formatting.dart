import 'dart:convert';
import 'dart:typed_data';

import '../models/captured_exchange.dart';

class DataFormatting {
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String formatDuration(Duration? duration) {
    if (duration == null) return '—';
    final ms = duration.inMilliseconds;
    if (ms < 1000) return '$ms ms';
    return '${(ms / 1000).toStringAsFixed(2)} s';
  }

  /// Builds a curl command string from a [CapturedExchange].
  /// [bodyBytes] should be provided if the request body has been fetched.
  static String buildCurlCommand(
    CapturedExchange exchange, {
    Uint8List? bodyBytes,
  }) {
    String esc(String s) => s.replaceAll("'", r"'\''");

    final buf = StringBuffer();
    buf.write("curl -X ${exchange.method} '${esc(exchange.url)}'");

    const skipHeaders = {'proxy-connection', 'proxy-authorization', 'host'};
    for (final h in exchange.requestHeaders) {
      if (skipHeaders.contains(h.name.toLowerCase())) continue;
      buf.write(" \\\n  -H '${esc(h.name)}: ${esc(h.value)}'");
    }

    if (bodyBytes != null && bodyBytes.isNotEmpty) {
      final body = utf8.decode(bodyBytes, allowMalformed: true);
      buf.write(" \\\n  --data-raw '${esc(body)}'");
    }

    return buf.toString();
  }
}
