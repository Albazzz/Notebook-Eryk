import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

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

// ---------------------------------------------------------------------------
// Finding the lines of text in the captured image.
//
// Vision's line boxes are unreliable on textbook pages: printed furigana above
// a line is often read as part of it, which makes the box taller (furigana
// then lands on the line above) and puts stray kana into the text. Instead
// the image itself is scanned for rows of ink, each body line is cut out on
// its own and read separately, and its real top edge is used.
// ---------------------------------------------------------------------------

/// Rows `top` (inclusive) to `bottom` (exclusive) of the image hold ink.
class TextBand {
  const TextBand(this.top, this.bottom);
  final int top;
  final int bottom;
  int get height => bottom - top;

  @override
  String toString() => 'TextBand($top, $bottom)';
}

/// A grayscale image, 0 (black) to 255 (white), row by row.
class InkImage {
  InkImage(this.width, this.height, this.luminance)
    : threshold = _thresholdFor(luminance);
  final int width;
  final int height;
  final Uint8List luminance;

  /// Darker than this is ink: well below the paper, whatever its tint.
  final int threshold;

  static int _thresholdFor(Uint8List luminance) {
    if (luminance.isEmpty) return 128;
    var sum = 0;
    for (final value in luminance) {
      sum += value;
    }
    return (sum / luminance.length * .7).clamp(80, 170).round();
  }

  bool isInk(int x, int y) => luminance[y * width + x] < threshold;
}

/// Rows holding text. Columns inked almost top to bottom (page edges, the
/// binding, vertical rules) are ignored; a row counts when it has a real share
/// of ink, so a hand-drawn circle between two lines does not join them.
List<TextBand> findTextBands(InkImage image) {
  final width = image.width;
  final height = image.height;
  if (width == 0 || height == 0) return const [];
  final columnInk = List<int>.filled(width, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (image.isInk(x, y)) columnInk[x]++;
    }
  }
  final ignored = [for (final count in columnInk) count > height * .6];
  final rowInk = List<int>.filled(height, 0);
  for (var y = 0; y < height; y++) {
    var count = 0;
    for (var x = 0; x < width; x++) {
      if (!ignored[x] && image.isInk(x, y)) count++;
    }
    rowInk[y] = count;
  }
  final busiest = rowInk.fold<int>(0, math.max);
  if (busiest == 0) return const [];
  final minimum = math.max(3, (busiest * .03).ceil());
  bool inked(int y) => y >= 0 && y < height && rowInk[y] >= minimum;
  final bands = <TextBand>[];
  var y = 0;
  while (y < height) {
    if (!inked(y)) {
      y++;
      continue;
    }
    final start = y;
    // A single blank row inside a line of glyphs (二, 三) is not a gap.
    while (inked(y) || (inked(y + 1) && y + 1 < height)) {
      y++;
    }
    if (y - start >= 3) bands.add(TextBand(start, y));
  }
  return bands;
}

/// Height of a line of body text: the median of the taller half of the
/// bands, so printed furigana and specks do not pull it down.
int typicalTextHeight(List<TextBand> bands) {
  if (bands.isEmpty) return 0;
  final heights = [for (final band in bands) band.height]..sort();
  final median = heights[heights.length ~/ 2];
  final tall = [
    for (final height in heights)
      if (height >= median) height,
  ];
  return tall[tall.length ~/ 2];
}

/// The lines of body text. Short bands are printed furigana or specks. A band
/// up to about twice the text height is printed furigana touching its line:
/// the text is its lower part. Anything taller is a figure or handwriting.
List<TextBand> bodyLines(List<TextBand> bands) {
  final textHeight = typicalTextHeight(bands);
  if (textHeight == 0) return const [];
  return [
    for (final band in bands)
      if (band.height >= textHeight * .6 && band.height <= textHeight * 1.3)
        band
      else if (band.height > textHeight * 1.3 &&
          band.height <= textHeight * 2.2)
        TextBand(band.bottom - textHeight, band.bottom),
  ];
}

/// True when ink already sits right above `[left, right)` of a line that
/// starts at [top], below [ceiling] (the previous line): the book prints
/// furigana there itself.
bool hasPrintedFurigana(
  InkImage image, {
  required int left,
  required int right,
  required int top,
  required int ceiling,
  required int textHeight,
}) {
  final from = math.max(ceiling, top - (textHeight * .6).round());
  final x0 = left.clamp(0, image.width);
  final x1 = right.clamp(0, image.width);
  if (top - from < 2 || x1 <= x0) return false;
  var ink = 0;
  for (var y = from; y < top; y++) {
    for (var x = x0; x < x1; x++) {
      if (image.isInk(x, y)) ink++;
    }
  }
  return ink / ((top - from) * (x1 - x0)) > .03;
}

/// One body line cut out of the capture for OCR: scaled up so small print
/// reads well, with a white margin around it.
class LineImage {
  const LineImage({
    required this.band,
    required this.png,
    required this.width,
    required this.height,
    required this.scaleX,
    required this.border,
  });
  final TextBand band;
  final Uint8List png;
  final int width;
  final int height;
  final double scaleX;
  final int border;
}

/// Moves a line read from a [LineImage] back to fractions of the capture,
/// taking its height from the body line itself.
OcrLine lineInCapture(
  OcrLine line,
  LineImage source, {
  required int captureWidth,
  required int captureHeight,
}) {
  double x(double fraction) =>
      ((fraction * source.width - source.border) / source.scaleX) /
      captureWidth;
  final top = source.band.top / captureHeight;
  final bottom = source.band.bottom / captureHeight;
  Rect across(Rect box) =>
      Rect.fromLTRB(x(box.left), top, x(box.right), bottom);
  return OcrLine(
    text: line.text,
    box: across(line.box),
    characterBoxes: [
      for (final box in line.characterBoxes) box == null ? null : across(box),
    ],
    tokens: line.tokens,
  );
}

class _PreparedCapture {
  const _PreparedCapture(this.ink, this.lines, this.textHeight);
  final InkImage ink;
  final List<LineImage> lines;
  final int textHeight;
}

// Work sent to a background isolate lives in top-level functions: a closure
// written inside a method also carries that method's other captured values
// (the State, the widget tree), which cannot be sent to an isolate.
Future<_PreparedCapture?> _prepareCaptureInBackground(Uint8List png) =>
    Isolate.run(() => _prepareCapture(png));

_PreparedCapture? _prepareCapture(Uint8List png) {
  final image = img.decodeImage(png);
  if (image == null) return null;
  final width = image.width;
  final height = image.height;
  final luminance = Uint8List(width * height);
  for (final pixel in image) {
    luminance[pixel.y * width + pixel.x] = pixel.luminance.toInt().clamp(
      0,
      255,
    );
  }
  final ink = InkImage(width, height, luminance);
  final bands = findTextBands(ink);
  final textHeight = typicalTextHeight(bands);
  final lines = <LineImage>[];
  for (final band in bodyLines(bands)) {
    final top = math.max(0, band.top - 2);
    final bottom = math.min(height, band.bottom + 2);
    var crop = img.copyCrop(
      image,
      x: 0,
      y: top,
      width: width,
      height: bottom - top,
    );
    // Vision reads small print better once a line is about 48 px tall.
    if (band.height < 48) {
      final scale = 48 / band.height;
      crop = img.copyResize(
        crop,
        width: (crop.width * scale).round(),
        height: (crop.height * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    }
    final border = (crop.height * .5).round();
    final canvas = img.Image(
      width: crop.width + border * 2,
      height: crop.height + border * 2,
    );
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, crop, dstX: border, dstY: border);
    lines.add(
      LineImage(
        band: band,
        png: img.encodePng(canvas),
        width: canvas.width,
        height: canvas.height,
        scaleX: crop.width / width,
        border: border,
      ),
    );
  }
  return _PreparedCapture(ink, lines, textHeight);
}

/// Furigana for the kanji in a captured image of [region] (page coordinates).
/// Each body line is read on its own; words the book already gives furigana
/// are skipped, and the size is kept to the space above the line. Falls back
/// to reading the whole image when no lines can be found.
Future<List<FuriganaMark>> recognizeFurigana({
  /// The capture saved on the device. It is only read here, never uploaded.
  required String capturePath,
  required Rect region,
  required Rect keepInside,
  required Future<List<OcrLine>> Function(String path) recognize,
  void Function(int done, int total)? onProgress,
}) async {
  final bytes = await File(capturePath).readAsBytes();
  final prepared = await _prepareCaptureInBackground(bytes);
  if (prepared == null || prepared.lines.isEmpty) {
    return buildFuriganaMarks(
      await recognize(capturePath),
      region: region,
      keepInside: keepInside,
    );
  }
  final lines = prepared.lines;
  final marks = <FuriganaMark>[];
  var done = 0;
  onProgress?.call(0, lines.length);
  // A few lines at a time: Vision runs off the main thread on the iPad.
  for (var start = 0; start < lines.length; start += 4) {
    final batch = [
      for (
        var index = start;
        index < math.min(start + 4, lines.length);
        index++
      )
        index,
    ];
    final results = await Future.wait(
      batch.map((index) async {
        final file = File('$capturePath.line$index.png');
        await file.writeAsBytes(lines[index].png, flush: true);
        try {
          return await recognize(file.path);
        } catch (_) {
          return const <OcrLine>[];
        } finally {
          unawaited(file.delete().catchError((_) => file));
        }
      }),
    );
    for (final (offset, recognized) in results.indexed) {
      final index = batch[offset];
      marks.addAll(
        _marksForLine(
          recognized,
          lines[index],
          ceiling: index == 0 ? 0 : lines[index - 1].band.bottom,
          prepared: prepared,
          region: region,
          keepInside: keepInside,
        ),
      );
      done++;
    }
    onProgress?.call(done, lines.length);
  }
  return marks;
}

List<FuriganaMark> _marksForLine(
  List<OcrLine> recognized,
  LineImage source, {
  required int ceiling,
  required _PreparedCapture prepared,
  required Rect region,
  required Rect keepInside,
}) {
  final ink = prepared.ink;
  final inCapture = [
    for (final line in recognized)
      lineInCapture(
        line,
        source,
        captureWidth: ink.width,
        captureHeight: ink.height,
      ),
  ];
  final pageUnitsPerPixel = region.height / ink.height;
  // Fit the space up to the previous line so nothing overlaps it.
  final room =
      math.min(source.band.top - ceiling, prepared.textHeight * .7) *
          pageUnitsPerPixel -
      1;
  final marks = <FuriganaMark>[];
  for (final mark in buildFuriganaMarks(
    inCapture,
    region: region,
    keepInside: keepInside,
  )) {
    final left = ((mark.rect.left - region.left) / region.width * ink.width)
        .floor();
    final right = ((mark.rect.right - region.left) / region.width * ink.width)
        .ceil();
    if (hasPrintedFurigana(
      ink,
      left: left,
      right: right,
      top: source.band.top,
      ceiling: ceiling,
      textHeight: prepared.textHeight,
    )) {
      continue;
    }
    final scale = (room / furiganaFontSize(mark)).clamp(.45, 1.0);
    marks.add(mark.copyWith(scale: scale));
  }
  return marks;
}
