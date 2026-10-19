import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../review.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'deck_library_screen.dart';
import 'review_screen.dart';

enum _WeaknessSort { newest, oldest, title, notebook, due, lapses }

extension on _WeaknessSort {
  String get label => switch (this) {
    _WeaknessSort.newest => 'Mới lưu gần đây',
    _WeaknessSort.oldest => 'Lưu lâu nhất',
    _WeaknessSort.title => 'Tên A–Z',
    _WeaknessSort.notebook => 'Theo vở',
    _WeaknessSort.due => 'Đến hạn ôn trước',
    _WeaknessSort.lapses => 'Hay quên nhất',
  };
}

const _allLabel = 'Tất cả';
const _jlptLevels = ['N1', 'N2', 'N3', 'N4', 'N5'];

class WeaknessesScreen extends StatefulWidget {
  const WeaknessesScreen({super.key, required this.state});
  final AppState state;

  @override
  State<WeaknessesScreen> createState() => _WeaknessesScreenState();
}

class _WeaknessesScreenState extends State<WeaknessesScreen> {
  WeaknessKind? kindFilter;
  String jlptFilter = _allLabel;
  String typeFilter = _allLabel;
  bool dueOnly = false;
  String search = '';
  _WeaknessSort sort = _WeaknessSort.newest;

  /// Non-empty while multi-select mode is active.
  final Set<String> selected = {};
  bool selecting = false;
  bool _reformatting = false;
  int _reformatProgress = 0;
  int _reformatTotal = 0;

  AppState get state => widget.state;

  List<WeakPoint> _visibleItems() {
    final query = search.trim().toLowerCase();
    final now = DateTime.now();
    final items = state.weakPoints.where((item) {
      if (kindFilter != null && item.kind != kindFilter) return false;
      if (jlptFilter != _allLabel && !item.tags.contains(jlptFilter)) {
        return false;
      }
      if (typeFilter != _allLabel && !item.tags.contains(typeFilter)) {
        return false;
      }
      if (dueOnly && !item.isDue(now)) return false;
      if (query.isEmpty) return true;
      final haystack = [
        item.title,
        item.content,
        item.reading,
        item.hanViet,
        item.reminder,
        item.mistake,
        item.note,
        item.sourceSentence,
        item.notebookTitle,
        ...item.examples,
        ...item.tags,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    int byDate(WeakPoint a, WeakPoint b) => b.createdAt.compareTo(a.createdAt);
    switch (sort) {
      case _WeaknessSort.newest:
        items.sort(byDate);
      case _WeaknessSort.oldest:
        items.sort((a, b) => byDate(b, a));
      case _WeaknessSort.title:
        items.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _WeaknessSort.notebook:
        items.sort((a, b) {
          final byNotebook = a.notebookTitle.compareTo(b.notebookTitle);
          return byNotebook != 0 ? byNotebook : a.page.compareTo(b.page);
        });
      case _WeaknessSort.due:
        items.sort(
          (a, b) => (a.dueAt ?? DateTime(0)).compareTo(b.dueAt ?? DateTime(0)),
        );
      case _WeaknessSort.lapses:
        items.sort((a, b) {
          final byLapses = b.lapses.compareTo(a.lapses);
          return byLapses != 0 ? byLapses : byDate(a, b);
        });
    }
    return items;
  }

  List<String> get _questionTypeTags {
    final tags = <String>{
      for (final item in state.weakPoints)
        ...item.tags.where((tag) => tag.startsWith('問題:')),
    }.toList()..sort();
    return tags;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final items = _visibleItems();
        final dueCount = state.dueWeakPoints.length;
        selected.removeWhere(
          (id) => !state.weakPoints.any((item) => item.id == id),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Column(
            children: [
              PageHeader(
                title: 'Điểm yếu',
                subtitle:
                    '${state.weakPoints.length} mục · $dueCount thẻ đến hạn ôn hôm nay',
                trailing: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: state.weakPoints.isEmpty ? null : _openReview,
                      icon: const Icon(Icons.style_outlined),
                      label: Text(
                        dueCount == 0 ? 'Ôn tập' : 'Ôn tập ($dueCount)',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DeckLibraryScreen(state: state),
                        ),
                      ),
                      icon: const Icon(Icons.collections_bookmark_outlined),
                      label: Text(
                        state.decks.isEmpty
                            ? 'Bộ flashcard'
                            : 'Bộ flashcard (${state.decks.length})',
                      ),
                    ),
                    SearchBox(
                      hint: 'Tìm từ, cách đọc, Hán Việt, thẻ...',
                      width: 260,
                      onChanged: (value) => setState(() => search = value),
                    ),
                    DropdownButton<_WeaknessSort>(
                      value: sort,
                      items: _WeaknessSort.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => sort = value ?? sort),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Thêm',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'select') {
                          setState(() => selecting = true);
                        } else if (value == 'export') {
                          _exportAnki(items);
                        } else if (value == 'reformat') {
                          _reformatAll();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'select',
                          child: Text('Chọn nhiều'),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          child: Text('Xuất Anki (danh sách đang lọc)'),
                        ),
                        PopupMenuItem(
                          value: 'reformat',
                          child: Text('Chuẩn hóa Điểm yếu'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_reformatting) ...[
                LinearProgressIndicator(
                  value: _reformatTotal == 0
                      ? null
                      : _reformatProgress / _reformatTotal,
                ),
                Text('Đang chuẩn hóa $_reformatProgress/$_reformatTotal mục…'),
              ],
              if (state.weakPoints.isNotEmpty)
                _StatsStrip(points: state.weakPoints),
              const SizedBox(height: 12),
              _buildFilters(),
              const SizedBox(height: 12),
              if (selecting) _buildSelectionBar(items),
              Expanded(
                child: items.isEmpty
                    ? _EmptyWeakness(
                        filtered: state.weakPoints.isNotEmpty,
                        onOpenRecent: state.notebooks.isEmpty
                            ? null
                            : () => state.open(state.notebooks.first),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 30),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Dismissible(
                            key: ValueKey('weakness-${item.id}'),
                            direction: selecting
                                ? DismissDirection.none
                                : DismissDirection.endToStart,
                            background: const _DeleteBackground(),
                            onDismissed: (_) => _delete([item.id]),
                            child: _WeaknessItem(
                              item: item,
                              selecting: selecting,
                              selected: selected.contains(item.id),
                              onOpen: () => selecting
                                  ? _toggleSelected(item)
                                  : _showDetail(item),
                              onLongPress: () => setState(() {
                                selecting = true;
                                selected.add(item.id);
                              }),
                              onEdit: () => _edit(item),
                              onSource: () => _openSource(item),
                              onDelete: () => _confirmDelete([item]),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilters() {
    final types = _questionTypeTags;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            label: const Text(_allLabel),
            selected: kindFilter == null,
            onSelected: (_) => setState(() => kindFilter = null),
          ),
          ...WeaknessKind.values.map(
            (kind) => ChoiceChip(
              label: Text(kind.label),
              selected: kindFilter == kind,
              onSelected: (_) => setState(() => kindFilter = kind),
            ),
          ),
          FilterChip(
            label: const Text('Đến hạn'),
            selected: dueOnly,
            onSelected: (value) => setState(() => dueOnly = value),
          ),
          DropdownButton<String>(
            value: jlptFilter,
            underline: const SizedBox.shrink(),
            items: [_allLabel, ..._jlptLevels]
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(value == _allLabel ? 'Mọi cấp JLPT' : value),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => jlptFilter = value ?? _allLabel),
          ),
          if (types.isNotEmpty)
            DropdownButton<String>(
              value: types.contains(typeFilter) ? typeFilter : _allLabel,
              underline: const SizedBox.shrink(),
              items: [_allLabel, ...types]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == _allLabel
                            ? 'Mọi dạng đề'
                            : jlptQuestionTypeFrom(
                                value.replaceFirst('問題:', ''),
                              ).label,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => typeFilter = value ?? _allLabel),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(List<WeakPoint> items) {
    final chosen = state.weakPoints
        .where((item) => selected.contains(item.id))
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Đã chọn ${chosen.length}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextButton(
            onPressed: () => setState(() {
              final allVisible = items.every(
                (item) => selected.contains(item.id),
              );
              if (allVisible) {
                selected.removeAll(items.map((item) => item.id));
              } else {
                selected.addAll(items.map((item) => item.id));
              }
            }),
            child: const Text('Chọn tất cả / bỏ chọn'),
          ),
          TextButton.icon(
            onPressed: chosen.isEmpty ? null : () => _openReview(queue: chosen),
            icon: const Icon(Icons.style_outlined),
            label: const Text('Ôn các mục này'),
          ),
          TextButton.icon(
            onPressed: chosen.isEmpty ? null : () => _createDeckFrom(chosen),
            icon: const Icon(Icons.collections_bookmark_outlined),
            label: const Text('Tạo bộ'),
          ),
          TextButton.icon(
            onPressed: chosen.isEmpty ? null : () => _exportAnki(chosen),
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('Xuất Anki'),
          ),
          TextButton.icon(
            onPressed: chosen.isEmpty ? null : () => _confirmDelete(chosen),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Xóa'),
          ),
          TextButton(
            onPressed: () => setState(() {
              selecting = false;
              selected.clear();
            }),
            child: const Text('Xong'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDeckFrom(List<WeakPoint> points) async {
    final controller = TextEditingController(
      text: 'Bộ ${state.decks.length + 1}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Tạo bộ từ ${points.length} mục'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên bộ'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Tạo bộ'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (name == null || !mounted) return;
    final deck = state.createDeck(name, points);
    setState(() {
      selecting = false;
      selected.clear();
    });
    showAppSnack(
      context,
      'Đã tạo ${deck.name} (${points.length} thẻ)',
      actionLabel: 'Mở',
      onAction: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DeckDetailScreen(state: state, deck: deck),
        ),
      ),
    );
  }

  void _toggleSelected(WeakPoint item) => setState(() {
    if (!selected.remove(item.id)) selected.add(item.id);
  });

  Future<void> _openReview({List<WeakPoint>? queue}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(state: state, initialQueue: queue),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _reformatAll() async {
    if (_reformatting || state.weakPoints.isEmpty) return;
    if (!state.aiConnected) {
      showAppSnack(context, 'Hãy thiết lập OpenRouter trong Cài đặt AI');
      return;
    }
    final pending = state.unnormalizedWeakPointCount;
    final normalized = state.weakPoints.length - pending;
    // 'pending': chỉ mục chưa chuẩn; 'all': làm lại cả mục đã chuẩn.
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chuẩn hóa Điểm yếu?'),
        content: Text(
          [
            pending == 0
                ? 'Tất cả ${state.weakPoints.length} mục đã được chuẩn hóa.'
                : '$pending mục chưa chuẩn hóa sẽ được AI xử lý theo lô.',
            if (normalized > 0 && pending > 0)
              '$normalized mục đã chuẩn hóa được bỏ qua để không tốn token.',
            'Động từ đưa về thể ます, từ loại khác về dạng đứng đơn. Ghi chú riêng, thẻ, nguồn và lịch ôn được giữ lại.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          if (normalized > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, 'all'),
              child: Text('Làm lại tất cả (${state.weakPoints.length})'),
            ),
          if (pending > 0)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'pending'),
              child: Text('Chuẩn hóa $pending mục'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final includeNormalized = choice == 'all';
    setState(() {
      _reformatting = true;
      _reformatProgress = 0;
      _reformatTotal = includeNormalized ? state.weakPoints.length : pending;
    });
    try {
      final result = await state.reformatAllWeakPoints(
        includeNormalized: includeNormalized,
        onProgress: (done, _) {
          if (mounted) setState(() => _reformatProgress = done);
        },
      );
      if (mounted) {
        showAppSnack(
          context,
          [
            'Đã chuẩn hóa ${result.updated} mục',
            if (result.failed > 0) '${result.failed} mục cần thử lại',
            if (result.skipped > 0) 'bỏ qua ${result.skipped} mục đã chuẩn',
          ].join(' · '),
        );
      }
    } catch (error) {
      if (mounted) showAppSnack(context, 'Không thể chuẩn hóa: $error');
    } finally {
      if (mounted) setState(() => _reformatting = false);
    }
  }

  Future<void> _exportAnki(List<WeakPoint> items) async {
    if (items.isEmpty) {
      showAppSnack(context, 'Không có điểm yếu nào để xuất');
      return;
    }
    try {
      final file = await state.exportWeakPointsToAnki(items);
      if (!mounted) return;
      showAppSnack(
        context,
        'Đã xuất ${items.length} thẻ: Tệp › Note Eryk › Exports › ${file.uri.pathSegments.last}. Trong Anki chọn Import file.',
      );
    } catch (error) {
      if (mounted) showAppSnack(context, 'Không xuất được file Anki: $error');
    }
  }

  void _openSource(WeakPoint item) {
    final notebook = state.notebooks
        .where((notebook) => notebook.id == item.notebookId)
        .firstOrNull;
    if (notebook == null) {
      showAppSnack(context, 'Không còn tìm thấy vở nguồn');
      return;
    }
    state.open(notebook, page: item.page, source: true);
  }

  Future<void> _showDetail(WeakPoint item) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const Expanded(
                      child: Text(
                        'Điểm yếu / Chi tiết',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'review'),
                      icon: const Icon(Icons.style_outlined),
                      label: const Text('Ôn thẻ này'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'edit'),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Sửa'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Xóa',
                      onPressed: () => Navigator.pop(context, 'delete'),
                      color: Theme.of(context).colorScheme.error,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth > 720;
                      final details = _DetailText(item: item);
                      final source = _SourcePanel(
                        item: item,
                        showOcr: state.showOcrInAiResults,
                        onOpenSource: () => Navigator.pop(context, 'source'),
                      );
                      return twoColumns
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: SingleChildScrollView(child: details),
                                ),
                                const SizedBox(width: 22),
                                Expanded(
                                  flex: 4,
                                  child: SingleChildScrollView(child: source),
                                ),
                              ],
                            )
                          : ListView(
                              children: [
                                details,
                                const SizedBox(height: 18),
                                source,
                              ],
                            );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    switch (action) {
      case 'edit':
        await _edit(item);
      case 'delete':
        await _confirmDelete([item]);
      case 'source':
        _openSource(item);
      case 'review':
        await _openReview(queue: [item]);
    }
  }

  Future<void> _edit(WeakPoint item) async {
    final title = TextEditingController(text: item.title);
    final content = TextEditingController(text: item.content);
    final reminder = TextEditingController(text: item.reminder);
    final note = TextEditingController(text: item.note);
    final reading = TextEditingController(text: item.reading);
    final hanViet = TextEditingController(text: item.hanViet);
    final conjugation = TextEditingController(text: item.conjugation);
    final examples = TextEditingController(text: item.examples.join('\n'));
    final sourceSentence = TextEditingController(text: item.sourceSentence);
    final correctAnswer = TextEditingController(text: item.correctAnswer);
    final mistake = TextEditingController(text: item.mistake);
    final tagInput = TextEditingController();
    final tags = List<String>.of(item.tags);
    var warning = item.warning;
    var kind = item.kind;
    final controllers = [
      title,
      content,
      reminder,
      note,
      reading,
      hanViet,
      conjugation,
      examples,
      sourceSentence,
      correctAnswer,
      mistake,
      tagInput,
    ];
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Widget field(
            TextEditingController controller,
            String label, {
            int minLines = 1,
            int maxLines = 4,
          }) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
              decoration: InputDecoration(labelText: label),
            ),
          );
          void addTag() {
            final tag = tagInput.text.trim();
            if (tag.isEmpty || tags.contains(tag)) return;
            setSheetState(() {
              tags.add(tag);
              tagInput.clear();
            });
          }

          final lexical = {
            WeaknessKind.vocabulary,
            WeaknessKind.kanji,
          }.contains(kind);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sửa điểm yếu',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 18),
                  field(title, 'Tên'),
                  DropdownButtonFormField<WeaknessKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Loại'),
                    items: WeaknessKind.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => kind = value ?? kind),
                  ),
                  const SizedBox(height: 12),
                  if (lexical) ...[
                    field(reading, 'Cách đọc (よみ / furigana)'),
                    field(hanViet, 'Hán Việt'),
                  ],
                  field(content, 'Nghĩa', minLines: 2),
                  if (kind == WeaknessKind.grammar)
                    field(conjugation, 'Cách nối (接続)', minLines: 2),
                  field(examples, 'Ví dụ (mỗi dòng một ví dụ)', minLines: 2),
                  field(sourceSentence, 'Câu gốc', minLines: 2),
                  field(correctAnswer, 'Đáp án đúng'),
                  field(mistake, 'Chỗ dễ nhầm', minLines: 2),
                  field(reminder, 'Mẹo nhớ', minLines: 1, maxLines: 3),
                  field(note, 'Ghi chú của tôi', minLines: 2, maxLines: 3),
                  if (warning.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InputChip(
                        avatar: const Icon(Icons.help_outline, size: 18),
                        label: Text('Cần kiểm tra: $warning'),
                        onDeleted: () => setSheetState(() => warning = ''),
                        deleteButtonTooltipMessage: 'Đã kiểm tra',
                      ),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...tags.map(
                        (tag) => InputChip(
                          label: Text(tag),
                          onDeleted: () =>
                              setSheetState(() => tags.remove(tag)),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: tagInput,
                          onSubmitted: (_) => addTag(),
                          decoration: const InputDecoration(
                            hintText: 'Thêm thẻ',
                            isDense: true,
                          ),
                        ),
                      ),
                      ActionChip(
                        label: const Text('+ Thêm'),
                        onPressed: addTag,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          state.resetWeakPointSchedule([item.id]);
                          Navigator.pop(context, false);
                          showAppSnack(this.context, 'Đã đặt lại lịch ôn');
                        },
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Học lại từ đầu'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          if (title.text.trim().isEmpty) return;
                          item.title = title.text.trim();
                          item.kind = kind;
                          item.content = content.text.trim();
                          item.reminder = reminder.text.trim();
                          item.note = note.text.trim();
                          item.reading = reading.text.trim();
                          item.hanViet = hanViet.text.trim();
                          item.conjugation = conjugation.text.trim();
                          item.examples = examples.text
                              .split('\n')
                              .map((line) => line.trim())
                              .where((line) => line.isNotEmpty)
                              .toList();
                          item.sourceSentence = sourceSentence.text.trim();
                          item.correctAnswer = correctAnswer.text.trim();
                          item.mistake = mistake.text.trim();
                          item.warning = warning;
                          item.tags = tags;
                          state.updateWeakPoint(item);
                          Navigator.pop(context, true);
                        },
                        child: const Text('Lưu thay đổi'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in controllers) {
      controller.dispose();
    }
    if (saved == true && mounted) showAppSnack(context, 'Đã lưu thay đổi');
  }

  Future<void> _confirmDelete(List<WeakPoint> items) async {
    final single = items.length == 1;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        title: Text(single ? 'Xóa điểm yếu?' : 'Xóa ${items.length} điểm yếu?'),
        content: Text(
          single
              ? '“${items.first.title}” sẽ bị xóa khỏi danh sách ôn tập. Nội dung vở gốc không thay đổi.'
              : 'Các mục đã chọn sẽ bị xóa khỏi danh sách ôn tập. Nội dung vở gốc không thay đổi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (accepted == true) _delete(items.map((item) => item.id));
  }

  void _delete(Iterable<String> ids) {
    final removed = state.deleteWeakPoints(ids);
    if (removed.isEmpty || !mounted) return;
    setState(() {
      selected.removeAll(removed.map((entry) => entry.point.id));
      if (selected.isEmpty) selecting = false;
    });
    // Undo is a safety net, so show it even when optional notifications are
    // turned off in Settings.
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 7),
        content: Text(
          removed.length == 1
              ? 'Đã xóa “${removed.first.point.title}”'
              : 'Đã xóa ${removed.length} điểm yếu',
        ),
        action: SnackBarAction(
          label: 'Hoàn tác',
          onPressed: () => state.restoreWeakPoints(removed),
        ),
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.points});
  final List<WeakPoint> points;

  @override
  Widget build(BuildContext context) {
    final lapsesByKind = <WeaknessKind, int>{};
    final countByType = <String, int>{};
    var learned = 0;
    for (final point in points) {
      lapsesByKind.update(
        point.kind,
        (value) => value + point.lapses + 1,
        ifAbsent: () => point.lapses + 1,
      );
      for (final tag in point.tags.where((tag) => tag.startsWith('問題:'))) {
        countByType.update(tag, (value) => value + 1, ifAbsent: () => 1);
      }
      if (point.intervalDays >= 21) learned++;
    }
    final weakestKind = lapsesByKind.entries.isEmpty
        ? null
        : (lapsesByKind.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
    final weakestType = countByType.entries.isEmpty
        ? null
        : (countByType.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _StatChip(
            icon: Icons.school_outlined,
            label: 'Đã thuộc (≥21 ngày): $learned/${points.length}',
          ),
          if (weakestKind != null)
            _StatChip(
              icon: Icons.trending_down,
              label: 'Mảng yếu nhất: ${weakestKind.label}',
            ),
          if (weakestType != null)
            _StatChip(
              icon: Icons.assignment_late_outlined,
              label:
                  'Dạng đề sai nhiều: ${jlptQuestionTypeFrom(weakestType.key.replaceFirst('問題:', '')).label} (${weakestType.value})',
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 24),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.error,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.delete_outline, color: Colors.white),
        SizedBox(width: 6),
        Text(
          'Xóa',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _WeaknessItem extends StatelessWidget {
  const _WeaknessItem({
    required this.item,
    required this.selecting,
    required this.selected,
    required this.onOpen,
    required this.onLongPress,
    required this.onEdit,
    required this.onSource,
    required this.onDelete,
  });
  final WeakPoint item;
  final bool selecting;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onSource;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final reading = item.reading.trim();
    final hanViet = item.hanViet.trim();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.secondaryContainer : null,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              if (selecting) ...[
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : Colors.grey,
                ),
                const SizedBox(width: 12),
              ],
              _KindBadge(kind: item.kind),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (reading.isNotEmpty &&
                            item.kind != WeaknessKind.grammar) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '【$reading】',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                        if (item.warning.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          const Tooltip(
                            message: 'AI chưa chắc một phần, hãy kiểm tra',
                            child: Icon(
                              Icons.help_outline,
                              size: 16,
                              color: AppColors.weakness,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(height: 1.35),
                    ),
                    if (hanViet.isNotEmpty &&
                        (item.kind == WeaknessKind.vocabulary ||
                            item.kind == WeaknessKind.kanji)) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Hán Việt: $hanViet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _DueLabel(item: item),
                        Text(
                          '${item.notebookTitle} · Trang ${item.page}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!selecting) ...[
                IconButton(
                  tooltip: 'Sửa',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Xóa',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Tùy chọn',
                  onSelected: (value) {
                    if (value == 'source') onSource();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'source', child: Text('Xem nguồn')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DueLabel extends StatelessWidget {
  const _DueLabel({required this.item});
  final WeakPoint item;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final (text, color) = item.isNewCard
        ? ('Mới', AppColors.quickCheck)
        : item.isDue(now)
        ? ('Đến hạn ôn', AppColors.weakness)
        : (
            'Ôn sau ${formatReviewInterval(item.dueAt!.difference(now))}',
            Colors.grey,
          );
    return Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});
  final WeaknessKind kind;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.weakness.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      kind.label,
      style: const TextStyle(
        color: AppColors.weakness,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _DetailText extends StatelessWidget {
  const _DetailText({required this.item});
  final WeakPoint item;
  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _KindBadge(kind: item.kind),
            ...item.tags.map(
              (tag) => Chip(
                label: Text(
                  tag.startsWith('問題:')
                      ? jlptQuestionTypeFrom(tag.replaceFirst('問題:', '')).label
                      : tag,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (item.warning.isNotEmpty)
          _LabelValue(
            label: 'CẦN KIỂM TRA',
            value: item.warning,
            emphasized: true,
          ),
        _LabelValue(label: 'NGHĨA', value: item.content),
        if (item.reading.isNotEmpty)
          _LabelValue(label: 'CÁCH ĐỌC', value: item.reading),
        if (item.hanViet.isNotEmpty)
          _LabelValue(label: 'HÁN VIỆT', value: item.hanViet),
        if (item.conjugation.isNotEmpty)
          _LabelValue(label: 'CÁCH NỐI / CẤU TRÚC', value: item.conjugation),
        if (item.sourceSentence.isNotEmpty)
          _LabelValue(label: 'CÂU GỐC', value: item.sourceSentence),
        if (item.correctAnswer.isNotEmpty)
          _LabelValue(label: 'ĐÁP ÁN ĐÚNG', value: item.correctAnswer),
        if (item.mistake.isNotEmpty)
          _LabelValue(
            label: 'CHỖ DỄ NHẦM',
            value: item.mistake,
            emphasized: true,
          ),
        if (item.examples.isNotEmpty)
          _LabelValue(label: 'VÍ DỤ', value: item.examples.join('\n')),
        if (item.reminder.isNotEmpty)
          _LabelValue(label: 'MẸO NHỚ', value: item.reminder),
        if (item.note.isNotEmpty)
          _LabelValue(label: 'GHI CHÚ CỦA TÔI', value: item.note),
      ],
    ),
  );
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({
    required this.label,
    required this.value,
    this.emphasized = false,
  });
  final String label;
  final String value;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 11,
            color: emphasized ? AppColors.weakness : Colors.grey,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 7),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
      ],
    ),
  );
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({
    required this.item,
    required this.showOcr,
    required this.onOpenSource,
  });
  final WeakPoint item;
  final bool showOcr;
  final VoidCallback onOpenSource;
  @override
  Widget build(BuildContext context) {
    final nextReview = item.isNewCard
        ? 'Chưa ôn lần nào'
        : 'Đã ôn ${item.reps} lần liên tiếp · quên ${item.lapses} lần';
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vùng nguồn',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 220,
            child: _SourceThumbnail(
              imagePath: item.sourceImagePath,
              fallbackText: item.ocrText,
            ),
          ),
          const SizedBox(height: 14),
          if (showOcr)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Nội dung OCR'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(item.ocrText),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Text(
            '${item.notebookTitle} · Trang ${item.page}\nĐã lưu ${_relativeDate(item.createdAt)}\n$nextReview',
            style: const TextStyle(color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpenSource,
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('Xem trong vở'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyWeakness extends StatelessWidget {
  const _EmptyWeakness({required this.filtered, required this.onOpenRecent});
  final bool filtered;
  final VoidCallback? onOpenRecent;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: AppColors.weakness.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            filtered ? Icons.filter_alt_off_outlined : Icons.gesture_rounded,
            size: 50,
            color: AppColors.weakness,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          filtered ? 'Không có mục phù hợp' : 'Chưa có điểm yếu nào',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 420,
          child: Text(
            filtered
                ? 'Thử bỏ bớt bộ lọc hoặc đổi từ khóa tìm kiếm.'
                : 'Trong vở, dùng công cụ Điểm yếu hoặc Kiểm tra nhanh rồi khoanh câu bạn làm sai.',
            textAlign: TextAlign.center,
          ),
        ),
        if (!filtered && onOpenRecent != null) ...[
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onOpenRecent,
            child: const Text('Mở vở gần đây'),
          ),
        ],
      ],
    ),
  );
}

String _relativeDate(DateTime value) {
  final days = DateTime.now().difference(value).inDays;
  if (days == 0) return 'hôm nay';
  if (days == 1) return 'hôm qua';
  return '$days ngày trước';
}

class _SourceThumbnail extends StatelessWidget {
  const _SourceThumbnail({required this.imagePath, required this.fallbackText});
  final String? imagePath;
  final String fallbackText;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    final hasImage = path != null && File(path).existsSync();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xfffff7e9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33d9822b)),
      ),
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(path), fit: BoxFit.contain),
            )
          : Center(
              child: Text(
                fallbackText,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, height: 1.4),
              ),
            ),
    );
  }
}
