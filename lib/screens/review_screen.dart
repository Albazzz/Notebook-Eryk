import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../flashcard_decks.dart';
import '../models.dart';
import '../review.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/paged_point_picker.dart';
import '../widgets/quick_check_sheet.dart';
import 'settings_screen.dart';

/// Ôn flashcard từ điểm yếu theo lịch lặp lại ngắt quãng.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.state,
    this.initialQueue,
    this.deck,
  });
  final AppState state;

  /// Ôn đúng các mục này (ví dụ các mục đã chọn) thay vì hàng đợi đến hạn.
  final List<WeakPoint>? initialQueue;

  /// Học theo một bộ thẻ: chỉ chọn trong bộ và ghi kết quả vào báo cáo bộ.
  final FlashcardDeck? deck;

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
  DateTime _startedAt = DateTime.now();

  AppState get state => widget.state;

  /// Mục được phép chọn: cả sổ điểm yếu, hoặc chỉ các thẻ của bộ.
  List<WeakPoint> get _eligible {
    final deck = widget.deck;
    return deck == null ? state.weakPoints : state.pointsForDeck(deck);
  }

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _queue = List.of(
      widget.initialQueue ??
          (widget.deck == null
              ? state.dueWeakPoints
              : state.pointsForDeck(widget.deck!)),
    );
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
    if (_index >= _queue.length) _recordDeckSession();
  }

  void _recordDeckSession() {
    final deck = widget.deck;
    if (deck == null || _reviewed == 0) return;
    state.recordDeckSession(
      deck,
      DeckSession(
        at: DateTime.now(),
        activity: DeckActivity.flashcard,
        correct: _reviewed - _again,
        total: _reviewed,
        seconds: DateTime.now().difference(_startedAt).inSeconds,
        detail: state.flashcardShuffle ? 'Trộn ngẫu nhiên' : '',
      ),
      wrongIds: _forgotten.map((point) => point.id),
    );
  }

  void _studyAll() {
    setState(() {
      _selectedIds = _eligible.map((point) => point.id).toSet();
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
    if (state.flashcardShuffle) cards.shuffle();
    setState(() {
      _startedAt = DateTime.now();
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
      showAppSnack(context, 'Hãy thiết lập API key trong Cài đặt AI');
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
    final eligible = _eligible;
    final selected = eligible
        .where((point) => _selectedIds.contains(point.id))
        .toList();
    bool missingData(WeakPoint point) => !canShowConfiguredFlashcard(
      point,
      state.flashcardFrontFields,
      state.flashcardBackFields,
    );
    final missing = selected.where(missingData).toList();
    final forgotten = eligible.where((point) => point.needsRevisit).toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.deck == null
                    ? 'Tạo phiên flashcard'
                    : 'Flashcard · ${widget.deck!.name}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Mặt trước: ${state.flashcardFrontFields.map((field) => field.label).join(', ')}'
                ' · Mặt sau: ${state.flashcardBackFields.map((field) => field.label).join(', ')}',
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _showFlashcardSettings,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Tùy chỉnh mặt thẻ'),
                  ),
                  FilterChip(
                    avatar: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text('Trộn ngẫu nhiên'),
                    selected: state.flashcardShuffle,
                    onSelected: (value) async {
                      await state.setFlashcardShuffle(value);
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Chọn mục để học (${selected.length}/${eligible.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (missing.isNotEmpty)
                Text(
                  '${missing.length} mục thiếu dữ liệu theo cài đặt mặt thẻ sẽ được bỏ qua.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(
                child: PagedPointPicker(
                  points: eligible,
                  selectedIds: _selectedIds,
                  isDisabled: missingData,
                  onChanged: (ids) => setState(() => _selectedIds = ids),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (forgotten.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _startWith(forgotten),
                      icon: const Icon(Icons.replay),
                      label: Text('Ôn lại ${forgotten.length} thẻ chưa nhớ'),
                    ),
                  FilledButton.icon(
                    onPressed: selected.isEmpty
                        ? null
                        : () => _startWith(selected),
                    icon: Icon(
                      state.flashcardShuffle
                          ? Icons.shuffle_rounded
                          : Icons.style_outlined,
                    ),
                    label: Text(
                      'Bắt đầu · ${selected.length - missing.length} thẻ',
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
              if (_eligible.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _studyAll,
                  icon: const Icon(Icons.replay),
                  label: Text(
                    widget.deck == null ? 'Ôn thêm tất cả' : 'Học lại cả bộ',
                  ),
                ),
              if (_eligible.any((item) => item.needsRevisit))
                FilledButton.icon(
                  onPressed: () =>
                      _startWith(_eligible.where((item) => item.needsRevisit)),
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
