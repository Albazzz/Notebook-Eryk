import 'dart:math' as math;

import 'models.dart';

/// Lịch ôn lặp lại ngắt quãng kiểu SM-2 (giống Anki), đủ đơn giản để kiểm thử
/// và không cần lưu lịch sử từng lượt ôn.
class ReviewScheduler {
  const ReviewScheduler();

  static const minEase = 1.3;
  static const maxEase = 3.2;
  static const relearnDelay = Duration(minutes: 10);

  /// Khoảng cách tới lần ôn tiếp theo nếu người học chọn [rating].
  Duration previewInterval(WeakPoint point, ReviewRating rating) {
    final days = _nextIntervalDays(point, rating);
    if (days == null) return relearnDelay;
    return Duration(minutes: (days * Duration.minutesPerDay).round());
  }

  void apply(WeakPoint point, ReviewRating rating, {DateTime? now}) {
    final reviewedAt = now ?? DateTime.now();
    final days = _nextIntervalDays(point, rating);
    switch (rating) {
      case ReviewRating.again:
        point.lapses++;
        point.reps = 0;
        point.ease = math.max(minEase, point.ease - .2);
        point.intervalDays = 0;
      case ReviewRating.hard:
        point.reps++;
        point.ease = math.max(minEase, point.ease - .15);
      case ReviewRating.good:
        point.reps++;
      case ReviewRating.easy:
        point.reps++;
        point.ease = math.min(maxEase, point.ease + .15);
    }
    if (days != null) point.intervalDays = days;
    point.lastReviewedAt = reviewedAt;
    point.dueAt = days == null
        ? reviewedAt.add(relearnDelay)
        : reviewedAt.add(
            Duration(minutes: (days * Duration.minutesPerDay).round()),
          );
  }

  /// `null` nghĩa là ôn lại trong phiên (sau [relearnDelay]).
  double? _nextIntervalDays(WeakPoint point, ReviewRating rating) {
    final current = point.intervalDays;
    final ease = point.ease;
    switch (rating) {
      case ReviewRating.again:
        return null;
      case ReviewRating.hard:
        return point.reps == 0 ? 1 : math.max(1, current * 1.2);
      case ReviewRating.good:
        if (point.reps == 0) return 1;
        if (point.reps == 1) return 3;
        return math.max(current + 1, current * ease);
      case ReviewRating.easy:
        if (point.reps == 0) return 4;
        return math.max(current + 2, current * ease * 1.3);
    }
  }

  /// Thẻ đến hạn trước, thẻ mới sau (giới hạn [newLimit] thẻ mới mỗi phiên).
  List<WeakPoint> dueQueue(
    Iterable<WeakPoint> points, {
    DateTime? now,
    int newLimit = 20,
  }) {
    final at = now ?? DateTime.now();
    final reviews =
        points.where((point) => !point.isNewCard && point.isDue(at)).toList()
          ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final fresh =
        points.where((point) => point.isNewCard && point.isDue(at)).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [...reviews, ...fresh.take(newLimit)];
  }
}

String formatReviewInterval(Duration value) {
  if (value.inMinutes < 60) return '${math.max(1, value.inMinutes)} phút';
  if (value.inHours < 24) return '${value.inHours} giờ';
  final days = value.inHours / 24;
  if (days < 30) return '${days.round()} ngày';
  if (days < 365) return '${(days / 30).toStringAsFixed(1)} tháng';
  return '${(days / 365).toStringAsFixed(1)} năm';
}

/// Nội dung hai mặt của một flashcard, dựng theo loại điểm yếu.
class FlashcardFace {
  const FlashcardFace({
    required this.prompt,
    required this.front,
    this.frontHint = '',
    required this.answer,
    this.details = const [],
  });

  /// Câu hỏi ngắn phía trên mặt trước, ví dụ "Đọc từ này thế nào?".
  final String prompt;
  final String front;
  final String frontHint;
  final String answer;

  /// Các mục phụ ở mặt sau (nhãn, nội dung).
  final List<(String, String)> details;
}

FlashcardFace buildFlashcard(WeakPoint point, {bool reverse = false}) {
  final details = <(String, String)>[
    if (point.reading.isNotEmpty && point.kind != WeaknessKind.grammar)
      ('Cách đọc', point.reading),
    if (point.hanViet.isNotEmpty) ('Hán Việt', point.hanViet),
    if (point.conjugation.isNotEmpty)
      ('Cách nối / cấu trúc', point.conjugation),
    if (point.correctAnswer.isNotEmpty) ('Đáp án đúng', point.correctAnswer),
    if (point.mistake.isNotEmpty) ('Chỗ dễ nhầm', point.mistake),
    if (point.examples.isNotEmpty) ('Ví dụ', point.examples.join('\n')),
    if (point.reminder.isNotEmpty) ('Mẹo nhớ', point.reminder),
    if (point.note.isNotEmpty) ('Ghi chú', point.note),
  ];
  final meaning = point.content.trim();
  if (reverse && meaning.isNotEmpty) {
    return FlashcardFace(
      prompt: switch (point.kind) {
        WeaknessKind.grammar => 'Mẫu ngữ pháp nào mang nghĩa này?',
        WeaknessKind.kanji => 'Kanji nào mang nghĩa này?',
        _ => 'Từ tiếng Nhật nào mang nghĩa này?',
      },
      front: meaning,
      answer: point.title,
      details: details,
    );
  }
  switch (point.kind) {
    case WeaknessKind.grammar:
      final cloze = _grammarCloze(point);
      if (cloze != null) {
        return FlashcardFace(
          prompt: 'Điền mẫu ngữ pháp còn thiếu',
          front: cloze,
          frontHint: meaning,
          answer: point.title,
          details: [('Nghĩa', meaning), ...details],
        );
      }
      return FlashcardFace(
        prompt: 'Nghĩa và cách dùng của mẫu này?',
        front: point.title,
        answer: meaning,
        details: details,
      );
    case WeaknessKind.vocabulary:
    case WeaknessKind.kanji:
      return FlashcardFace(
        prompt: point.kind == WeaknessKind.kanji
            ? 'Cách đọc và nghĩa của chữ này?'
            : 'Cách đọc và nghĩa của từ này?',
        front: point.title,
        frontHint: point.sourceSentence,
        answer: [
          if (point.reading.isNotEmpty) point.reading,
          meaning,
        ].join(' — '),
        details: details
            .where((item) => item.$1 != 'Cách đọc')
            .toList(growable: false),
      );
    case WeaknessKind.reading:
    case WeaknessKind.other:
      final question = point.sourceSentence.isNotEmpty
          ? point.sourceSentence
          : point.title;
      return FlashcardFace(
        prompt: point.correctAnswer.isNotEmpty
            ? 'Đáp án đúng là gì?'
            : 'Điểm cần nhớ là gì?',
        front: question,
        frontHint: question == point.title ? '' : point.title,
        answer: point.correctAnswer.isNotEmpty ? point.correctAnswer : meaning,
        details: [
          if (point.correctAnswer.isNotEmpty && meaning.isNotEmpty)
            ('Giải thích', meaning),
          ...details.where((item) => item.$1 != 'Đáp án đúng'),
        ],
      );
  }
}

/// Đục lỗ mẫu ngữ pháp trong câu ví dụ/câu gốc. Trả về null nếu không tìm
/// thấy mẫu trong câu (khi đó thẻ hỏi nghĩa thay vì điền).
String? _grammarCloze(WeakPoint point) {
  final pattern = point.title
      .replaceAll(RegExp(r'[〜~～\s]'), '')
      .split(RegExp(r'[/／・]'))
      .first;
  if (pattern.isEmpty) return null;
  final candidates = [
    point.sourceSentence,
    ...point.examples.map((example) => example.split(' — ').first),
  ];
  for (final sentence in candidates) {
    final index = sentence.indexOf(pattern);
    if (index >= 0) {
      return sentence.replaceRange(index, index + pattern.length, '＿＿＿');
    }
  }
  return null;
}

/// Xuất TSV cho Anki: Mặt trước, Mặt sau, Tags. Anki nhận HTML nên xuống dòng
/// được đổi thành <br>.
String exportAnkiTsv(Iterable<WeakPoint> points) {
  String cell(String value) => value
      .replaceAll('\t', ' ')
      .replaceAll('\r\n', '\n')
      .replaceAll('\n', '<br>')
      .trim();
  final buffer = StringBuffer()
    ..writeln('#separator:tab')
    ..writeln('#html:true')
    ..writeln('#columns:Front\tBack\tTags');
  for (final point in points) {
    final face = buildFlashcard(point);
    final front = [
      face.front,
      if (face.frontHint.isNotEmpty) '<small>${face.frontHint}</small>',
    ].join('\n');
    final back = [
      '<b>${face.answer}</b>',
      for (final (label, value) in face.details) '<i>$label:</i> $value',
    ].join('\n');
    final tags = {
      'NoteEryk',
      point.kind.name,
      ...point.tags.map((tag) => tag.replaceAll(RegExp(r'\s+'), '_')),
    }.join(' ');
    buffer.writeln('${cell(front)}\t${cell(back)}\t${cell(tags)}');
  }
  return buffer.toString();
}
