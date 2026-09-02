import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class WeaknessesScreen extends StatefulWidget {
  const WeaknessesScreen({super.key, required this.state});
  final AppState state;

  @override
  State<WeaknessesScreen> createState() => _WeaknessesScreenState();
}

class _WeaknessesScreenState extends State<WeaknessesScreen> {
  String filter = 'Tất cả';
  String search = '';

  @override
  Widget build(BuildContext context) {
    final items = widget.state.weakPoints.where((item) {
      final matchesFilter = filter == 'Tất cả' || item.kind.label == filter;
      final haystack = '${item.title} ${item.content} ${item.reminder}'
          .toLowerCase();
      return matchesFilter && haystack.contains(search.toLowerCase());
    }).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      child: Column(
        children: [
          PageHeader(
            title: 'Điểm yếu',
            subtitle:
                '${widget.state.weakPoints.length} mục bạn đã chủ động lưu để ôn lại.',
            trailing: Wrap(
              spacing: 10,
              children: [
                SearchBox(
                  hint: 'Tìm điểm yếu...',
                  width: 230,
                  onChanged: (value) => setState(() => search = value),
                ),
                DropdownButton<String>(
                  value: 'Mới lưu gần đây',
                  items: const ['Mới lưu gần đây', 'Tên A–Z', 'Theo vở']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children:
                  ['Tất cả', ...WeaknessKind.values.map((item) => item.label)]
                      .map(
                        (label) => ChoiceChip(
                          label: Text(label),
                          selected: filter == label,
                          onSelected: (_) => setState(() => filter = label),
                        ),
                      )
                      .toList(),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: items.isEmpty
                ? _EmptyWeakness(
                    onOpenRecent: () =>
                        widget.state.open(widget.state.notebooks.first),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 30),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _WeaknessItem(
                      item: items[index],
                      onOpen: () => _showDetail(items[index]),
                      onEdit: () => _edit(items[index]),
                      onSource: () => _openSource(items[index]),
                      onDelete: () => _confirmDelete(items[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openSource(WeakPoint item) {
    final notebook = widget.state.notebooks
        .where((notebook) => notebook.id == item.notebookId)
        .firstOrNull;
    if (notebook == null) {
      showAppSnack(context, 'Không còn tìm thấy vở nguồn');
      return;
    }
    widget.state.open(notebook, page: item.page, source: true);
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
                    const Text(
                      'Điểm yếu / Chi tiết',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'edit'),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Sửa'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
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
                        onOpenSource: () => Navigator.pop(context, 'source'),
                      );
                      return twoColumns
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 6, child: details),
                                const SizedBox(width: 22),
                                Expanded(flex: 4, child: source),
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
        await _confirmDelete(item);
      case 'source':
        _openSource(item);
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
    var kind = item.kind;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
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
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Tên'),
                ),
                const SizedBox(height: 12),
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
                if ({
                  WeaknessKind.vocabulary,
                  WeaknessKind.kanji,
                }.contains(kind)) ...[
                  TextField(
                    controller: reading,
                    decoration: const InputDecoration(
                      labelText: 'Cách đọc (よみ / furigana)',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if ({
                  WeaknessKind.vocabulary,
                  WeaknessKind.kanji,
                }.contains(kind)) ...[
                  TextField(
                    controller: hanViet,
                    decoration: const InputDecoration(labelText: 'Hán Việt'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: content,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Nội dung'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sourceSentence,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Câu gốc'),
                ),
                const SizedBox(height: 12),
                if (kind == WeaknessKind.grammar) ...[
                  TextField(
                    controller: conjugation,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Cách chia / cấu trúc',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if ({
                  WeaknessKind.grammar,
                  WeaknessKind.vocabulary,
                  WeaknessKind.kanji,
                }.contains(kind)) ...[
                  TextField(
                    controller: examples,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Ví dụ (mỗi dòng một ví dụ)',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: reminder,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Điểm cần nhớ'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Ghi chú'),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
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
                        widget.state.updateWeakPoint(item);
                        Navigator.pop(context, true);
                      },
                      child: const Text('Lưu thay đổi'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    title.dispose();
    content.dispose();
    reminder.dispose();
    note.dispose();
    reading.dispose();
    hanViet.dispose();
    conjugation.dispose();
    examples.dispose();
    sourceSentence.dispose();
    if (saved == true && mounted) showAppSnack(context, 'Đã lưu thay đổi');
  }

  Future<void> _confirmDelete(WeakPoint item) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Xóa điểm yếu?'),
        content: Text(
          '“${item.title}” sẽ bị xóa khỏi danh sách ôn tập. Nội dung vở gốc không thay đổi.',
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
            child: const Text('Xóa điểm yếu'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      widget.state.deleteWeakPoint(item.id);
      if (mounted) showAppSnack(context, 'Đã xóa điểm yếu');
    }
  }
}

class _WeaknessItem extends StatelessWidget {
  const _WeaknessItem({
    required this.item,
    required this.onOpen,
    required this.onEdit,
    required this.onSource,
    required this.onDelete,
  });
  final WeakPoint item;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onSource;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              height: 82,
              child: _SourceThumbnail(
                imagePath: item.sourceImagePath,
                fallbackText: item.ocrText,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _KindBadge(kind: item.kind),
                      ...item.tags
                          .take(1)
                          .map(
                            (tag) => Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Chip(
                                label: Text(tag),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.reminder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${item.notebookTitle} · Trang ${item.page} · ${_relativeDate(item.createdAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              children: [
                TextButton(onPressed: onOpen, child: const Text('Mở')),
                IconButton(
                  onPressed: onEdit,
                  tooltip: 'Sửa',
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: onSource,
                  tooltip: 'Xem nguồn',
                  icon: const Icon(Icons.my_location_rounded),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Xóa')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
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
          children: [
            _KindBadge(kind: item.kind),
            ...item.tags.map((tag) => Chip(label: Text(tag))),
          ],
        ),
        const SizedBox(height: 24),
        _LabelValue(label: 'NỘI DUNG', value: item.content),
        if (item.sourceSentence.isNotEmpty)
          _LabelValue(label: 'CÂU GỐC', value: item.sourceSentence),
        if (item.reading.isNotEmpty)
          _LabelValue(label: 'CÁCH ĐỌC', value: item.reading),
        if (item.hanViet.isNotEmpty)
          _LabelValue(label: 'HÁN VIỆT', value: item.hanViet),
        if (item.conjugation.isNotEmpty)
          _LabelValue(label: 'CÁCH CHIA / CẤU TRÚC', value: item.conjugation),
        if (item.examples.isNotEmpty)
          _LabelValue(label: 'VÍ DỤ', value: item.examples.join('\n')),
        _LabelValue(
          label: 'ĐIỂM CẦN NHỚ',
          value: item.reminder,
          emphasized: true,
        ),
        _LabelValue(
          label: 'GHI CHÚ CỦA TÔI',
          value: item.note.isEmpty ? 'Chưa có ghi chú.' : item.note,
        ),
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
        Text(value, style: const TextStyle(fontSize: 16, height: 1.5)),
      ],
    ),
  );
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({required this.item, required this.onOpenSource});
  final WeakPoint item;
  final VoidCallback onOpenSource;
  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Vùng nguồn', style: TextStyle(fontWeight: FontWeight.w800)),
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
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('OCR text'),
          children: [
            Align(alignment: Alignment.centerLeft, child: Text(item.ocrText)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${item.notebookTitle} · Trang ${item.page}\nĐã lưu ${_relativeDate(item.createdAt)}',
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

class _EmptyWeakness extends StatelessWidget {
  const _EmptyWeakness({required this.onOpenRecent});
  final VoidCallback onOpenRecent;
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
          child: const Icon(
            Icons.gesture_rounded,
            size: 50,
            color: AppColors.weakness,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Chưa có điểm yếu nào',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const SizedBox(
          width: 410,
          child: Text(
            'Trong vở, chọn công cụ Điểm yếu rồi khoanh nội dung bạn muốn ôn lại.',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onOpenRecent,
          child: const Text('Mở vở gần đây'),
        ),
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
