import 'package:flutter/painting.dart';

/// Una singola occorrenza della query di ricerca nel body.
///
/// [start]/[end] sono offset (unità UTF-16) dentro il testo della riga
/// sorgente [line]. [index] è la posizione globale dell'occorrenza nella
/// lista ordinata di tutte le occorrenze.
class BodyMatch {
  final int index;
  final int line;
  final int start;
  final int end;

  const BodyMatch(this.index, this.line, this.start, this.end);
}

/// Splitta il testo in righe sorgente per la ricerca/il layout.
///
/// Il separatore `\n` di fine testo non crea una riga visiva aggiuntiva, quindi
/// viene rimosso prima dello split per mantenere l'indice di riga allineato
/// con il rendering reale del `Text`.
List<String> splitLines(String text) {
  final t = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return t.split('\n');
}

/// Trova le occorrenze letterali (regex-escapate) di [query] nelle [lines].
///
/// La query è trattata come testo letterale: i metacaratteri regex (es. `.`)
/// non hanno significato. La ricerca è case-insensitive. Non supporta match
/// che attraversano più righe (un `\n` nella query non trova nulla).
List<BodyMatch> findMatches(List<String> lines, String query) {
  if (query.isEmpty) return const [];
  final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
  final matches = <BodyMatch>[];
  for (var i = 0; i < lines.length; i++) {
    for (final m in pattern.allMatches(lines[i])) {
      matches.add(BodyMatch(matches.length, i, m.start, m.end));
    }
  }
  return matches;
}

/// Calcola l'offset di scroll di un match usando gli stessi `TextStyle`/
/// `textScaler`/`maxWidth` del `Text` renderizzato.
///
/// Usa il caret layout reale (`getOffsetForCaret`) invece di sommare le
/// altezze dichiarate delle righe: `computeLineMetrics().height` può divergere
/// dall'interlinea effettivo (es. arrotondamenti), e la somma accumula errori
/// su tante righe producendo scroll "troppo avanti/indietro".
class BodySearchLayout {
  final List<String> lines;
  final double maxWidth;
  final TextStyle style;
  final TextScaler textScaler;

  /// `true` quando il contenuto è renderizzato come paragrafi separati per
  /// riga (JSON grande, `ListView.builder`): l'offset è la somma delle altezze
  /// dei singoli item. `false` quando è un unico paragrafo con tutte le righe.
  final bool perLineParagraphs;

  BodySearchLayout({
    required this.lines,
    required this.maxWidth,
    required this.style,
    this.textScaler = TextScaler.noScaling,
    this.perLineParagraphs = false,
  });

  final Map<int, double> _lineHeights = {};

  /// Offset verticale (px) dall'inizio del contenuto fino alla riga visiva
  /// che contiene l'inizio del [match].
  double offsetForMatch(BodyMatch match) {
    if (perLineParagraphs) {
      var top = 0.0;
      for (var i = 0; i < match.line; i++) {
        top += lineHeight(i);
      }
      return top + _caretDy(lines[match.line], match.start);
    }
    final painter = _wholePainter();
    return painter
        .getOffsetForCaret(
          TextPosition(offset: _globalOffset(match)),
          Rect.zero,
        )
        .dy;
  }

  /// Paragrafo completo (tutte le righe) come nel rendering a testo unico.
  TextPainter _wholePainter() {
    return TextPainter(
      text: TextSpan(text: lines.join('\n'), style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
  }

  /// Offset del match nel testo completo (righe join da `\n`).
  int _globalOffset(BodyMatch match) {
    var offset = 0;
    for (var i = 0; i < match.line; i++) {
      offset += lines[i].length + 1;
    }
    return offset + match.start;
  }

  double? _charWidth;
  double? _singleRowHeight;

  TextPainter _measure(String text) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
  }

  double get _charWidthValue => _charWidth ??= _measure('M').width;

  double get _singleRowHeightValue => _singleRowHeight ??= _measure('M').height;

  static bool _isAscii(String s) => s.codeUnits.every((u) => u < 0x80);

  /// Altezza del paragrafo di una singola riga (è l'altezza dell'item nella
  /// ListView lazy). Una riga vuota conta comunque come una riga visiva.
  ///
  /// Per le righe ASCII che non possono andare a capo (larghezza totale <=
  /// [maxWidth]) usa l'altezza di una riga singola senza TextPainter: è il
  /// fast path che evita di misurare migliaia di righe corte.
  double lineHeight(int index) {
    final cached = _lineHeights[index];
    if (cached != null) return cached;
    final text = lines[index];
    final height =
        (text.isEmpty ||
            (_isAscii(text) && text.length * _charWidthValue <= maxWidth))
        ? _singleRowHeightValue
        : _measure(text).height;
    return _lineHeights[index] = height;
  }

  double _caretDy(String text, int charOffset) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    return painter
        .getOffsetForCaret(TextPosition(offset: charOffset), Rect.zero)
        .dy;
  }

  double? _totalHeight;

  /// Altezza totale del contenuto: somma delle altezze di tutte le righe.
  ///
  /// È il max scroll extent esatto, usato dal delegate della ListView lazy
  /// per evitare che l'animateTo venga clamppato su una stima troppo bassa
  /// (il ListView.builder estrapola dall'estensione media degli item costruiti
  /// e su body grandi con altezze variabili si ferma "troppo prima").
  double get totalHeight => _totalHeight ??= () {
    var sum = 0.0;
    for (var i = 0; i < lines.length; i++) {
      sum += lineHeight(i);
    }
    return sum;
  }();
}
