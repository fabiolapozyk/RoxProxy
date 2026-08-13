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

  group('RenderJson.text', () {
    test('roundtrips the pretty-printed JSON exactly', () {
      final raw = '{"name": "Rox", "nested": {"a": [1, 2, 3]}, "ok": true}';
      final pretty = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(raw));
      final mode = BodyRenderer.render(
        data: Uint8List.fromList(utf8.encode(raw)),
        contentType: 'application/json',
      );
      expect((mode as RenderJson).text, pretty);
    });

    test('empty lines list yields empty string', () {
      expect(RenderJson([]).text, '');
    });

    test('single line JSON roundtrips', () {
      final mode = BodyRenderer.render(
        data: Uint8List.fromList(utf8.encode('42')),
        contentType: 'application/json',
      );
      expect((mode as RenderJson).text, '42');
    });

    test('escaped newlines inside strings do not split lines', () {
      final raw = '{"msg": "line1\\nline2"}';
      final pretty = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(raw));
      final mode = BodyRenderer.render(
        data: Uint8List.fromList(utf8.encode(raw)),
        contentType: 'application/json',
      );
      final json = mode as RenderJson;
      expect(json.lines.length, 3);
      expect(json.text, pretty);
    });
  });
}
