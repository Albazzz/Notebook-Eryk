import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:noteeryk/furigana.dart';

/// A 600×300 capture: two lines of "glyphs" 40 px tall at y 40 and y 118,
/// printed furigana (12 px) above x 100–160 of the second line, and the
/// binding shadow down the right edge.
img.Image _page() {
  final page = img.Image(width: 600, height: 300);
  img.fill(page, color: img.ColorRgb8(250, 248, 240));
  void block(int x, int y, int w, int h) => img.fillRect(
    page,
    x1: x,
    y1: y,
    x2: x + w - 1,
    y2: y + h - 1,
    color: img.ColorRgb8(20, 20, 20),
  );
  for (final top in const [40, 118]) {
    for (var x = 20; x < 560; x += 40) {
      block(x, top, 30, 40);
    }
  }
  block(100, 100, 60, 12); // printed furigana
  block(588, 0, 6, 300); // binding shadow
  return page;
}

InkImage _ink(img.Image image) {
  final luminance = Uint8List(image.width * image.height);
  for (final pixel in image) {
    luminance[pixel.y * image.width + pixel.x] = pixel.luminance.toInt();
  }
  return InkImage(image.width, image.height, luminance);
}

void main() {
  test('tìm dòng chữ thân bài, bỏ furigana in sẵn và gáy sách', () {
    final ink = _ink(_page());
    final bands = findTextBands(ink);
    expect(bands.map((band) => (band.top, band.bottom)), [
      (40, 80),
      (100, 112),
      (118, 158),
    ]);
    expect(typicalTextHeight(bands), 40);
    expect(bodyLines(bands).map((band) => (band.top, band.bottom)), [
      (40, 80),
      (118, 158),
    ]);

    // Furigana printed touching its line: the text is the lower part.
    expect(
      bodyLines(const [
        TextBand(0, 40),
        TextBand(60, 100),
        TextBand(120, 180),
      ]).last.top,
      140,
    );

    expect(
      hasPrintedFurigana(
        ink,
        left: 100,
        right: 140,
        top: 118,
        ceiling: 80,
        textHeight: 40,
      ),
      isTrue,
    );
    expect(
      hasPrintedFurigana(
        ink,
        left: 300,
        right: 340,
        top: 118,
        ceiling: 80,
        textHeight: 40,
      ),
      isFalse,
    );
  });

  test('đọc từng dòng riêng, đặt furigana sát mép trên dòng thật', () async {
    final directory = await Directory.systemTemp.createTemp('furigana_test');
    addTearDown(() => directory.delete(recursive: true));
    final capture = File('${directory.path}/capture.png');
    await capture.writeAsBytes(img.encodePng(_page()));

    final calls = <String>[];
    // Lines are 40 px tall, so they are scaled ×1.2 and get a white border.
    Rect across(img.Image line, double left, double right) {
      const scale = 1.2;
      final border = (line.width - 600 * scale) / 2;
      return Rect.fromLTRB(
        (left * scale + border) / line.width,
        .3,
        (right * scale + border) / line.width,
        .7,
      );
    }

    // Callbacks from the editor hold things an isolate cannot receive (the
    // widget tree); they must not travel with the background work.
    final unsendable = ReceivePort();
    addTearDown(unsendable.close);
    Future<List<OcrLine>> recognize(String path) async {
      calls.add(path);
      expect(unsendable, isNotNull);
      final line = img.decodePng(await File(path).readAsBytes())!;
      if (path.endsWith('.line0.png')) {
        return [
          OcrLine(
            text: '山川',
            box: across(line, 100, 180),
            tokens: const [
              OcrToken(start: 0, length: 1, reading: 'やま'),
              OcrToken(start: 1, length: 1, reading: 'かわ'),
            ],
          ),
        ];
      }
      return [
        // Under the printed furigana: skipped.
        OcrLine(
          text: '海',
          box: across(line, 100, 140),
          tokens: const [OcrToken(start: 0, length: 1, reading: 'うみ')],
        ),
        OcrLine(
          text: '空',
          box: across(line, 300, 340),
          tokens: const [OcrToken(start: 0, length: 1, reading: 'そら')],
        ),
      ];
    }

    // The capture covers page area 0,0–300,150: 2 px per page unit.
    const region = Rect.fromLTWH(0, 0, 300, 150);
    final progress = <int>[];
    final marks = await recognizeFurigana(
      onProgress: (done, _) => progress.add(done + unsendable.hashCode * 0),
      capturePath: capture.path,
      region: region,
      keepInside: region,
      recognize: recognize,
    );

    expect(calls, hasLength(2));
    expect(marks.map((mark) => mark.reading), ['やま', 'かわ', 'そら']);
    final yama = marks.first;
    expect(yama.rect.top, closeTo(20, .01));
    expect(yama.rect.height, closeTo(20, .01));
    expect(yama.rect.left, closeTo(50, .5));
    expect(yama.rect.width, closeTo(20, .5));
    final sora = marks.last;
    expect(sora.rect.top, closeTo(59, .01));
    expect(sora.rect.left, closeTo(150, .5));
    // Line images are deleted once read.
    expect(directory.listSync().map((entry) => entry.uri.pathSegments.last), [
      'capture.png',
    ]);
  });
}
