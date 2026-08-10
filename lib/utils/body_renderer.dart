import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

sealed class RenderMode {}

enum JsonTokenKind {
  key,
  string,
  number,
  boolNull,
  punctuation,
  whitespace,
  other,
}

class JsonSegment {
  final String text;
  final JsonTokenKind kind;
  JsonSegment(this.text, this.kind);
}

class JsonLine {
  final List<JsonSegment> segments;
  JsonLine(this.segments);
}

class RenderJson extends RenderMode {
  final List<JsonLine> lines;
  RenderJson(this.lines);
}

class RenderText extends RenderMode {
  final String text;
  RenderText(this.text);
}

class RenderImage extends RenderMode {
  final Uint8List bytes;
  RenderImage(this.bytes);
}

class RenderHex extends RenderMode {
  final String text;
  RenderHex(this.text);
}

class RenderEmpty extends RenderMode {}

class BodyRenderer {
  static const int _bytesPerLine = 16;
  static const int _maxHexDumpBytes = 64 * 1024;

  static RenderMode render({
    required Uint8List data,
    String? contentType,
    bool isTruncated = false,
  }) {
    if (data.isEmpty) return RenderEmpty();

    final ct = contentType?.toLowerCase() ?? '';

    // Image
    if (ct.startsWith('image/')) {
      return RenderImage(data);
    }

    // JSON
    if (ct.contains('json') || ct.contains('javascript')) {
      final str = _toString(data, contentType: ct);
      if (str != null) {
        final pretty = _prettyJson(str);
        if (pretty != null) return RenderJson(_tokenizeJson(pretty));
        return RenderText(str);
      }
    }

    // Text-like types
    if (ct.isEmpty ||
        ct.startsWith('text/') ||
        ct.contains('xml') ||
        ct.contains('html') ||
        ct.contains('form-urlencoded')) {
      final str = _toString(data, contentType: ct);
      if (str != null) return RenderText(str);
    }

    // Try to decode as text if content type is not recognized
    if (ct.isEmpty || !ct.startsWith('image/')) {
      final str = _toString(data, contentType: ct);
      if (str != null) {
        return RenderText(str);
      }
    }

    // Fallback: hex dump
    return RenderHex(_hexDump(data));
  }

  static String? _toString(Uint8List data, {String? contentType}) {
    try {
      return utf8.decode(data);
    } catch (_) {
      // Se il Content-Type è text/html o specifica UTF-8, forza la decodifica come UTF-8
      // ignorando i byte non validi
      if (contentType != null &&
          (contentType.toLowerCase().contains('text/html') ||
              contentType.toLowerCase().contains('charset=utf-8'))) {
        final str = utf8.decode(data, allowMalformed: true);
        // Verifica se la stringa contiene caratteri non validi
        final hasInvalidChars = str.runes.any(
          (r) => r < 32 && r != 9 && r != 10 && r != 13,
        );
        if (hasInvalidChars) {
          // Rimuovi i caratteri non validi
          return str.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
        }
        return str;
      }
      try {
        return latin1.decode(data);
      } catch (_) {
        return null;
      }
    }
  }

  static String? _prettyJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return null;
    }
  }

  static final RegExp _jsonTokenRe = RegExp(
    r'("(?:[^"\\]|\\.)*")' // group 1 – string
    r'|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)' // group 2 – number
    r'|(true|false|null)' // group 3 – keyword
    r'|([{}\[\],:])' // group 4 – punctuation
    r'|(\s+)' // group 5 – whitespace
    r'|(.)', // group 6 – fallback
    dotAll: true,
  );

  /// Splits pretty-printed JSON text into lines of color-classified segments.
  /// Theme-independent: colors are resolved at render time.
  static List<JsonLine> _tokenizeJson(String source) {
    final lines = <JsonLine>[];
    var segments = <JsonSegment>[];

    void flush() {
      if (segments.isNotEmpty) {
        lines.add(JsonLine(segments));
        segments = <JsonSegment>[];
      }
    }

    for (final m in _jsonTokenRe.allMatches(source)) {
      JsonTokenKind kind;
      if (m.group(1) != null) {
        var i = m.end;
        while (i < source.length && (source[i] == ' ' || source[i] == '\t')) {
          i++;
        }
        kind = i < source.length && source[i] == ':'
            ? JsonTokenKind.key
            : JsonTokenKind.string;
      } else if (m.group(2) != null) {
        kind = JsonTokenKind.number;
      } else if (m.group(3) != null) {
        kind = JsonTokenKind.boolNull;
      } else if (m.group(4) != null) {
        kind = JsonTokenKind.punctuation;
      } else if (m.group(5) != null) {
        kind = JsonTokenKind.whitespace;
      } else {
        kind = JsonTokenKind.other;
      }

      final text = m.group(0)!;
      if (!text.contains('\n')) {
        segments.add(JsonSegment(text, kind));
        continue;
      }
      final parts = text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) segments.add(JsonSegment(parts[i], kind));
        if (i < parts.length - 1) flush();
      }
    }
    flush();
    return lines;
  }

  static String _hexDump(Uint8List data) {
    final shown = data.length > _maxHexDumpBytes
        ? data.sublist(0, _maxHexDumpBytes)
        : data;
    final sb = StringBuffer();
    for (var i = 0; i < shown.length; i += _bytesPerLine) {
      final end = (i + _bytesPerLine).clamp(0, shown.length);
      final chunk = shown.sublist(i, end);

      // Offset
      sb.write('${i.toRadixString(16).padLeft(8, '0')}  ');

      // Hex bytes
      for (var j = 0; j < _bytesPerLine; j++) {
        if (j < chunk.length) {
          sb.write(chunk[j].toRadixString(16).padLeft(2, '0'));
          sb.write(' ');
        } else {
          sb.write('   ');
        }
        if (j == 7) sb.write(' ');
      }

      // ASCII
      sb.write(' |');
      for (final byte in chunk) {
        sb.write(
          (byte >= 0x20 && byte < 0x7f) ? String.fromCharCode(byte) : '.',
        );
      }
      sb.write('|\n');
    }
    if (shown.length < data.length) {
      sb.writeln('... (truncated: ${data.length} bytes total)');
    }
    return sb.toString();
  }
}
