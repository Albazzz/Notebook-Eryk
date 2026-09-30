import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../review.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/quick_check_sheet.dart';

/// Ôn flashcard từ điểm yếu theo lịch lặp lại ngắt quãng.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.state, this.initialQueue});
  final AppState state;

  /// Ôn đúng các mục này (ví dụ các mục đã chọn) thay vì hàng đợi đến hạn.
  final List<WeakPoint>? initialQueue;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late List<WeakPoint> _queue;
  int _index = 0;
  bool _revealed = false;
  bool _started = false;
  FlashcardFront _front = FlashcardFront.word;
  HanVietSide _hanVietSide = HanVietSide.back;
  late Set<String> _selectedIds;
  int _reviewed = 0;
  int _again = 0;

  /// Thẻ bấm "Quên" trong phiên được ôn lại ở cuối phiên và gợi ý luyện đề.
  final List<WeakPoint> _forgotten = [];

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _queue = List.of(widget.initialQueue ?? state.dueWeakPoints);
    _selectedIds = _queue.map((point) => point.id).toSet();
  }

  WeakPoint? get _current => _index < _queue.length ? _queue[_index] : null;

  void _rate(ReviewRating rating) {
    final point = _current;
    if (point == null) return;
    state.reviewWeakPoint(point, rating);
    setState(() {
      _reviewed++;
      if (rating == ReviewRating.again) {
        _again++;
        if (!_forgotten.contains(point)) _forgotten.add(point);
      }
      _index++;
      _revealed = false;
    });
  }

  void _studyAll() {
    setState(() {
      _selectedIds = state.weakPoints.map((point) => point.id).toSet();
      _started = false;
    });
  }

  void _startWith(Iterable<WeakPoint> points) {
    final cards = points
        .where((point) => canShowFlashcard(point, _front))
        .toList();
    if (cards.isEmpty) {
      showAppSnack(context, 'Không có thẻ phù hợp với mặt trước đã chọn');
      return;
    }
    setState(() {
      _queue = cards;
      _index = 0;
      _revealed = false;
      _started = true;
      _reviewed = 0;
      _again = 0;
      _forgotten.clear();
    });
  }

  List<WeakPoint> _practiceCandidates() {
    if (_forgotten.isNotEmpty) return _forgotten.take(8).toList();
    final ranked = List.of(state.weakPoints)
      ..sort((a, b) {
        final byLapses = b.lapses.compareTo(a.lapses);
        if (byLapses != 0) return byLapses;
        return b.createdAt.compareTo(a.createdAt);
      });
    return ranked.take(8).toList();
  }

  Future<void> _startPractice() async {
    final points = _practiceCandidates();
    if (points.isEmpty) {
      showAppSnack(context, 'Chưa có điểm yếu để tạo đề');
      return;
    }
    if (!state.aiConnected) {
      showAppSnack(context, 'Hãy thiết lập OpenRouter trong Cài đặt AI');
      return;
    }
    final future = state.aiService.completePracticeQuestions(
      apiKey: state.apiKey,
      modelId: state.modelIdFor(AiTask.solve),
      points: points,
      jlpt: state.jlpt,
      language: state.explanationLanguage,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickCheckSheet(
        result: future,
        title: 'Luyện đề AI (${points.length} câu)',
        initialQuestionCount: points.length,
        wrongActionLabel: 'Đưa câu đã tích về ôn lại',
        onRetry: () => _startPractice(),
        onWrongAnswers: (wrong) {
          var matched = 0;
          for (final answer in wrong) {
            final point = _pointForQuestion(answer.question, points);
            if (point == null) continue;
            state.reencounterWeakPoint(point);
            matched++;
          }
          if (mounted) {
            showAppSnack(context, 'Đã đưa $matched điểm yếu về ôn ngay');
          }
        },
      ),
    );
  }

  /// Câu luyện tập mang nhãn "#n" hoặc "n" và `point` là tiêu đề điểm yếu.
  WeakPoint? _pointForQuestion(
    QuickCheckQuestion question,
    List<WeakPoint> points,
  ) {
    final number = int.tryParse(question.label.replaceAll(RegExp(r'\D'), ''));
    if (number != null && number >= 1 && number <= points.length) {
      return points[number - 1];
    }
    final key = question.point.trim();
    return points.where((point) => point.title.trim() == key).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final point = _started ? _current : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          point == null ? 'Ôn tập' : 'Ôn tập · ${_index + 1}/${_queue.length}',
        ),
        actions: [
          IconButton(
            tooltip: 'Luyện đề AI từ điểm hay quên',
            onPressed: _startPractice,
            icon: const Icon(Icons.quiz_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: !_started
            ? _buildSetup()
            : point == null
            ? _buildFinished()
            : _buildCard(point),
      ),
    );
  }

  Widget _buildSetup() {
    final eligible = state.weakPoints;
    final selected = eligible
        .where((point) => _selectedIds.contains(point.id))
        .toList();
    final missing = selected
        .where((point) => !canShowFlashcard(point, _front))
        .toList();
    final forgotten = eligible.where((point) => point.needsRevisit).toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Tạo phiên flashcard',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text('Mặt trước', style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Từ / mẫu'),
                  selected: _front == FlashcardFront.word,
                  onSelected: (_) =>
                      setState(() => _front = FlashcardFront.word),
                ),
                ChoiceChip(
                  label: const Text('Nghĩa'),
                  selected: _front == FlashcardFront.meaning,
                  onSelected: (_) =>
                      setState(() => _front = FlashcardFront.meaning),
                ),
                ChoiceChip(
                  label: const Text('Kanji'),
                  selected: _front == FlashcardFront.kanji,
                  onSelected: (_) =>
                      setState(() => _front = FlashcardFront.kanji),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<HanVietSide>(
              initialValue: _hanVietSide,
              decoration: const InputDecoration(labelText: 'Hiển thị Hán Việt'),
              items: const [
                DropdownMenuItem(
                  value: HanVietSide.front,
                  child: Text('Mặt trước'),
                ),
                DropdownMenuItem(
                  value: HanVietSide.back,
                  child: Text('Mặt sau'),
                ),
                DropdownMenuItem(value: HanVietSide.hidden, child: Text('Ẩn')),
              ],
              onChanged: (value) =>
                  setState(() => _hanVietSide = value ?? _hanVietSide),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chọn mục để học (${selected.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _selectedIds = eligible
                        .map((point) => point.id)
                        .toSet(),
                  ),
                  child: const Text('Chọn tất cả'),
                ),
                TextButton(
                  onPressed: () => setState(_selectedIds.clear),
                  child: const Text('Bỏ chọn'),
                ),
              ],
            ),
            if (missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${missing.length} mục không có ${_front == FlashcardFront.kanji ? 'Kanji' : 'nội dung cho mặt trước'} sẽ được bỏ qua.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (final point in eligible)
              CheckboxListTile(
                value: _selectedIds.contains(point.id),
                title: Text(point.title),
                subtitle: Text(
                  point.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selectedIds.add(point.id);
                  } else {
                    _selectedIds.remove(point.id);
                  }
                }),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: selected.isEmpty ? null : () => _startWith(selected),
              icon: const Icon(Icons.style_outlined),
              label: Text('Bắt đầu · ${selected.length - missing.length} thẻ'),
            ),
            if (forgotten.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _startWith(forgotten),
                icon: const Icon(Icons.replay),
                label: Text('Ôn lại ${forgotten.length} thẻ chưa nhớ'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinished() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _reviewed == 0 ? Icons.celebration_outlined : Icons.task_alt,
            size: 64,
            color: AppColors.correct,
          ),
          const SizedBox(height: 16),
          Text(
            _reviewed == 0 ? 'Không có thẻ đến hạn' : 'Xong phiên ôn tập',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _reviewed == 0
                ? 'Bạn đã ôn hết thẻ hôm nay. Có thể ôn thêm hoặc luyện đề AI.'
                : 'Đã ôn $_reviewed lượt, quên $_again lượt.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              if (state.weakPoints.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _studyAll,
                  icon: const Icon(Icons.replay),
                  label: const Text('Ôn thêm tất cả'),
                ),
              if (state.weakPoints.any((item) => item.needsRevisit))
                FilledButton.icon(
                  onPressed: () => _startWith(
                    state.weakPoints.where((item) => item.needsRevisit),
                  ),
                  icon: const Icon(Icons.replay),
                  label: const Text('Ôn lại các thẻ chưa nhớ'),
                ),
              FilledButton.icon(
                onPressed: _startPractice,
                icon: const Icon(Icons.quiz_outlined),
                label: Text(
                  _forgotten.isEmpty
                      ? 'Luyện đề AI'
                      : 'Luyện đề AI với ${_forgotten.length} thẻ đã quên',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildCard(WeakPoint point) {
    final face = buildConfiguredFlashcard(
      point,
      front: _front,
      hanVietSide: _hanVietSide,
    );
    final scheme = Theme.of(context).colorScheme;
    final frontSize = face.front.characters.length <= 8
        ? 44.0
        : face.front.characters.length <= 30
        ? 26.0
        : 19.0;
    return Column(
      children: [
        LinearProgressIndicator(
          value: _queue.isEmpty ? 0 : _index / _queue.length,
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: GestureDetector(
                onTap: () => setState(() => _revealed = !_revealed),
                child: Card(
                  margin: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (child, animation) =>
                          RotationTransition(
                            turns: Tween<double>(
                              begin: .5,
                              end: 1,
                            ).animate(animation),
                            child: child,
                          ),
                      child: Column(
                        key: ValueKey('${point.id}-$_revealed'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              _Badge(label: point.kind.label),
                              const SizedBox(width: 8),
                              if (point.isNewCard)
                                const _Badge(
                                  label: 'Mới',
                                  color: AppColors.quickCheck,
                                )
                              else if (point.lapses > 0)
                                _Badge(
                                  label: 'Quên ${point.lapses} lần',
                                  color: AppColors.wrong,
                                ),
                              const Spacer(),
                              Flexible(
                                child: Text(
                                  '${point.notebookTitle} · Tr. ${point.page}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          if (!_revealed)
                            Text(
                              face.prompt,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          if (!_revealed) const SizedBox(height: 14),
                          if (!_revealed)
                            SelectableText(
                              face.front,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: frontSize,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                              ),
                            ),
                          if (face.frontHint.isNotEmpty && !_revealed) ...[
                            const SizedBox(height: 12),
                            Text(
                              face.frontHint,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ],
                          if (_revealed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Mặt sau · chạm để lật lại',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (!_revealed) const Divider(height: 36),
                          if (!_revealed)
                            Center(
                              child: FilledButton.tonal(
                                onPressed: () =>
                                    setState(() => _revealed = true),
                                child: const Text('Lật thẻ'),
                              ),
                            )
                          else ...[
                            SelectableText(
                              face.answer,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.correct,
                              ),
                            ),
                            const SizedBox(height: 18),
                            for (final (label, value) in face.details)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        letterSpacing: .8,
                                        fontWeight: FontWeight.w800,
                                        color: label == 'Chỗ dễ nhầm'
                                            ? AppColors.weakness
                                            : Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      value,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_revealed)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Row(
                children: [
                  for (final rating in [
                    ReviewRating.again,
                    ReviewRating.good,
                  ]) ...[
                    Expanded(child: _ratingButton(point, rating)),
                    if (rating == ReviewRating.again) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _ratingButton(WeakPoint point, ReviewRating rating) {
    final color = switch (rating) {
      ReviewRating.again => AppColors.wrong,
      ReviewRating.hard => AppColors.weakness,
      ReviewRating.good => AppColors.correct,
      ReviewRating.easy => AppColors.primary,
    };
    final next = formatReviewInterval(
      state.reviewScheduler.previewInterval(point, rating),
    );
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: () => _rate(rating),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rating == ReviewRating.again ? 'Chưa nhớ' : 'Đã nhớ',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(next, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.color = AppColors.weakness});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}
