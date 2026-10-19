import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';

/// Kết quả bảng tô OCR. [terms] rỗng nghĩa là người học để AI tự tìm toàn bộ.
class OcrHighlightResult {
  const OcrHighlightResult({required this.text, required this.terms});

  /// OCR sau khi người học sửa (nếu có).
  final String text;
  final List<String> terms;
}

/// Hiện OCR của vùng khoanh để người học tự tô các cụm cần lưu làm điểm yếu.
/// Trả về null khi người học hủy.
Future<OcrHighlightResult?> showOcrHighlightSheet(
  BuildContext context, {
  required String ocrText,
  String? previewImagePath,
}) => showModalBottomSheet<OcrHighlightResult>(
  context: context,
  isScrollControlled: true,
  // Kéo ngang trên chữ là thao tác tô; tắt kéo-để-đóng để hai cử chỉ không
  // giành nhau.
  enableDrag: false,
  builder: (_) =>
      OcrHighlightSheet(ocrText: ocrText, previewImagePath: previewImagePath),
);

class OcrHighlightSheet extends StatefulWidget {
  const OcrHighlightSheet({
    super.key,
    required this.ocrText,
    this.previewImagePath,
  });

  final String ocrText;

  /// Ảnh vùng khoanh chỉ để người học đối chiếu OCR; không gửi cho AI.
  final String? previewImagePath;

  @override
  State<OcrHighlightSheet> createState() => _OcrHighlightSheetState();
}

class _OcrHighlightSheetState extends State<OcrHighlightSheet> {
  final GlobalKey _textKey = GlobalKey();
  late final TextEditingController _editController = TextEditingController(
    text: widget.ocrText,
  );
  late String _text = widget.ocrText;

  /// Ký tự (rune) cùng vị trí UTF-16 để chuyển từ vị trí con trỏ sang ký tự.
  late List<({int start, String char})> _glyphs = _splitGlyphs(_text);
  late List<int> _glyphOfUnit = _unitIndex(_glyphs, _text.length);
  final Set<int> _selected = {};
  bool _editing = false;

  /// true: đang tô thêm; false: đang xóa tô; null: không kéo.
  bool? _painting;
  int? _lastGlyph;

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  static List<({int start, String char})> _splitGlyphs(String text) {
    final glyphs = <({int start, String char})>[];
    var offset = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      glyphs.add((start: offset, char: char));
      offset += char.length;
    }
    return glyphs;
  }

  static List<int> _unitIndex(
    List<({int start, String char})> glyphs,
    int length,
  ) {
    final index = List<int>.filled(length, 0);
    for (var glyph = 0; glyph < glyphs.length; glyph++) {
      for (var unit = 0; unit < glyphs[glyph].char.length; unit++) {
        index[glyphs[glyph].start + unit] = glyph;
      }
    }
    return index;
  }

  static bool _isSpace(String char) => char.trim().isEmpty;

  static bool _isKanji(String char) {
    final code = char.runes.first;
    return (code >= 0x4e00 && code <= 0x9fff) ||
        (code >= 0x3400 && code <= 0x4dbf) ||
        code == 0x3005; // 々
  }

  static bool _isKatakana(String char) {
    final code = char.runes.first;
    return (code >= 0x30a0 && code <= 0x30ff) || code == 0xff70;
  }

  static bool _isLatinOrDigit(String char) =>
      RegExp(r'[A-Za-z0-9Ａ-Ｚａ-ｚ０-９]').hasMatch(char);

  static const _edgePunctuation = '、。，．,.・「」『』（）()［］[]【】〈〉《》！？!?：:；;…〜~～ 　';

  /// Các cụm liên tiếp đã tô, theo thứ tự trong văn bản.
  List<({int from, int to, String text})> get _runs {
    final runs = <({int from, int to, String text})>[];
    int? from;
    for (var index = 0; index <= _glyphs.length; index++) {
      final selected = index < _glyphs.length && _selected.contains(index);
      if (selected) {
        from ??= index;
        continue;
      }
      if (from != null) {
        var text = _glyphs
            .sublist(from, index)
            .map((glyph) => glyph.char)
            .join();
        // Strip punctuation caught by an imprecise drag, but keep a leading
        // 〜 that marks a grammar pattern.
        while (text.isNotEmpty &&
            _edgePunctuation.contains(text[text.length - 1])) {
          text = text.substring(0, text.length - 1);
        }
        while (text.isNotEmpty &&
            _edgePunctuation.contains(text[0]) &&
            !'〜~～'.contains(text[0])) {
          text = text.substring(1);
        }
        if (text.isNotEmpty) runs.add((from: from, to: index, text: text));
        from = null;
      }
    }
    return runs;
  }

  List<String> get _terms {
    final seen = <String>{};
    return _runs.map((run) => run.text).where(seen.add).toList(growable: false);
  }

  int? _glyphAt(Offset globalPosition) {
    final paragraph = _textKey.currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph) return null;
    final local = paragraph.globalToLocal(globalPosition);
    if (!(Offset.zero & paragraph.size).contains(local)) return null;
    final caret = paragraph.getPositionForOffset(local).offset;
    // The caret lands either before or after the glyph under the finger;
    // check both neighbours against their painted boxes.
    for (final unit in [caret, caret - 1]) {
      if (unit < 0 || unit >= _glyphOfUnit.length) continue;
      final glyph = _glyphOfUnit[unit];
      final start = _glyphs[glyph].start;
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: start,
          extentOffset: start + _glyphs[glyph].char.length,
        ),
      );
      if (boxes.any((box) => box.toRect().inflate(3).contains(local))) {
        return glyph;
      }
    }
    return null;
  }

  void _apply(int glyph, bool paint) {
    if (_isSpace(_glyphs[glyph].char)) return;
    if (paint) {
      _selected.add(glyph);
    } else {
      _selected.remove(glyph);
    }
  }

  /// Chạm: tô cả cụm cùng loại chữ (kanji liền nhau, katakana, chữ Latin);
  /// hiragana tô từng chữ vì có thể là trợ từ. Chạm vào cụm đã tô thì bỏ tô.
  void _onTap(Offset globalPosition) {
    final glyph = _glyphAt(globalPosition);
    if (glyph == null || _isSpace(_glyphs[glyph].char)) return;
    setState(() {
      if (_selected.contains(glyph)) {
        var from = glyph;
        var to = glyph;
        while (from > 0 && _selected.contains(from - 1)) {
          from--;
        }
        while (to < _glyphs.length - 1 && _selected.contains(to + 1)) {
          to++;
        }
        for (var index = from; index <= to; index++) {
          _selected.remove(index);
        }
        return;
      }
      final char = _glyphs[glyph].char;
      final bool Function(String) sameRun = _isKanji(char)
          ? _isKanji
          : _isKatakana(char)
          ? _isKatakana
          : _isLatinOrDigit(char)
          ? _isLatinOrDigit
          : (_) => false;
      var from = glyph;
      var to = glyph;
      while (from > 0 && sameRun(_glyphs[from - 1].char)) {
        from--;
      }
      while (to < _glyphs.length - 1 && sameRun(_glyphs[to + 1].char)) {
        to++;
      }
      for (var index = from; index <= to; index++) {
        _apply(index, true);
      }
    });
  }

  void _startPaint(Offset globalPosition) {
    final glyph = _glyphAt(globalPosition);
    if (glyph == null) {
      _painting = null;
      return;
    }
    setState(() {
      _painting = !_selected.contains(glyph);
      _lastGlyph = glyph;
      _apply(glyph, _painting!);
    });
  }

  void _updatePaint(Offset globalPosition) {
    final painting = _painting;
    if (painting == null) return;
    final glyph = _glyphAt(globalPosition);
    if (glyph == null || glyph == _lastGlyph) return;
    setState(() {
      // A fast stroke skips glyphs between two pointer events; fill the gap.
      final previous = _lastGlyph ?? glyph;
      final from = previous < glyph ? previous : glyph;
      final to = previous < glyph ? glyph : previous;
      for (var index = from; index <= to; index++) {
        if (_glyphs[index].char == '\n') continue;
        _apply(index, painting);
      }
      _lastGlyph = glyph;
    });
  }

  void _endPaint() {
    _painting = null;
    _lastGlyph = null;
  }

  void _removeRun(({int from, int to, String text}) run) => setState(() {
    for (var index = run.from; index < run.to; index++) {
      _selected.remove(index);
    }
  });

  void _toggleEditing() {
    setState(() {
      if (_editing) {
        final edited = _editController.text.trim();
        if (edited != _text) {
          _text = edited;
          _glyphs = _splitGlyphs(_text);
          _glyphOfUnit = _unitIndex(_glyphs, _text.length);
          _selected.clear();
        }
      } else {
        _editController.text = _text;
      }
      _editing = !_editing;
    });
  }

  TextSpan _buildSpan(TextStyle base, Color highlight) {
    final spans = <TextSpan>[];
    final buffer = StringBuffer();
    bool? bufferSelected;
    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: bufferSelected == true
              ? TextStyle(
                  backgroundColor: highlight,
                  fontWeight: FontWeight.w700,
                )
              : null,
        ),
      );
      buffer.clear();
    }

    for (var index = 0; index < _glyphs.length; index++) {
      final selected = _selected.contains(index);
      if (selected != bufferSelected) {
        flush();
        bufferSelected = selected;
      }
      buffer.write(_glyphs[index].char);
    }
    flush();
    return TextSpan(style: base, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final runs = _runs;
    final terms = _terms;
    final imagePath = widget.previewImagePath;
    final media = MediaQuery.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, media.viewInsets.bottom + 14),
        child: SizedBox(
          width: 760,
          height: media.size.height * .86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.border_color, color: AppColors.weakness),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tô cụm cần học',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _toggleEditing,
                    icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
                    label: Text(_editing ? 'Xong' : 'Sửa OCR'),
                  ),
                ],
              ),
              Text(
                _editing
                    ? 'Sửa chữ nhận dạng sai rồi bấm Xong để tô.'
                    : 'Chạm một từ để tô, kéo ngang hoặc giữ rồi kéo để tô nhiều chữ. Chạm lại cụm đã tô để bỏ.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              if (imagePath != null && File(imagePath).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(imagePath),
                    height: 72,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: _editing
                      ? TextField(
                          controller: _editController,
                          autofocus: true,
                          expands: true,
                          maxLines: null,
                          style: const TextStyle(fontSize: 20, height: 1.6),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            filled: false,
                          ),
                        )
                      : SingleChildScrollView(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) =>
                                _onTap(details.globalPosition),
                            onHorizontalDragStart: (details) =>
                                _startPaint(details.globalPosition),
                            onHorizontalDragUpdate: (details) =>
                                _updatePaint(details.globalPosition),
                            onHorizontalDragEnd: (_) => _endPaint(),
                            onHorizontalDragCancel: _endPaint,
                            onLongPressStart: (details) =>
                                _startPaint(details.globalPosition),
                            onLongPressMoveUpdate: (details) =>
                                _updatePaint(details.globalPosition),
                            onLongPressEnd: (_) => _endPaint(),
                            child: SizedBox(
                              width: double.infinity,
                              child: RichText(
                                key: _textKey,
                                text: _buildSpan(
                                  TextStyle(
                                    fontSize: 24,
                                    height: 1.9,
                                    letterSpacing: 1.5,
                                    color: scheme.onSurface,
                                  ),
                                  AppColors.weakness.withValues(alpha: .3),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: runs.isEmpty
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Chưa tô cụm nào.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: runs.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (_, index) => InputChip(
                          label: Text(runs[index].text),
                          onDeleted: () => _removeRun(runs[index]),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_selected.clear),
                      child: const Text('Bỏ tô hết'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _editing
                        ? null
                        : () => Navigator.pop(
                            context,
                            OcrHighlightResult(text: _text, terms: const []),
                          ),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('AI tự tìm'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.weakness,
                    ),
                    onPressed: terms.isEmpty || _editing
                        ? null
                        : () => Navigator.pop(
                            context,
                            OcrHighlightResult(text: _text, terms: terms),
                          ),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(
                      terms.isEmpty
                          ? 'Tạo điểm yếu'
                          : 'Tạo điểm yếu (${terms.length})',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
