import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../review.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/quick_check_sheet.dart';
import 'settings_screen.dart';

/// Ôn flashcard từ điểm yếu theo lịch lặp lại ngắt quãng.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.state, this.initialQueue});
  final AppState state;

  /// Ôn đúng các mục này (ví dụ các mục đã chọn) thay vì hàng đợi đến hạn.
  final List<WeakPoint>? initialQueue;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with SingleTickerProviderStateMixin {
  late List<WeakPoint> _queue;
  int _index = 0;
  bool _revealed = false;
  bool _started = false;
  late final AnimationController _flipController;
  late Set<String> _selectedIds;
  int _reviewed = 0;
  int _again = 0;

  /// Thẻ bấm "Quên" trong phiên được ôn lại ở cuối phiên và gợi ý luyện đề.
  final List<WeakPoint> _forgotten = [];

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _queue = List.of(widget.initialQueue ?? state.dueWeakPoints);
    _selectedIds = _queue.map((point) => point.id).toSet();
  }

  WeakPoint? get _current => _index < _queue.length ? _queue[_index] : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _flipController.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 560);
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_flipController.isAnimating) return;
    if (_revealed) {
      setState(() => _revealed = false);
      _flipController.reverse();
    } else {
      _flipController.forward().then((_) {
        if (mounted && _flipController.isCompleted) {
          setState(() => _revealed = true);
        }
      });
    }
  }

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
      _flipController.value = 0;
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
        .where(
          (point) => canShowConfiguredFlashcard(
            point,
            state.flashcardFrontFields,
            state.flashcardBackFields,
          ),
        )
        .toList();
    if (cards.isEmpty) {
      showAppSnack(context, 'Không có thẻ đủ dữ liệu theo cài đặt mặt thẻ');
      return;
    }
    setState(() {
      _queue = cards;
      _index = 0;
      _revealed = false;
      _flipController.value = 0;
      _started = true;
      _reviewed = 0;
      _again = 0;
      _forgotten.clear();
    });
  }

  Future<void> _showFlashcardSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .82,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: FlashcardSettingsPanel(state: state),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
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
        .where(
          (point) => !canShowConfiguredFlashcard(
            point,
            state.flashcardFrontFields,
            state.flashcardBackFields,
          ),
        )
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
            Text(
              'Mặt trước: ${state.flashcardFrontFields.map((field) => field.label).join(', ')}',
            ),
            const SizedBox(height: 4),
            Text(
              'Mặt sau: ${state.flashcardBackFields.map((field) => field.label).join(', ')}',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _showFlashcardSettings,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Tùy chỉnh mặt thẻ'),
              ),
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
                  '${missing.length} mục thiếu dữ liệu theo cài đặt mặt thẻ sẽ được bỏ qua.',
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
    final front = flashcardSideContent(point, state.flashcardFrontFields);
    final back = flashcardSideContent(point, state.flashcardBackFields);
    return Column(
      children: [
        LinearProgressIndicator(
          value: _queue.isEmpty ? 0 : _index / _queue.length,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = math.min(
                440.0,
                math.max(120.0, constraints.maxHeight - 32),
              );
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SizedBox(
                    width: double.infinity,
                    height: height,
                    child: AnimatedBuilder(
                      animation: _flipController,
                      builder: (context, _) {
                        final angle = _flipController.value * math.pi;
                        final showingBack = angle > math.pi / 2;
                        return Transform(
                          key: const ValueKey('flashcard-rotation'),
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, .0012)
                            ..rotateY(angle),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(
                              showingBack ? math.pi : 0,
                            ),
                            child: _cardFace(
                              showingBack ? back : front,
                              showingBack: showingBack,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
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

  Widget _cardFace(
    List<(FlashcardField, String)> contents, {
    required bool showingBack,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('flashcard-tap'),
        onTap: _flipCard,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  showingBack ? 'Mặt sau' : 'Mặt trước',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final (index, entry) in contents.indexed) ...[
                            if (index > 0) const SizedBox(height: 18),
                            if (index > 0)
                              Text(
                                entry.$1.label,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            Text(
                              entry.$2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: index == 0
                                    ? (entry.$2.characters.length <= 8
                                          ? 42
                                          : 26)
                                    : 17,
                                fontWeight: index == 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                showingBack ? 'Chạm để xem lại mặt trước' : 'Chạm để lật thẻ',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
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
