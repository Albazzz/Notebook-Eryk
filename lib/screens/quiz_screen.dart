import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../flashcard_decks.dart';
import '../models.dart';
import '../theme.dart';

/// Quiz trắc nghiệm của một bộ thẻ: hỏi bằng một trường (Hán Việt, Nghĩa,
/// Kanji, Cách đọc) và chọn đáp án ở một trường khác.
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.state,
    required this.deck,
    this.ask,
    this.answer,
    this.points,
  });

  final AppState state;
  final FlashcardDeck deck;

  /// null: ngẫu nhiên cho từng câu.
  final QuizField? ask;
  final QuizField? answer;

  /// Chỉ hỏi các thẻ này (ví dụ làm lại câu sai); mặc định là cả bộ.
  final List<WeakPoint>? points;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late List<QuizQuestion> _questions;
  int _index = 0;

  /// Lựa chọn đã bấm ở câu hiện tại; -1 là "Bạn không biết?".
  int? _picked;
  final List<QuizQuestion> _wrong = [];
  int _correct = 0;
  final DateTime _startedAt = DateTime.now();
  bool _recorded = false;
  Timer? _advanceTimer;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _questions = buildQuiz(
      widget.points ?? state.pointsForDeck(widget.deck),
      ask: widget.ask,
      answer: widget.answer,
      distractorPool: state.weakPoints,
    );
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  QuizQuestion? get _current =>
      _index < _questions.length ? _questions[_index] : null;

  void _pick(int option) {
    final question = _current;
    if (question == null || _picked != null) return;
    final correct = option == question.correctIndex;
    setState(() {
      _picked = option;
      if (correct) {
        _correct++;
      } else {
        _wrong.add(question);
      }
    });
    if (correct && !MediaQuery.disableAnimationsOf(context)) {
      // A right answer needs no reading time; move on automatically.
      _advanceTimer = Timer(const Duration(milliseconds: 750), _next);
    }
  }

  void _next() {
    _advanceTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _index++;
      _picked = null;
    });
    if (_index >= _questions.length) _record();
  }

  void _record() {
    if (_recorded || _questions.isEmpty) return;
    _recorded = true;
    final ask = widget.ask?.label ?? 'Ngẫu nhiên';
    final answer = widget.answer?.label ?? 'Ngẫu nhiên';
    state.recordDeckSession(
      widget.deck,
      DeckSession(
        at: DateTime.now(),
        activity: DeckActivity.quiz,
        correct: _correct,
        total: _questions.length,
        seconds: DateTime.now().difference(_startedAt).inSeconds,
        detail: [
          '$ask → $answer',
          if (widget.points != null) 'làm lại câu sai',
        ].join(' · '),
      ),
      wrongIds: _wrong.map((question) => question.point.id),
    );
  }

  void _restart({bool wrongOnly = false}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QuizScreen(
          state: state,
          deck: widget.deck,
          ask: widget.ask,
          answer: widget.answer,
          points: wrongOnly
              ? _wrong.map((question) => question.point).toSet().toList()
              : widget.points,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = _current;
    return Scaffold(
      appBar: AppBar(title: Text('Quiz · ${widget.deck.name}')),
      body: SafeArea(
        child: _questions.isEmpty
            ? _buildEmpty()
            : question == null
            ? _buildResult()
            : Column(
                children: [
                  LinearProgressIndicator(value: _index / _questions.length),
                  Expanded(child: _buildQuestion(question)),
                ],
              ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Không tạo được câu hỏi',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Các thẻ trong bộ chưa có đủ ${widget.ask?.label ?? 'trường hỏi'} và '
            '${widget.answer?.label ?? 'trường đáp án'}, hoặc không đủ đáp án nhiễu. '
            'Hãy chọn kiểu hỏi khác hoặc bổ sung thông tin cho điểm yếu.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Quay lại'),
          ),
        ],
      ),
    ),
  );

  Widget _buildQuestion(QuizQuestion question) {
    final scheme = Theme.of(context).colorScheme;
    final answered = _picked != null;
    final correct = _picked == question.correctIndex;
    final promptSize = question.prompt.characters.length <= 12 ? 34.0 : 24.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 940),
          child: Container(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        question.ask.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '${_index + 1}/${_questions.length}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  question.prompt,
                  style: TextStyle(
                    fontSize: promptSize,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 72),
                Text(
                  'Chọn đáp án đúng · ${question.answer.label}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 520 ? 2 : 1;
                    const gap = 16.0;
                    final width =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (
                          var option = 0;
                          option < question.options.length;
                          option++
                        )
                          SizedBox(
                            width: width,
                            child: _OptionTile(
                              key: ValueKey('quiz-option-$option'),
                              number: option + 1,
                              text: question.options[option],
                              state: !answered
                                  ? _OptionState.idle
                                  : option == question.correctIndex
                                  ? _OptionState.correct
                                  : option == _picked
                                  ? _OptionState.wrong
                                  : _OptionState.faded,
                              onTap: answered ? null : () => _pick(option),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                if (!answered)
                  Center(
                    child: TextButton(
                      onPressed: () => _pick(-1),
                      child: const Text('Bạn không biết?'),
                    ),
                  )
                else
                  _Feedback(
                    correct: correct,
                    question: question,
                    onNext: _next,
                    isLast: _index == _questions.length - 1,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    final scheme = Theme.of(context).colorScheme;
    final total = _questions.length;
    final percent = total == 0 ? 0 : (_correct * 100 / total).round();
    final seconds = DateTime.now().difference(_startedAt).inSeconds;
    final color = percent >= 80
        ? AppColors.correct
        : percent >= 50
        ? AppColors.weakness
        : AppColors.wrong;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              percent >= 80 ? Icons.emoji_events_outlined : Icons.task_alt,
              size: 56,
              color: color,
            ),
            const SizedBox(height: 10),
            Text(
              '$percent%',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              'Đúng $_correct/$total câu · ${seconds ~/ 60} phút ${seconds % 60} giây',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                if (_wrong.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _restart(wrongOnly: true),
                    icon: const Icon(Icons.replay),
                    label: Text('Làm lại ${_wrong.length} câu sai'),
                  ),
                OutlinedButton.icon(
                  onPressed: _restart,
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Làm lại (trộn mới)'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Xong'),
                ),
              ],
            ),
            if (_wrong.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Câu sai', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final question in _wrong)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(question.prompt),
                    subtitle: Text(
                      '${question.answer.label}: ${question.correctText}',
                      style: const TextStyle(
                        color: AppColors.correct,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: Text(
                      question.point.title,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _OptionState { idle, correct, wrong, faded }

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.number,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final int number;
  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (border, fill, icon) = switch (state) {
      _OptionState.idle => (scheme.outline, scheme.surface, null),
      _OptionState.correct => (
        AppColors.correct,
        AppColors.correct.withValues(alpha: .12),
        Icons.check_circle_rounded,
      ),
      _OptionState.wrong => (
        AppColors.wrong,
        AppColors.wrong.withValues(alpha: .12),
        Icons.cancel_rounded,
      ),
      _OptionState.faded => (scheme.outlineVariant, scheme.surface, null),
    };
    return Opacity(
      opacity: state == _OptionState.faded ? .55 : 1,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: border,
                width: state == _OptionState.idle ? 1.2 : 2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(fontSize: 19, height: 1.35),
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, color: border),
                ] else
                  Text(
                    '$number',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.correct,
    required this.question,
    required this.onNext,
    required this.isLast,
  });

  final bool correct;
  final QuizQuestion question;
  final VoidCallback onNext;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final point = question.point;
    final details = <String>{
      if (point.title.isNotEmpty) point.title,
      if (point.reading.isNotEmpty) point.reading,
      if (point.hanViet.isNotEmpty) point.hanViet,
      if (point.content.isNotEmpty) point.content,
    }.join(' · ');
    return Row(
      children: [
        Icon(
          correct ? Icons.check_circle_rounded : Icons.lightbulb_outline,
          color: correct ? AppColors.correct : AppColors.weakness,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            correct
                ? 'Chính xác! $details'
                : 'Đáp án: ${question.correctText}\n$details',
            style: const TextStyle(height: 1.4),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: onNext,
          child: Text(isLast ? 'Xem kết quả' : 'Tiếp tục'),
        ),
      ],
    );
  }
}

/// Bảng chọn kiểu Quiz; trả về (hỏi, đáp) với null là ngẫu nhiên.
Future<({QuizField? ask, QuizField? answer})?> showQuizSetup(
  BuildContext context, {
  required List<WeakPoint> points,
  required List<WeakPoint> pool,
}) => showModalBottomSheet<({QuizField? ask, QuizField? answer})>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _QuizSetupSheet(points: points, pool: pool),
);

class _QuizSetupSheet extends StatefulWidget {
  const _QuizSetupSheet({required this.points, required this.pool});
  final List<WeakPoint> points;
  final List<WeakPoint> pool;

  @override
  State<_QuizSetupSheet> createState() => _QuizSetupSheetState();
}

class _QuizSetupSheetState extends State<_QuizSetupSheet> {
  QuizField? _ask;
  QuizField? _answer;

  Widget _choices(
    QuizField? value,
    ValueChanged<QuizField?> onChanged, {
    QuizField? exclude,
  }) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ChoiceChip(
        avatar: const Icon(Icons.shuffle_rounded, size: 18),
        label: const Text('Ngẫu nhiên'),
        selected: value == null,
        onSelected: (_) => onChanged(null),
      ),
      for (final field in QuizField.values)
        if (field != exclude)
          ChoiceChip(
            label: Text(field.label),
            selected: value == field,
            onSelected: (_) => onChanged(field),
          ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final count = buildQuiz(
      widget.points,
      ask: _ask,
      answer: _answer,
      distractorPool: widget.pool,
      random: math.Random(1),
    ).length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quiz', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            const Text(
              'Câu hỏi hiển thị',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _choices(
              _ask,
              (value) => setState(() {
                _ask = value;
                if (_answer == value) _answer = null;
              }),
            ),
            const SizedBox(height: 16),
            const Text(
              'Chọn đáp án theo',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _choices(
              _answer,
              (value) => setState(() => _answer = value),
              exclude: _ask,
            ),
            const SizedBox(height: 16),
            Text(
              count == 0
                  ? 'Không thẻ nào đủ dữ liệu cho kiểu hỏi này.'
                  : '$count/${widget.points.length} thẻ đủ dữ liệu để hỏi.',
              style: TextStyle(
                color: count == 0
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: count == 0
                    ? null
                    : () =>
                          Navigator.pop(context, (ask: _ask, answer: _answer)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('Bắt đầu $count câu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
