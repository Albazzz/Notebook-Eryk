import 'package:flutter/material.dart';

import '../app_state.dart';
import '../flashcard_decks.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/paged_point_picker.dart';
import 'quiz_screen.dart';
import 'review_screen.dart';

String _relativeDay(DateTime? value) {
  if (value == null) return 'Chưa học';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  return '$diff ngày trước';
}

String _formatDateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

Future<void> openDeckFlashcards(
  BuildContext context,
  AppState state,
  FlashcardDeck deck,
) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => ReviewScreen(state: state, deck: deck, autoStart: true),
  ),
);

Future<void> openDeckQuiz(
  BuildContext context,
  AppState state,
  FlashcardDeck deck,
) async {
  final points = state.pointsForDeck(deck);
  if (points.isEmpty) {
    showAppSnack(context, 'Bộ này chưa có thẻ');
    return;
  }
  final setup = await showQuizSetup(
    context,
    state: state,
    points: points,
    pool: state.weakPoints,
  );
  if (setup == null || !context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => QuizScreen(
        state: state,
        deck: deck,
        ask: setup.ask,
        answer: setup.answer,
      ),
    ),
  );
}

/// Công tắc trộn ngẫu nhiên nằm ở trang chọn chế độ, cạnh nút Flashcard.
class _ShuffleChip extends StatelessWidget {
  const _ShuffleChip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => FilterChip(
    avatar: const Icon(Icons.shuffle_rounded, size: 18),
    label: const Text('Trộn ngẫu nhiên'),
    selected: state.flashcardShuffle,
    onSelected: state.setFlashcardShuffle,
  );
}

/// Thư viện bộ flashcard: tạo bộ, tự chia bộ và chọn bộ học mỗi ngày.
class DeckLibraryScreen extends StatelessWidget {
  const DeckLibraryScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final today = deckForToday(state.decks, DateTime.now());
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bộ flashcard'),
            actions: [
              TextButton.icon(
                onPressed: state.weakPoints.isEmpty
                    ? null
                    : () => _showAutoSplit(context),
                icon: const Icon(Icons.auto_awesome_mosaic_outlined),
                label: const Text('Tự chia bộ'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: state.weakPoints.isEmpty
                    ? null
                    : () => showDeckEditor(context, state),
                icon: const Icon(Icons.add),
                label: const Text('Tạo bộ'),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: SafeArea(
            child: state.decks.isEmpty
                ? _EmptyLibrary(
                    hasPoints: state.weakPoints.isNotEmpty,
                    onAutoSplit: () => _showAutoSplit(context),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (today != null)
                            _TodayCard(state: state, deck: today)
                          else
                            const _AllDoneCard(),
                          const SizedBox(height: 20),
                          Text(
                            'Tất cả bộ (${state.decks.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          for (final deck in state.decks)
                            _DeckTile(state: state, deck: deck),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _showAutoSplit(BuildContext context) async {
    final created = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AutoSplitSheet(state: state),
    );
    if (created != null && created > 0 && context.mounted) {
      showAppSnack(context, 'Đã tạo $created bộ flashcard');
    }
  }
}

/// Tạo bộ mới hoặc sửa thẻ của [deck] bằng danh sách chia trang.
Future<void> showDeckEditor(
  BuildContext context,
  AppState state, {
  FlashcardDeck? deck,
}) async {
  final nameController = TextEditingController(
    text: deck?.name ?? 'Bộ ${state.decks.length + 1}',
  );
  var selected = deck?.pointIds.toSet() ?? <String>{};
  final saved = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .82,
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  deck == null ? 'Tạo bộ flashcard' : 'Sửa bộ ${deck.name}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Tên bộ'),
                ),
                const SizedBox(height: 8),
                Text('Đã chọn ${selected.length} thẻ'),
                Expanded(
                  child: PagedPointPicker(
                    points: state.weakPoints,
                    selectedIds: selected,
                    onChanged: (ids) => setSheetState(() => selected = ids),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, true),
                      child: Text(deck == null ? 'Tạo bộ' : 'Lưu'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final name = nameController.text;
  // The sheet's TextField may still be attached during the exit animation.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  nameController.dispose();
  if (saved != true) return;
  // Keep the library order of the weak point list for the chosen ids.
  final ordered = [
    for (final point in state.weakPoints)
      if (selected.contains(point.id)) point,
  ];
  if (deck == null) {
    state.createDeck(name, ordered);
  } else {
    final kept = deck.pointIds.where(selected.contains).toList();
    final added = ordered
        .map((point) => point.id)
        .where((id) => !kept.contains(id));
    state
      ..setDeckPoints(deck, [...kept, ...added])
      ..renameDeck(deck, name);
  }
}

class _AutoSplitSheet extends StatefulWidget {
  const _AutoSplitSheet({required this.state});
  final AppState state;

  @override
  State<_AutoSplitSheet> createState() => _AutoSplitSheetState();
}

class _AutoSplitSheetState extends State<_AutoSplitSheet> {
  double _maxSize = 20;
  bool _shuffle = true;
  bool _onlyUnassigned = true;
  WeaknessKind? _kind;
  final TextEditingController _prefix = TextEditingController(text: 'Bộ');

  @override
  void dispose() {
    _prefix.dispose();
    super.dispose();
  }

  List<WeakPoint> get _source {
    final assigned = widget.state.pointIdsInDecks;
    return widget.state.weakPoints
        .where((point) => _kind == null || point.kind == _kind)
        .where((point) => !_onlyUnassigned || !assigned.contains(point.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final maxSize = _maxSize.round();
    final sizes = splitIntoDecks(
      source,
      maxSize,
    ).map((deck) => deck.length).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tự chia bộ flashcard',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const Text(
                'Lấy từ',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tất cả loại'),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  for (final kind in WeaknessKind.values)
                    ChoiceChip(
                      label: Text(kind.label),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _onlyUnassigned,
                onChanged: (value) => setState(() => _onlyUnassigned = value),
                title: const Text('Chỉ lấy thẻ chưa có trong bộ nào'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _shuffle,
                onChanged: (value) => setState(() => _shuffle = value),
                title: const Text('Trộn ngẫu nhiên trước khi chia'),
                subtitle: const Text('Tắt để chia theo thứ tự trong sổ'),
              ),
              Text(
                'Tối đa $maxSize thẻ mỗi bộ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Slider(
                value: _maxSize,
                min: 5,
                max: 60,
                divisions: 11,
                label: '$maxSize',
                onChanged: (value) => setState(() => _maxSize = value),
              ),
              TextField(
                controller: _prefix,
                decoration: const InputDecoration(
                  labelText: 'Tên bộ',
                  helperText: 'Các bộ được đánh số: Bộ 1, Bộ 2...',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                source.isEmpty
                    ? 'Không có thẻ phù hợp để chia.'
                    : '${source.length} thẻ → ${sizes.length} bộ (${sizes.join(' / ')} thẻ)',
                style: TextStyle(
                  color: source.isEmpty
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: source.isEmpty
                      ? null
                      : () {
                          final created = widget.state.createSplitDecks(
                            source,
                            maxSize: maxSize,
                            shuffle: _shuffle,
                            prefix: _prefix.text,
                          );
                          Navigator.pop(context, created.length);
                        },
                  icon: const Icon(Icons.auto_awesome_mosaic_outlined),
                  label: Text('Tạo ${sizes.length} bộ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.state, required this.deck});
  final AppState state;
  final FlashcardDeck deck;

  @override
  Widget build(BuildContext context) {
    final count = state.pointsForDeck(deck).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HÔM NAY NÊN HỌC',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 6),
          Text(deck.name, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            '$count thẻ · Lần học trước: ${_relativeDay(deck.lastStudiedAt)}',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => openDeckFlashcards(context, state, deck),
                icon: const Icon(Icons.style_outlined),
                label: const Text('Flashcard'),
              ),
              OutlinedButton.icon(
                onPressed: () => openDeckQuiz(context, state, deck),
                icon: const Icon(Icons.quiz_outlined),
                label: const Text('Quiz'),
              ),
              _ShuffleChip(state: state),
            ],
          ),
        ],
      ),
    );
  }
}

class _AllDoneCard extends StatelessWidget {
  const _AllDoneCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.correct.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      children: [
        Icon(Icons.celebration_outlined, color: AppColors.correct),
        SizedBox(width: 12),
        Expanded(child: Text('Hôm nay bạn đã học tất cả các bộ.')),
      ],
    ),
  );
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({required this.state, required this.deck});
  final AppState state;
  final FlashcardDeck deck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = state.pointsForDeck(deck).length;
    final quiz = deck.lastOf(DeckActivity.quiz);
    final studiedToday = deck.studiedOn(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DeckDetailScreen(state: state, deck: deck),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: studiedToday
                    ? AppColors.correct.withValues(alpha: .15)
                    : scheme.surfaceContainerHigh,
                child: Icon(
                  studiedToday ? Icons.check_rounded : Icons.style_outlined,
                  color: studiedToday ? AppColors.correct : scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deck.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        '$count thẻ',
                        _relativeDay(deck.lastStudiedAt),
                        if (quiz != null)
                          'Quiz gần nhất ${(quiz.accuracy * 100).round()}%',
                      ].join(' · '),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Flashcard',
                onPressed: () => openDeckFlashcards(context, state, deck),
                icon: const Icon(Icons.style_outlined),
              ),
              IconButton(
                tooltip: 'Quiz',
                onPressed: () => openDeckQuiz(context, state, deck),
                icon: const Icon(Icons.quiz_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.hasPoints, required this.onAutoSplit});
  final bool hasPoints;
  final VoidCallback onAutoSplit;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.collections_bookmark_outlined, size: 56),
          const SizedBox(height: 12),
          const Text(
            'Chưa có bộ flashcard',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            hasPoints
                ? 'Chia điểm yếu thành các bộ nhỏ để học mỗi ngày một bộ.'
                : 'Hãy lưu điểm yếu trước, sau đó chia thành các bộ để học.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (hasPoints)
            FilledButton.icon(
              onPressed: onAutoSplit,
              icon: const Icon(Icons.auto_awesome_mosaic_outlined),
              label: const Text('Tự chia bộ'),
            ),
        ],
      ),
    ),
  );
}

/// Chi tiết một bộ: học Flashcard/Quiz và báo cáo tiến độ.
class DeckDetailScreen extends StatelessWidget {
  const DeckDetailScreen({super.key, required this.state, required this.deck});
  final AppState state;
  final FlashcardDeck deck;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final points = state.pointsForDeck(deck);
        final now = DateTime.now();
        final mastered = points.where((p) => p.intervalDays >= 7).length;
        final due = points.where((p) => p.isDue(now)).length;
        final quizzes = deck.sessions
            .where((session) => session.activity == DeckActivity.quiz)
            .toList();
        final lastQuiz = quizzes.lastOrNull;
        final averageQuiz = quizzes.isEmpty
            ? null
            : quizzes.fold<double>(0, (sum, item) => sum + item.accuracy) /
                  quizzes.length;
        final studyDays = deck.sessions
            .map((s) => DateTime(s.at.year, s.at.month, s.at.day))
            .toSet()
            .length;
        final byId = {for (final point in points) point.id: point};
        final hardest =
            deck.wrongCounts.entries
                .where(
                  (entry) => byId.containsKey(entry.key) && entry.value > 0,
                )
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));
        return Scaffold(
          appBar: AppBar(
            title: Text(deck.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) => _onMenu(context, value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Sửa thẻ trong bộ')),
                  PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
                  PopupMenuItem(value: 'delete', child: Text('Xóa bộ')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: points.isEmpty
                              ? null
                              : () => openDeckFlashcards(context, state, deck),
                          icon: const Icon(Icons.style_outlined),
                          label: const Text('Flashcard'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: points.isEmpty
                              ? null
                              : () => openDeckQuiz(context, state, deck),
                          icon: const Icon(Icons.quiz_outlined),
                          label: const Text('Quiz'),
                        ),
                        _ShuffleChip(state: state),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Báo cáo',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _StatTile(label: 'Số thẻ', value: '${points.length}'),
                        _StatTile(
                          label: 'Đã thuộc (≥7 ngày)',
                          value: '$mastered/${points.length}',
                        ),
                        _StatTile(label: 'Đến hạn ôn', value: '$due'),
                        _StatTile(label: 'Số ngày đã học', value: '$studyDays'),
                        _StatTile(
                          label: 'Quiz gần nhất',
                          value: lastQuiz == null
                              ? '—'
                              : '${(lastQuiz.accuracy * 100).round()}%',
                        ),
                        _StatTile(
                          label: 'Quiz trung bình',
                          value: averageQuiz == null
                              ? '—'
                              : '${(averageQuiz * 100).round()}%',
                        ),
                      ],
                    ),
                    if (hardest.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Thẻ hay sai',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      for (final entry in hardest.take(5))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.wrong.withValues(
                              alpha: .12,
                            ),
                            child: Text(
                              '${entry.value}',
                              style: const TextStyle(
                                color: AppColors.wrong,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(byId[entry.key]!.title),
                          subtitle: Text(
                            [
                              byId[entry.key]!.reading,
                              byId[entry.key]!.content,
                            ].where((part) => part.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Lịch sử học',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    if (deck.sessions.isEmpty)
                      const Text('Chưa học lần nào.')
                    else
                      for (final session in deck.sessions.reversed.take(30))
                        _SessionRow(session: session),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    switch (value) {
      case 'edit':
        await showDeckEditor(context, state, deck: deck);
      case 'rename':
        final controller = TextEditingController(text: deck.name);
        final name = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Đổi tên bộ'),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, controller.text),
                child: const Text('Lưu'),
              ),
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        controller.dispose();
        if (name != null) state.renameDeck(deck, name);
      case 'delete':
        final index = state.deleteDeck(deck);
        if (!context.mounted) return;
        Navigator.pop(context);
        showAppSnack(
          context,
          'Đã xóa ${deck.name} (điểm yếu vẫn giữ nguyên)',
          actionLabel: 'Hoàn tác',
          onAction: () => state.restoreDeck(deck, index),
        );
    }
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final DeckSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = (session.accuracy * 100).round();
    final color = percent >= 80
        ? AppColors.correct
        : percent >= 50
        ? AppColors.weakness
        : AppColors.wrong;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            session.activity == DeckActivity.quiz
                ? Icons.quiz_outlined
                : Icons.style_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    session.activity.label,
                    if (session.detail.isNotEmpty) session.detail,
                  ].join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_formatDateTime(session.at)} · ${session.seconds ~/ 60} phút ${session.seconds % 60} giây',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${session.correct}/${session.total}',
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
