import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/ui/detail/body_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('splitLines', () {
    test('splits on newline', () {
      expect(splitLines('a\nb\nc'), ['a', 'b', 'c']);
    });

    test('strips a single trailing newline (no extra visual row)', () {
      expect(splitLines('a\nb\n'), ['a', 'b']);
    });

    test('keeps inner empty lines', () {
      expect(splitLines('a\n\nb'), ['a', '', 'b']);
    });

    test('single line without newline', () {
      expect(splitLines('abc'), ['abc']);
    });

    test('empty string is one empty line', () {
      expect(splitLines(''), ['']);
    });
  });

  group('findMatches', () {
    test('empty query returns no matches', () {
      expect(findMatches(['abc'], ''), isEmpty);
    });

    test('treats query as literal text (regex metachars escaped)', () {
      final matches = findMatches(['foo.bar', 'fooxbar'], 'foo.bar');
      expect(matches, hasLength(1));
      expect(matches.single.line, 0);
      expect(matches.single.start, 0);
      expect(matches.single.end, 7);
    });

    test('parens and brackets are literal', () {
      final matches = findMatches(['a(b) [c]', 'abc'], '(');
      expect(matches, hasLength(1));
      expect(matches.single.line, 0);
      expect(matches.single.start, 1);
    });

    test('case-insensitive matching', () {
      final matches = findMatches(['Hello hello HELLO'], 'hello');
      expect(matches, hasLength(3));
    });

    test('global indices and line mapping across multiple lines', () {
      final matches = findMatches(['x a', 'b x c', 'x'], 'x');
      expect(matches.map((m) => m.index), [0, 1, 2]);
      expect(matches.map((m) => m.line), [0, 1, 2]);
      expect(matches.map((m) => m.start), [0, 2, 0]);
    });

    test('query containing newline finds nothing (per-line search)', () {
      expect(findMatches(['ab', 'cd'], 'b\nc'), isEmpty);
    });

    test('overlapping occurrences do not overlap', () {
      final matches = findMatches(['aaaa'], 'aa');
      expect(matches.map((m) => m.start), [0, 2]);
    });
  });

  group('BodySearchLayout', () {
    // In flutter_test il font Ahem ha glyph quadrati larghi quanto il
    // fontSize (12px) e, con height 1.5, righe visive di 18px.
    final style = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5);

    // Riferimento: il vero rendering usa un unico paragrafo con le righe
    // join da '\n'; l'offset deve coincidere con la posizione del caret.
    double refDy(
      List<String> lines,
      int globalOffset,
      TextStyle st, {
      double width = 1000,
    }) {
      final p = TextPainter(
        text: TextSpan(text: lines.join('\n'), style: st),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      return p
          .getOffsetForCaret(TextPosition(offset: globalOffset), Rect.zero)
          .dy;
    }

    test('offset equals the real paragraph caret position (line 0)', () {
      final lines = ['a', 'bb', 'ccc'];
      final layout = BodySearchLayout(
        lines: lines,
        maxWidth: 1000,
        style: style,
      );
      final match = BodyMatch(0, 0, 0, 1);
      expect(
        layout.offsetForMatch(match),
        closeTo(refDy(lines, 0, style), 0.01),
      );
    });

    test('offset advances with the line index', () {
      final lines = ['a', 'bb', 'ccc'];
      final layout = BodySearchLayout(
        lines: lines,
        maxWidth: 1000,
        style: style,
      );
      final o0 = layout.offsetForMatch(BodyMatch(0, 0, 0, 1));
      final o1 = layout.offsetForMatch(BodyMatch(1, 1, 0, 1));
      final o2 = layout.offsetForMatch(BodyMatch(2, 2, 0, 1));
      expect(o1, closeTo(refDy(lines, 4, style), 0.01));
      expect(o2, closeTo(refDy(lines, 7, style), 0.01));
      expect(o1, greaterThan(o0));
      expect(o2, greaterThan(o1));
    });

    test('wrapped long line contributes multiple visual rows', () {
      // 30 char * 12px = 360px; maxWidth 288 -> 2 righe (24 + 6).
      final lines = [List.filled(30, 'a').join(), 'T'];
      final layout = BodySearchLayout(
        lines: lines,
        maxWidth: 288,
        style: style,
      );
      final match = BodyMatch(0, 1, 0, 1);
      final expected = refDy(lines, 31, style, width: 288);
      expect(layout.offsetForMatch(match), closeTo(expected, 0.01));
      expect(layout.offsetForMatch(match), greaterThan(18));
    });

    test('match on a wrapped row lands on the correct visual row', () {
      final lines = [List.filled(30, 'a').join()];
      final layout = BodySearchLayout(
        lines: lines,
        maxWidth: 288,
        style: style,
      );
      final match = BodyMatch(0, 0, 26, 27);
      expect(
        layout.offsetForMatch(match),
        closeTo(refDy(lines, 26, style, width: 288), 0.01),
      );
    });

    test('empty line counts as one visual row', () {
      final lines = ['a', '', 'T'];
      final layout = BodySearchLayout(
        lines: lines,
        maxWidth: 1000,
        style: style,
      );
      final match = BodyMatch(0, 2, 0, 1);
      expect(
        layout.offsetForMatch(match),
        closeTo(refDy(lines, 3, style), 0.01),
      );
    });

    test('textScaler scales the offsets', () {
      final lines = ['a', 'bb', 'ccc'];
      final layout = BodySearchLayout(
        lines: lines,
        maxWidth: 1000,
        style: style,
        textScaler: const TextScaler.linear(2.0),
      );
      final match = BodyMatch(0, 2, 0, 1);
      final p = TextPainter(
        text: TextSpan(text: lines.join('\n'), style: style),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(2.0),
      )..layout(maxWidth: 1000);
      final expected = p
          .getOffsetForCaret(TextPosition(offset: 7), Rect.zero)
          .dy;
      expect(layout.offsetForMatch(match), closeTo(expected, 0.01));
    });

    test('hex style (fontSize 11) uses its own measured line height', () {
      final hexStyle = TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        height: 1.5,
      );
      final lines = ['aa', 'bb'];
      final layout = BodySearchLayout(
        lines: lines,
        maxWidth: 1000,
        style: hexStyle,
      );
      final match = BodyMatch(0, 1, 0, 1);
      expect(
        layout.offsetForMatch(match),
        closeTo(refDy(lines, 3, hexStyle), 0.01),
      );
    });

    test('lazy mode (per-line paragraphs) sums item heights', () {
      final lines = ['aa', 'bb', 'cc'];
      final layout = BodySearchLayout(
        lines: lines,
        maxWidth: 1000,
        style: style,
        perLineParagraphs: true,
      );
      final m = BodyMatch(0, 2, 0, 1);
      var sum = 0.0;
      for (final line in lines.take(2)) {
        final p = TextPainter(
          text: TextSpan(text: line, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 1000);
        sum += p.height;
      }
      expect(layout.offsetForMatch(m), closeTo(sum, 0.01));
    });
  });
}
