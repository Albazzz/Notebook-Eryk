import 'package:flutter/material.dart';

import 'color_panel.dart';

/// Kết quả soạn một hộp văn bản.
class TextBoxEdit {
  const TextBoxEdit({
    required this.text,
    required this.fontSize,
    required this.color,
  });
  final String text;
  final double fontSize;
  final Color color;
}

/// Bảng gõ chữ từ bàn phím. Trả về null khi người dùng hủy.
Future<TextBoxEdit?> showTextBoxEditor(
  BuildContext context, {
  String text = '',
  required double fontSize,
  required Color color,
}) => showModalBottomSheet<TextBoxEdit>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      _TextBoxEditorSheet(text: text, fontSize: fontSize, color: color),
);

class _TextBoxEditorSheet extends StatefulWidget {
  const _TextBoxEditorSheet({
    required this.text,
    required this.fontSize,
    required this.color,
  });
  final String text;
  final double fontSize;
  final Color color;

  @override
  State<_TextBoxEditorSheet> createState() => _TextBoxEditorSheetState();
}

class _TextBoxEditorSheetState extends State<_TextBoxEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  late double _fontSize = widget.fontSize.clamp(12, 48);
  late Color _color = widget.color;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(
    context,
    TextBoxEdit(text: _controller.text, fontSize: _fontSize, color: _color),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.text.isEmpty ? 'Thêm văn bản' : 'Sửa văn bản',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('text-box-field'),
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                style: TextStyle(fontSize: _fontSize, color: _color),
                decoration: const InputDecoration(
                  hintText: 'Gõ nội dung, có thể dùng bàn phím tiếng Nhật',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Cỡ chữ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 12,
                      max: 48,
                      divisions: 36,
                      label: '${_fontSize.round()}',
                      onChanged: (value) => setState(() => _fontSize = value),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${_fontSize.round()}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final color in colorPanelPresets)
                    GestureDetector(
                      onTap: () => setState(() => _color = color),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: color.toARGB32() == _color.toARGB32()
                                ? scheme.primary
                                : scheme.outline.withValues(alpha: .4),
                            width: color.toARGB32() == _color.toARGB32()
                                ? 3
                                : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _done, child: const Text('Xong')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
