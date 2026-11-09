import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';

/// Bảng tạo điểm yếu từ văn bản gõ tay. Trả về số mục đã xử lý khi lưu.
Future<int?> showWeakPointInputSheet(BuildContext context, AppState state) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => WeakPointInputSheet(state: state),
    );

class _ReviewItem {
  _ReviewItem(this.draft, {required this.duplicate, this.unprocessed = false})
    : selected = duplicate == null;
  final WeakPointDraft draft;
  final WeakPoint? duplicate;
  final bool unprocessed;
  bool selected;
}

/// Gõ hoặc dán văn bản bất kỳ: AI tự rút ra các điểm cần học, điền nội dung theo
/// từng lô rồi người học duyệt trước khi lưu.
class WeakPointInputSheet extends StatefulWidget {
  const WeakPointInputSheet({super.key, required this.state});
  final AppState state;

  @override
  State<WeakPointInputSheet> createState() => _WeakPointInputSheetState();
}

class _WeakPointInputSheetState extends State<WeakPointInputSheet> {
  final TextEditingController _controller = TextEditingController();

  /// null: để AI tự nhận loại.
  WeaknessKind? _kind;
  bool _running = false;

  /// Đang ở bước AI đọc văn bản, chưa tới bước điền theo lô.
  bool _reading = false;

  /// Cấp ghi trong văn bản theo tiêu đề đã chuẩn hóa, dùng để gắn thẻ.
  final Map<String, String> _levels = {};
  int _completed = 0;
  int _total = 0;
  String? _error;
  List<String> _warnings = const [];
  List<_ReviewItem>? _review;

  AppState get state => widget.state;
  List<String> get _lines => parseTypedWeakPoints(_controller.text);
  bool get _hasText => _controller.text.trim().isNotEmpty;

  /// Cả khi AI đổi nhẹ tiêu đề (thêm 〜, bỏ dấu cách) vẫn khớp được cấp độ.
  String _levelKey(String title) => title.replaceAll(RegExp(r'[\s〜~～]'), '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _running = true;
      _reading = true;
      _completed = 0;
      _total = 0;
      _error = null;
    });
    final List<TypedWeakPointSeed> seeds;
    final String readWarning;
    try {
      final extracted = await state.aiService.extractTypedWeakPoints(
        apiKey: state.apiKey,
        modelId: state.modelIdFor(AiTask.createWeakPoint),
        text: _controller.text,
        jlpt: state.jlpt,
        language: state.explanationLanguage,
        kind: _kind,
      );
      seeds = extracted.seeds;
      readWarning = extracted.warning;
    } catch (error) {
      if (mounted) {
        setState(() {
          _running = false;
          _reading = false;
          _error = 'Không đọc được văn bản: ${_describe(error)}';
        });
      }
      return;
    }
    if (!mounted) return;
    if (seeds.isEmpty) {
      setState(() {
        _running = false;
        _reading = false;
        _error = 'AI không tìm thấy điểm cần học nào trong văn bản này.';
      });
      return;
    }
    _levels
      ..clear()
      ..addAll({
        for (final seed in seeds)
          if (seed.level.isNotEmpty) _levelKey(seed.title): seed.level,
      });
    final byTerm = {for (final seed in seeds) seed.promptText: seed};
    final requests = [
      for (final part in chunked(
        seeds.map((seed) => seed.promptText).toList(),
        weakPointBatchSize,
      ))
        WeakPointDraftRequest(text: '', terms: part),
    ];
    setState(() {
      _reading = false;
      _total = requests.length;
    });
    final run = await state.draftWeakPoints(
      requests,
      typedInput: true,
      forcedKind: _kind,
      isCancelled: () => !mounted,
      onProgress: (completed, total) {
        if (mounted) setState(() => _completed = completed);
      },
    );
    if (!mounted) return;
    if (run.items.isEmpty) {
      setState(() {
        _running = false;
        _error = run.error == null
            ? 'AI không trả về mục nào. Hãy thử lại.'
            : 'Không tạo được: ${_describe(run.error!)}';
      });
      return;
    }
    final verified = await state.verifyDraftsWithDictionary(run.items);
    if (!mounted) return;
    final failedSeeds = [
      for (final request in run.failed)
        for (final term in request.terms) byTerm[term]!,
    ];
    setState(() {
      _running = false;
      _warnings = [if (readWarning.isNotEmpty) readWarning, ...run.warnings];
      _review = [
        for (final draft in verified)
          _ReviewItem(
            draft,
            duplicate: state.findDuplicateWeakPoint(draft.kind, draft.title),
          ),
        for (final seed in failedSeeds)
          _ReviewItem(
            WeakPointDraft(
              title: seed.title,
              kind: _kind ?? WeaknessKind.grammar,
              content: seed.notes,
              warning: 'AI chưa xử lý được mục này, hãy bổ sung sau khi lưu.',
            ),
            duplicate: null,
            unprocessed: true,
          ),
      ];
    });
  }

  String _describe(Object error) => error
      .toString()
      .replaceFirst('FormatException: ', '')
      .replaceFirst('HttpException: ', '');

  /// Dòng dạng "mẫu: nghĩa" được tách thành tiêu đề và nghĩa.
  WeakPointDraft _titleOnlyDraft(String line) {
    final match = RegExp(r'^(.+?)\s*[:：]\s*(.+)$').firstMatch(line);
    return WeakPointDraft(
      title: (match?.group(1) ?? line).trim(),
      kind: _kind ?? WeaknessKind.grammar,
      content: (match?.group(2) ?? '').trim(),
    );
  }

  /// Không gọi AI: furigana, Hán Việt và nghĩa còn thiếu lấy từ từ điển.
  Future<void> _saveWithoutAi() async {
    final items = <_ReviewItem>[];
    for (final line in _lines) {
      final typed = _titleOnlyDraft(line);
      final fill = await state.dictionaryFillFor(typed.title);
      if (!mounted) return;
      final kind = _kind ?? fill?.suggestedKind ?? typed.kind;
      final lexical =
          kind == WeaknessKind.vocabulary || kind == WeaknessKind.kanji;
      items.add(
        _ReviewItem(
          WeakPointDraft(
            title: typed.title,
            kind: kind,
            content: typed.content.isNotEmpty
                ? typed.content
                : fill?.meaning ?? '',
            reading: lexical ? fill?.reading ?? '' : '',
            hanViet: lexical ? fill?.hanViet ?? '' : '',
          ),
          duplicate: state.findDuplicateWeakPoint(kind, typed.title),
          unprocessed: true,
        ),
      );
    }
    _save(items);
  }

  void _save(List<_ReviewItem> items) {
    var count = 0;
    for (final (index, item) in items.indexed) {
      final duplicate = item.duplicate;
      if (duplicate != null) {
        // Already saved: send it back to review instead of creating a copy.
        if (item.selected || _review == null) {
          state.reencounterWeakPoint(duplicate);
          count++;
        }
        continue;
      }
      if (!item.selected) continue;
      final draft = item.draft;
      state.addWeakPoint(
        WeakPoint(
          id: '${DateTime.now().microsecondsSinceEpoch}_$index',
          title: draft.title,
          kind: draft.kind,
          content: draft.content,
          reminder: draft.reminder,
          note: '',
          tags: [_levels[_levelKey(draft.title)] ?? state.jlpt],
          notebookId: '',
          notebookTitle: '',
          page: 1,
          ocrText: '',
          reading: draft.reading,
          hanViet: draft.hanViet,
          conjugation: draft.conjugation,
          examples: draft.examples,
          sourceSentence: draft.sourceSentence,
          correctAnswer: draft.correctAnswer,
          mistake: draft.mistake,
          warning: draft.warning,
          createdAt: DateTime.now(),
          formatVersion: item.unprocessed ? 0 : weakPointFormatVersion,
        ),
      );
      count++;
    }
    Navigator.pop(context, count);
  }

  @override
  Widget build(BuildContext context) {
    // With the keyboard up, take all the room left above it (minus the status
    // bar and drag handle) so the field and buttons stay on screen.
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final height = keyboard > 0
        ? media.size.height - keyboard - media.padding.top - 72
        : media.size.height * .82;
    final review = _review;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, keyboard + 16),
        child: SizedBox(
          height: height.clamp(0, double.infinity).toDouble(),
          child: review == null ? _buildInput() : _buildReview(review),
        ),
      ),
    );
  }

  Widget _buildInput() => LayoutBuilder(
    builder: (context, constraints) {
      // Too short for a comfortable field (big keyboard, small window):
      // give the field a fixed height and let the whole sheet scroll
      // instead of squeezing the text over the chips.
      const minField = 160.0;
      final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
      final fixed = keyboardUp ? 200.0 : 260.0;
      if (constraints.maxHeight >= fixed + minField) {
        return _inputContent(keyboardUp: keyboardUp, fieldHeight: null);
      }
      return SingleChildScrollView(
        child: _inputContent(keyboardUp: keyboardUp, fieldHeight: minField),
      );
    },
  );

  Widget _inputContent({required bool keyboardUp, double? fieldHeight}) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final lines = _lines;
    final field = TextField(
      key: const ValueKey('weak-point-input'),
      controller: _controller,
      enabled: !_running,
      autofocus: true,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        hintText: '〜とはいえ [N2]: dẫu nói là... nhưng\n〜わけではない\n〜にもかかわらず: mặc dù',
      ),
    );
    return Column(
      mainAxisSize: fieldHeight == null ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Nhập điểm yếu', style: Theme.of(context).textTheme.headlineSmall),
        // While typing the field needs the room more than the explanation.
        if (!keyboardUp) ...[
          const SizedBox(height: 4),
          Text(
            'Gõ hoặc dán ghi chú bất kỳ, tiếng Việt xen tiếng Nhật cũng được. AI tự rút ra các mẫu ngữ pháp và từ cần học, bạn duyệt rồi mới lưu.',
            style: TextStyle(color: muted),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Tự nhận loại'),
              selected: _kind == null,
              onSelected: _running ? null : (_) => setState(() => _kind = null),
            ),
            for (final kind in const [
              WeaknessKind.grammar,
              WeaknessKind.vocabulary,
              WeaknessKind.kanji,
            ])
              ChoiceChip(
                label: Text('Chỉ ${kind.label}'),
                selected: _kind == kind,
                onSelected: _running
                    ? null
                    : (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (fieldHeight == null)
          Expanded(child: field)
        else
          SizedBox(height: fieldHeight, child: field),
        const SizedBox(height: 8),
        if (_running) ...[
          LinearProgressIndicator(
            value: _reading || _total == 0 ? null : _completed / _total,
          ),
          const SizedBox(height: 4),
          Text(
            _reading
                ? 'AI đang đọc văn bản...'
                : 'Đang tạo · lô $_completed/$_total, mỗi lô tối đa $weakPointBatchSize mục',
          ),
        ] else if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          )
        else if (!state.aiConnected)
          Text(
            'Chưa có API key: chỉ lưu được các dòng mở đầu bằng tiếng Nhật, nội dung bạn tự điền sau.',
            style: TextStyle(color: muted),
          ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 6,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            OutlinedButton(
              onPressed: _running || lines.isEmpty ? null : _saveWithoutAi,
              child: Text(
                lines.isEmpty
                    ? 'Lưu không dùng AI'
                    : 'Lưu ${lines.length} dòng, không dùng AI',
              ),
            ),
            FilledButton.icon(
              onPressed: _running || !_hasText || !state.aiConnected
                  ? null
                  : _generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Tạo bằng AI'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReview(List<_ReviewItem> items) {
    final scheme = Theme.of(context).colorScheme;
    final selected = items.where((item) => item.selected).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Duyệt điểm yếu (${items.length})',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Bỏ tích mục không cần. Sau khi lưu có thể sửa từng mục trong danh sách.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        for (final warning in _warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              warning,
              style: const TextStyle(color: AppColors.weakness),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final draft = item.draft;
              final notes = [
                if (draft.conjugation.isNotEmpty) draft.conjugation,
                if (draft.reading.isNotEmpty) draft.reading,
                if (draft.examples.isNotEmpty) draft.examples.first,
              ];
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: item.selected,
                onChanged: (value) =>
                    setState(() => item.selected = value == true),
                title: Text(
                  draft.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.kind.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    if (draft.content.isNotEmpty) Text(draft.content),
                    for (final note in notes)
                      Text(
                        note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    if (item.duplicate != null)
                      const Text(
                        'Đã có trong sổ. Nếu tích, mục cũ được đưa lên ôn lại.',
                        style: TextStyle(color: AppColors.weakness),
                      ),
                    if (draft.warning.isNotEmpty)
                      Text(
                        draft.warning,
                        style: const TextStyle(color: AppColors.weakness),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => setState(() => _review = null),
              child: const Text('Quay lại'),
            ),
            FilledButton.icon(
              onPressed: selected == 0 ? null : () => _save(items),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text('Lưu $selected mục'),
            ),
          ],
        ),
      ],
    );
  }
}
