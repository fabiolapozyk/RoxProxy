import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/utils/body_renderer.dart';

void main() {
  group('BodyRenderer JSON lines', () {
    test('pretty-prints and tokenizes into lines', () {
      final data = utf8.encode('{"name": "Rox", "n": 5, "ok": true}');
      final mode = BodyRenderer.render(
        data: Uint8List.fromList(data),
        contentType: 'application/json',
      );

      expect(mode, isA<RenderJson>());
      final lines = (mode as RenderJson).lines;
      expect(lines, isNotEmpty);
      expect(lines.length, greaterThan(1));
    });

    test('classifies key, string, number and bool/null tokens', () {
      final data = utf8.encode('{"name": "Rox", "n": 5, "ok": true}');
      final mode = BodyRenderer.render(
        data: Uint8List.fromList(data),
        contentType: 'application/json',
      );

      final segments = (mode as RenderJson).lines
          .expand((l) => l.segments)
          .toList();

      final key = segments.firstWhere((s) => s.text == '"name"');
      expect(key.kind, JsonTokenKind.key);
      final string = segments.firstWhere((s) => s.text == '"Rox"');
      expect(string.kind, JsonTokenKind.string);
      final number = segments.firstWhere((s) => s.text == '5');
      expect(number.kind, JsonTokenKind.number);
      final boolNull = segments.firstWhere((s) => s.text == 'true');
      expect(boolNull.kind, JsonTokenKind.boolNull);
      final punctuation = segments.firstWhere((s) => s.text == '{');
      expect(punctuation.kind, JsonTokenKind.punctuation);
      final whitespace = segments.firstWhere(
        (s) => s.kind == JsonTokenKind.whitespace,
      );
      expect(whitespace.text, isNotEmpty);
    });

    test('fallback to plain text when JSON is invalid', () {
      final mode = BodyRenderer.render(
        data: Uint8List.fromList(utf8.encode('not json')),
        contentType: 'application/json',
      );
      expect(mode, isA<RenderText>());
    });

    test('empty body renders empty', () {
      final mode = BodyRenderer.render(
        data: Uint8List(0),
        contentType: 'application/json',
      );
      expect(mode, isA<RenderEmpty>());
    });
  });
}
