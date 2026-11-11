import 'package:flutter/painting.dart';

import 'models.dart';

/// A word found by the on-device tokenizer, in UTF-16 offsets of the line.
class OcrToken {
  const OcrToken({
    required this.start,
    required this.length,
    required this.reading,
  });
  final int start;
  final int length;

  /// Hiragana reading of the whole token, okurigana included.
  final String reading;
}

/// One recognized line. Boxes are fractions of the image, origin top-left.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.box,
    this.characterBoxes = const [],
    this.tokens = const [],
  });
  final String text;
  final Rect box;

  /// One entry per UTF-16 unit of [text]; null where Vision has no box.
  final List<Rect?> characterBoxes;
  final List<OcrToken> tokens;

  static Rect? _rect(Object? raw) {
    final values = raw as List?;
    if (values == null || values.length != 4) return null;
    final numbers = values.cast<num>();
    return Rect.fromLTWH(
      numbers[0].toDouble(),
      numbers[1].toDouble(),
      numbers[2].toDouble(),
      numbers[3].toDouble(),
    );
  }

  factory OcrLine.fromChannel(Map<Object?, Object?> raw) => OcrLine(
    text: raw['text'] as String? ?? '',
    box: _rect(raw['box']) ?? Rect.zero,
    characterBoxes: [
      for (final box in raw['characterBoxes'] as List? ?? const []) _rect(box),
    ],
    tokens: [
      for (final token in raw['tokens'] as List? ?? const [])
        OcrToken(
          start: (token as Map)['start'] as int,
          length: token['length'] as int,
          reading: token['reading'] as String,
        ),
    ],
  );
}

class FuriganaSpan {
  const FuriganaSpan(this.start, this.end, this.reading);
  final int start;
  final int end;
  final String reading;
}

bool _isKanji(int unit) =>
    (unit >= 0x4e00 && unit <= 0x9fff) ||
    (unit >= 0x3400 && unit <= 0x4dbf) ||
    unit == 0x3005; // 々

String _toHiragana(String text) => String.fromCharCodes(
  text.codeUnits.map(
    (unit) => unit >= 0x30a1 && unit <= 0x30f6 ? unit - 0x60 : unit,
  ),
);

final _hiraganaOnly = RegExp(r'^[ぁ-ゟー]+$');

/// The transcription writes a long o as ō, which comes back as おう. These
/// common words are really おお, so they are corrected by their spelling.
const _longOWords = <(String, String, String)>[
  ('大き', 'おう', 'おお'),
  ('多', 'おう', 'おお'),
  ('通', 'とう', 'とお'),
  ('遠', 'とう', 'とお'),
  ('氷', 'こう', 'こお'),
  ('凍', 'こう', 'こお'),
  ('狼', 'おう', 'おお'),
  ('覆', 'おう', 'おお'),
];

String _correctLongO(String surface, String reading) {
  // 通 and 多 start many on'yomi words (通学, 多分), so okurigana is required.
  if (surface.length < 2 && !surface.startsWith('氷') && surface != '狼') {
    return reading;
  }
  if (surface.length >= 2 && _isKanji(surface.codeUnitAt(1))) return reading;
  for (final (spelling, wrong, right) in _longOWords) {
    if (surface.startsWith(spelling) && reading.startsWith(wrong)) {
      return right + reading.substring(wrong.length);
    }
  }
  return reading;
}

/// Splits [reading] over the kanji of [surface], leaving okurigana bare:
/// 食べ物 + たべもの → 食:た, 物:もの.
List<FuriganaSpan> alignFurigana(String surface, String reading) {
  final units = surface.codeUnits;
  final runs = <(int, int, bool)>[];
  for (var index = 0; index < units.length;) {
    final kanji = _isKanji(units[index]);
    var end = index + 1;
    while (end < units.length && _isKanji(units[end]) == kanji) {
      end++;
    }
    runs.add((index, end, kanji));
    index = end;
  }
  final kanjiRuns = [
    for (final run in runs)
      if (run.$3) run,
  ];
  if (kanjiRuns.isEmpty) return const [];
  final pattern = StringBuffer('^');
  for (final (start, end, kanji) in runs) {
    pattern.write(
      kanji
          ? '(.+?)'
          : RegExp.escape(_toHiragana(surface.substring(start, end))),
    );
  }
  pattern.write(r'$');
  final match = RegExp(pattern.toString()).firstMatch(reading);
  if (match == null) {
    return [FuriganaSpan(kanjiRuns.first.$1, kanjiRuns.last.$2, reading)];
  }
  return [
    for (final (index, run) in kanjiRuns.indexed)
      FuriganaSpan(run.$1, run.$2, match.group(index + 1)!),
  ];
}

double _glyphWeight(int unit) =>
    unit < 0x2e80 || (unit >= 0xff61 && unit <= 0xff9f) ? .55 : 1;

/// Vision's per-character boxes are used only when they look sane: narrower
/// than the line, inside it and in reading order. Otherwise (Vision often
/// reports the whole line for every character) the position is estimated
/// along the line, since Japanese glyphs are close to equal width. The
/// height always comes from the line, so a stray character box cannot pull
/// the furigana into the middle of the text.
bool _characterBoxesUsable(OcrLine line) {
  final boxes = line.characterBoxes;
  if (line.text.length < 2 || boxes.length != line.text.length) return false;
  final first = boxes.first;
  if (first == null || first.width >= line.box.width * .9) return false;
  final slack = line.box.width * .03;
  var previous = double.negativeInfinity;
  for (final box in boxes) {
    if (box == null) continue;
    if (box.left < line.box.left - slack ||
        box.right > line.box.right + slack ||
        box.left < previous - slack) {
      return false;
    }
    previous = box.left;
  }
  return true;
}

Rect _spanBox(OcrLine line, int start, int end) {
  if (_characterBoxesUsable(line)) {
    double? left;
    double? right;
    for (var index = start; index < end; index++) {
      final box = line.characterBoxes[index];
      if (box == null) continue;
      left = left == null || box.left < left ? box.left : left;
      right = right == null || box.right > right ? box.right : right;
    }
    if (left != null && right != null) {
      return Rect.fromLTRB(left, line.box.top, right, line.box.bottom);
    }
  }
  final units = line.text.codeUnits;
  final total = units.fold<double>(0, (sum, unit) => sum + _glyphWeight(unit));
  double widthOf(int from, int to) => units
      .sublist(from, to)
      .fold<double>(0, (sum, unit) => sum + _glyphWeight(unit));
  final perWeight = line.box.width / total;
  return Rect.fromLTWH(
    line.box.left + widthOf(0, start) * perWeight,
    line.box.top,
    widthOf(start, end) * perWeight,
    line.box.height,
  );
}

/// Furigana for every kanji of [lines], placed in page coordinates. [region]
/// is the page area of the OCR image; marks outside [keepInside] are dropped
/// so the capture margin does not annotate words the learner did not circle.
List<FuriganaMark> buildFuriganaMarks(
  List<OcrLine> lines, {
  required Rect region,
  required Rect keepInside,
}) {
  final marks = <FuriganaMark>[];
  final heights = [for (final line in lines) line.box.height]..sort();
  final typicalHeight = heights.isEmpty ? 0.0 : heights[heights.length ~/ 2];
  for (final line in lines) {
    // A box much taller than the other lines is two lines read as one;
    // positions inside it would be guesses.
    if (lines.length > 2 && line.box.height > typicalHeight * 1.8) continue;
    // Vertical text would need the reading on the side of the glyphs.
    if (line.box.height > line.box.width * 1.5 && line.text.length >= 3) {
      continue;
    }
    for (final token in line.tokens) {
      final end = token.start + token.length;
      if (end > line.text.length) continue;
      final surface = line.text.substring(token.start, end);
      final reading = _correctLongO(surface, _toHiragana(token.reading));
      if (!_hiraganaOnly.hasMatch(reading)) continue;
      for (final span in alignFurigana(surface, reading)) {
        final box = _spanBox(
          line,
          token.start + span.start,
          token.start + span.end,
        );
        final rect = Rect.fromLTWH(
          region.left + box.left * region.width,
          region.top + box.top * region.height,
          box.width * region.width,
          box.height * region.height,
        );
        if (keepInside.contains(rect.center)) {
          marks.add(
            FuriganaMark(
              id: FuriganaMark.newId(),
              reading: span.reading,
              rect: rect,
            ),
          );
        }
      }
    }
  }
  return marks;
}

/// Automatic size from the kanji height, times the learner's own scale.
double furiganaFontSize(FuriganaMark mark) =>
    (mark.rect.height * .42).clamp(6.0, 16.0) * mark.scale;

/// Where the furigana text is drawn: centred just above its kanji.
Rect furiganaLabelRect(FuriganaMark mark) {
  final painter = TextPainter(
    text: TextSpan(
      text: mark.reading,
      style: TextStyle(fontSize: furiganaFontSize(mark), height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final rect = Rect.fromLTWH(
    mark.rect.center.dx - painter.width / 2,
    mark.rect.top - painter.height - 1,
    painter.width,
    painter.height,
  );
  painter.dispose();
  return rect;
}

/// The learner circles what they see (the kana) or the kanji under it.
bool furiganaInRegion(FuriganaMark mark, Rect region) =>
    region.contains(mark.rect.center) ||
    region.contains(furiganaLabelRect(mark).center);
