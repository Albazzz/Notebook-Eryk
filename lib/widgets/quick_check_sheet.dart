import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Kết quả làm một câu: lựa chọn người học bấm và đúng/sai.
class QuickCheckAnswer {
  const QuickCheckAnswer({
    required this.question,
    required this.pickedIndex,
    required this.correct,
  });

  final QuickCheckQuestion question;

  /// null với câu tự luận người học tự chấm.
  final int? pickedIndex;
  final bool correct;

  String get pickedText {
    final index = pickedIndex;
    if (index == null || index < 0 || index >= question.choices.length) {
      return '';
    }
    final choice = question.choices[index];
    return [
      choice.label,
      choice.text,
    ].where((part) => part.isNotEmpty).join('. ');
  }

  /// Mô tả cho AI biết người học đã sai ở đâu khi tạo điểm yếu.
  String get learnerContext {
    final label = question.label.isEmpty ? '' : 'Câu ${question.label}: ';
    if (pickedIndex == null) {
      return '${label}người học trả lời sai; đáp án đúng là ${question.correctText}.';
    }
    return '${label}người học chọn "$pickedText" (sai); đáp án đúng là ${question.correctText}.';
  }

  /// Nội dung câu hỏi dạng văn bản để gửi lại cho AI.
  String get questionText => [
    if (question.label.isNotEmpty) 'Câu ${question.label}',
    question.stem,
    ...question.choices.map(
      (choice) => [
        choice.label,
        choice.text,
      ].where((part) => part.isNotEmpty).join(' '),
    ),
  ].where((part) => part.trim().isNotEmpty).join('\n');
}

/// Bảng chấm nhanh: hiện ngay hàng nút đáp án trong lúc AI đang giải, rồi chấm
/// tại chỗ khi có kết quả. Hỗ trợ nhiều câu trong một vùng khoanh.
class QuickCheckSheet extends StatefulWidget {
  const QuickCheckSheet({
    super.key,
    required this.result,
    required this.title,
    this.sourceText = '',
    this.initialQuestionCount = 1,
    this.wrongActionLabel = 'Lưu câu sai thành điểm yếu',
    required this.onWrongAnswers,
    this.onExplain,
    this.onRetry,
  });

  final Future<QuickCheckResult> result;
  final String title;
  final String sourceText;
  final int initialQuestionCount;
  final String wrongActionLabel;
  final ValueChanged<List<QuickCheckAnswer>> onWrongAnswers;
  final ValueChanged<QuickCheckAnswer>? onExplain;
  final VoidCallback? onRetry;

  @override
  State<QuickCheckSheet> createState() => _QuickCheckSheetState();
}

class _QuickCheckSheetState extends State<QuickCheckSheet> {
  QuickCheckResult? _result;
  Object? _error;

  /// Lựa chọn người học bấm theo vị trí câu → vị trí lựa chọn.
  final Map<int, int> _picks = {};

  /// Tự chấm cho câu không có lựa chọn.
  final Map<int, bool> _selfGraded = {};
  final Set<int> _revealed = {};
  late int _placeholderCount = widget.initialQuestionCount.clamp(1, 20);

  @override
  void initState() {
    super.initState();
    widget.result.then(
      (value) {
        if (!mounted) return;
        setState(() {
          _result = value;
          // Giữ các lựa chọn đã bấm trước khi AI trả về nếu còn hợp lệ.
          _picks.removeWhere(
            (question, choice) =>
                question >= value.questions.length ||
                choice >= value.questions[question].choices.length,
          );
        });
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = error);
      },
    );
  }

  List<QuickCheckAnswer> get _answers {
    final result = _result;
    if (result == null) return const [];
    final answers = <QuickCheckAnswer>[];
    for (var index = 0; index < result.questions.length; index++) {
      final question = result.questions[index];
      if (question.choices.isEmpty) {
        final graded = _selfGraded[index];
        if (graded != null) {
          answers.add(
            QuickCheckAnswer(
              question: question,
              pickedIndex: null,
              correct: graded,
            ),
          );
        }
        continue;
      }
      final pick = _picks[index];
      if (pick == null) continue;
      answers.add(
        QuickCheckAnswer(
          question: question,
          pickedIndex: pick,
          correct: pick == question.correctIndex,
        ),
      );
    }
    return answers;
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final answers = _answers;
    final wrong = answers.where((answer) => !answer.correct).toList();
    final total = result?.questions.length ?? _placeholderCount;
    final height = MediaQuery.sizeOf(context).height * .86;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: SizedBox(
          height: height,
          width: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    color: AppColors.quickCheck,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (result != null)
                    _ScoreBadge(
                      correct: answers.where((answer) => answer.correct).length,
                      answered: answers.length,
                      total: total,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                result == null && _error == null
                    ? 'AI đang giải đề… Bạn cứ bấm đáp án của mình, app sẽ chấm ngay khi có kết quả.'
                    : 'Bấm đáp án bạn đã chọn cho từng câu.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (result == null && _error == null)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                _ErrorBanner(
                  message: _errorText(_error!),
                  onRetry: widget.onRetry,
                ),
              if (result?.warning.isNotEmpty == true)
                _WarningBanner(message: result!.warning),
              if (widget.sourceText.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Nội dung đã nhận dạng'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(widget.sourceText),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: result?.questions.length ?? _placeholderCount,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => result == null
                      ? _placeholderCard(index)
                      : _questionCard(index, result.questions[index]),
                ),
              ),
              if (result == null && _error == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _placeholderCount >= 20
                        ? null
                        : () => setState(() => _placeholderCount++),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm câu'),
                  ),
                ),
              const SizedBox(height: 8),
              // Wrap: Material 3 caps bottom sheets at 640 px, which is too
              // narrow for all three actions on one line in Vietnamese.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (answers.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        _picks.clear();
                        _selfGraded.clear();
                        _revealed.clear();
                      }),
                      child: const Text('Làm lại'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.weakness,
                    ),
                    onPressed: wrong.isEmpty
                        ? null
                        : () {
                            Navigator.pop(context);
                            widget.onWrongAnswers(wrong);
                          },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(
                      wrong.isEmpty
                          ? widget.wrongActionLabel
                          : '${widget.wrongActionLabel} (${wrong.length})',
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

  String _errorText(Object error) => error
      .toString()
      .replaceFirst('FormatException: ', '')
      .replaceFirst('HttpException: ', '')
      .replaceFirst('Exception: ', '');

  Widget _placeholderCard(int index) {
    const labels = ['1', '2', '3', '4'];
    return _QuestionFrame(
      heading: 'Câu ${index + 1}',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var choice = 0; choice < labels.length; choice++)
            ChoiceChip(
              label: Text(labels[choice]),
              selected: _picks[index] == choice,
              onSelected: _error != null
                  ? null
                  : (_) => setState(() => _picks[index] = choice),
            ),
        ],
      ),
    );
  }

  Widget _questionCard(int index, QuickCheckQuestion question) {
    final heading = [
      question.label.isEmpty ? 'Câu ${index + 1}' : 'Câu ${question.label}',
      if (question.questionType != JlptQuestionType.other)
        question.questionType.label,
    ].join(' · ');
    if (question.choices.isEmpty) {
      return _openQuestionCard(index, question, heading);
    }
    final pick = _picks[index];
    final graded = pick != null;
    final correct = graded && pick == question.correctIndex;
    return _QuestionFrame(
      heading: heading,
      status: !graded ? null : correct,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.stem.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(question.stem, style: const TextStyle(height: 1.5)),
            ),
          for (var choice = 0; choice < question.choices.length; choice++)
            _ChoiceTile(
              choice: question.choices[choice],
              picked: pick == choice,
              revealed: graded,
              onTap: graded
                  ? null
                  : () => setState(() => _picks[index] = choice),
            ),
          if (graded) ...[
            const SizedBox(height: 8),
            if (!correct)
              Text(
                'Đáp án đúng: ${question.correctText}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.correct,
                ),
              ),
            if (question.explanation.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  question.explanation,
                  style: const TextStyle(height: 1.45),
                ),
              ),
            _QuestionActions(
              point: question.point,
              onExplain: widget.onExplain == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      widget.onExplain!(
                        QuickCheckAnswer(
                          question: question,
                          pickedIndex: pick,
                          correct: correct,
                        ),
                      );
                    },
            ),
          ],
        ],
      ),
    );
  }

  Widget _openQuestionCard(
    int index,
    QuickCheckQuestion question,
    String heading,
  ) {
    final revealed = _revealed.contains(index);
    final graded = _selfGraded[index];
    return _QuestionFrame(
      heading: heading,
      status: graded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.stem.isNotEmpty)
            Text(question.stem, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 8),
          if (!revealed)
            OutlinedButton(
              onPressed: () => setState(() => _revealed.add(index)),
              child: const Text('Xem đáp án'),
            )
          else ...[
            Text(
              'Đáp án: ${question.answer}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (question.explanation.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(question.explanation),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Mình làm đúng'),
                  selected: graded == true,
                  onSelected: (_) => setState(() => _selfGraded[index] = true),
                ),
                ChoiceChip(
                  label: const Text('Mình làm sai'),
                  selected: graded == false,
                  onSelected: (_) => setState(() => _selfGraded[index] = false),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionFrame extends StatelessWidget {
  const _QuestionFrame({
    required this.heading,
    required this.child,
    this.status,
  });
  final String heading;
  final Widget child;

  /// null: chưa chấm; true: đúng; false: sai.
  final bool? status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      true => AppColors.correct,
      false => AppColors.wrong,
      null => Theme.of(context).colorScheme.outlineVariant,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: status == null ? 1 : 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  heading,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (status != null)
                Icon(
                  status! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: color,
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.choice,
    required this.picked,
    required this.revealed,
    required this.onTap,
  });
  final QuickCheckChoice choice;
  final bool picked;
  final bool revealed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color border;
    final Color? fill;
    if (revealed && choice.correct) {
      border = AppColors.correct;
      fill = AppColors.correct.withValues(alpha: .1);
    } else if (revealed && picked) {
      border = AppColors.wrong;
      fill = AppColors.wrong.withValues(alpha: .1);
    } else {
      border = picked ? AppColors.quickCheck : scheme.outlineVariant;
      fill = null;
    }
    final showReason =
        revealed && (picked || choice.correct) && choice.reason.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: fill ?? scheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    choice.label,
                    choice.text,
                  ].where((part) => part.isNotEmpty).join('. '),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (showReason)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      choice.reason,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestionActions extends StatelessWidget {
  const _QuestionActions({required this.point, required this.onExplain});
  final String point;
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (point.isNotEmpty) Chip(label: Text(point)),
        if (onExplain != null)
          TextButton.icon(
            onPressed: onExplain,
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Giải thích chi tiết'),
          ),
      ],
    ),
  );
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({
    required this.correct,
    required this.answered,
    required this.total,
  });
  final int correct;
  final int answered;
  final int total;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.quickCheck.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      answered == 0 ? '0/$total' : 'Đúng $correct/$answered · $total câu',
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: AppColors.quickCheck,
      ),
    ),
  );
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.weakness.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: AppColors.weakness, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
        if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry!();
            },
            child: const Text('Thử lại'),
          ),
      ],
    ),
  );
}

/// Ước lượng số câu hỏi từ OCR để hiện đủ hàng nút trước khi AI trả về:
/// đếm ô trống （　）/＿＿ hoặc dòng bắt đầu bằng số câu.
int estimateQuestionCount(String text) {
  // Câu 文の組み立て có bốn ô ＿＿ trên cùng một dòng, nên đếm theo dòng.
  final blankPattern = RegExp(r'[（(]\s*[)）]|＿{2,}|_{3,}|★');
  final blanks = text
      .split('\n')
      .where((line) => blankPattern.hasMatch(line))
      .length;
  final numbered = RegExp(
    r'^\s*(?:問\s*\d+|\d+\s*[.．、)）]|[（(]\d+[)）])',
    multiLine: true,
  ).allMatches(text).length;
  // Lựa chọn 1–4 cũng bắt đầu bằng số, nên chia 5 (1 câu + 4 lựa chọn).
  final fromNumbers = (numbered / 5).round();
  final estimate = blanks > 0 ? blanks : fromNumbers;
  return estimate.clamp(1, 10);
}
