import 'dart:math' as math;

import 'models.dart';

/// Trường dùng làm câu hỏi hoặc đáp án trong Quiz của một bộ thẻ (cùng bộ
/// trường với mặt thẻ flashcard).
enum QuizField {
  word('Từ / mẫu'),
  kanji('Kanji'),
  reading('Cách đọc'),
  hanViet('Hán Việt'),
  meaning('Nghĩa'),
  example('Ví dụ');

  const QuizField(this.label);
  final String label;

  String valueOf(WeakPoint point) => switch (this) {
    QuizField.word => point.title,
    // The written form of the word, only when it actually uses kanji.
    QuizField.kanji =>
      RegExp(r'[\u3400-\u9fff]').hasMatch(point.title) ? point.title : '',
    QuizField.reading => point.reading,
    QuizField.hanViet => point.hanViet,
    QuizField.meaning => point.content,
    QuizField.example =>
      point.examples.isEmpty ? '' : point.examples.first.split(' — ').first,
  }.trim();
}

enum DeckActivity {
  flashcard('Flashcard'),
  quiz('Quiz');

  const DeckActivity(this.label);
  final String label;
}

/// Một lượt học một bộ thẻ, dùng cho báo cáo.
class DeckSession {
  const DeckSession({
    required this.at,
    required this.activity,
    required this.correct,
    required this.total,
    this.seconds = 0,
    this.detail = '',
  });

  final DateTime at;
  final DeckActivity activity;
  final int correct;
  final int total;
  final int seconds;

  /// Ví dụ "Nghĩa → Kanji" cho Quiz.
  final String detail;

  double get accuracy => total == 0 ? 0 : correct / total;

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'activity': activity.name,
    'correct': correct,
    'total': total,
    'seconds': seconds,
    'detail': detail,
  };

  factory DeckSession.fromJson(Map<String, dynamic> json) => DeckSession(
    at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
    activity: DeckActivity.values.firstWhere(
      (value) => value.name == json['activity'],
      orElse: () => DeckActivity.flashcard,
    ),
    correct: (json['correct'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    seconds: (json['seconds'] as num?)?.toInt() ?? 0,
    detail: json['detail']?.toString() ?? '',
  );
}

/// Bộ flashcard: danh sách id điểm yếu theo thứ tự cùng lịch sử học.
class FlashcardDeck {
  FlashcardDeck({
    required this.id,
    required this.name,
    required this.pointIds,
    required this.createdAt,
    List<DeckSession>? sessions,
    Map<String, int>? wrongCounts,
  }) : sessions = sessions ?? [],
       wrongCounts = wrongCounts ?? {};

  final String id;
  String name;
  List<String> pointIds;
  final DateTime createdAt;
  final List<DeckSession> sessions;

  /// Số lần trả lời sai/quên của từng thẻ trong bộ.
  final Map<String, int> wrongCounts;

  static const maxSessions = 200;

  DateTime? get lastStudiedAt => sessions.isEmpty ? null : sessions.last.at;

  bool studiedOn(DateTime day) => sessions.any(
    (session) =>
        session.at.year == day.year &&
        session.at.month == day.month &&
        session.at.day == day.day,
  );

  DeckSession? lastOf(DeckActivity activity) =>
      sessions.where((session) => session.activity == activity).lastOrNull;

  void record(DeckSession session, Iterable<String> wrongIds) {
    sessions.add(session);
    if (sessions.length > maxSessions) {
      sessions.removeRange(0, sessions.length - maxSessions);
    }
    for (final id in wrongIds) {
      wrongCounts[id] = (wrongCounts[id] ?? 0) + 1;
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'pointIds': pointIds,
    'createdAt': createdAt.toIso8601String(),
    'sessions': sessions.map((session) => session.toJson()).toList(),
    'wrongCounts': wrongCounts,
  };

  factory FlashcardDeck.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) throw const FormatException('Bộ thẻ thiếu id');
    return FlashcardDeck(
      id: id,
      name: json['name']?.toString() ?? 'Bộ thẻ',
      pointIds: (json['pointIds'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      sessions: (json['sessions'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => DeckSession.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      wrongCounts: (json['wrongCounts'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
      ),
    );
  }
}

/// Chia [points] thành các bộ không quá [maxSize] thẻ, kích thước đều nhau
/// (45 thẻ, tối đa 20 → 15/15/15 thay vì 20/20/5).
List<List<WeakPoint>> splitIntoDecks(
  List<WeakPoint> points,
  int maxSize, {
  bool shuffle = false,
  math.Random? random,
}) {
  if (points.isEmpty || maxSize <= 0) return const [];
  final source = List.of(points);
  if (shuffle) source.shuffle(random);
  final count = (source.length / maxSize).ceil();
  final base = source.length ~/ count;
  final extra = source.length % count;
  final decks = <List<WeakPoint>>[];
  var start = 0;
  for (var index = 0; index < count; index++) {
    final size = base + (index < extra ? 1 : 0);
    decks.add(source.sublist(start, start + size));
    start += size;
  }
  return decks;
}

class QuizQuestion {
  const QuizQuestion({
    required this.point,
    required this.promptLines,
    required this.answer,
    required this.options,
    required this.correctIndex,
  });

  final WeakPoint point;

  /// Các trường hiển thị ở câu hỏi, trường đầu là dòng chính.
  final List<(QuizField, String)> promptLines;
  final QuizField answer;
  final List<String> options;
  final int correctIndex;

  QuizField get ask => promptLines.first.$1;
  String get prompt => promptLines.first.$2;
  String get correctText => options[correctIndex];
}

String _normalized(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s・、,。.]'), '');

/// Câu hỏi (các dòng hiển thị) và trường đáp có thể dùng cho [point].
/// [ask] rỗng: chọn ngẫu nhiên một trường hỏi; [answer] null: ngẫu nhiên.
/// Trường hỏi trùng giá trị với đáp án bị bỏ để không lộ đáp án (ví dụ
/// hỏi Cách đọc của một từ chỉ có kana).
List<(List<(QuizField, String)>, QuizField)> quizLayoutsFor(
  WeakPoint point, {
  Set<QuizField> ask = const {},
  QuizField? answer,
}) {
  final layouts = <(List<(QuizField, String)>, QuizField)>[];
  for (final reply in QuizField.values) {
    if (answer != null && reply != answer) continue;
    if (ask.contains(reply)) continue;
    final replyValue = reply.valueOf(point);
    if (replyValue.isEmpty) continue;
    bool usable(QuizField field) {
      final value = field.valueOf(point);
      return field != reply &&
          value.isNotEmpty &&
          _normalized(value) != _normalized(replyValue);
    }

    if (ask.isEmpty) {
      for (final question in QuizField.values.where(usable)) {
        layouts.add(([(question, question.valueOf(point))], reply));
      }
    } else {
      final lines = [
        for (final field in QuizField.values)
          if (ask.contains(field) && usable(field))
            (field, field.valueOf(point)),
      ];
      if (lines.isNotEmpty) layouts.add((lines, reply));
    }
  }
  return layouts;
}

/// Sinh câu hỏi trắc nghiệm cho [deck]. Đáp án nhiễu lấy trong bộ trước rồi
/// mới tới [distractorPool] (thường là toàn bộ điểm yếu) để bộ nhỏ vẫn đủ 4
/// lựa chọn. Thẻ không đủ dữ liệu hoặc không đủ đáp án nhiễu bị bỏ qua.
List<QuizQuestion> buildQuiz(
  List<WeakPoint> deck, {
  Set<QuizField> ask = const {},
  QuizField? answer,
  Iterable<WeakPoint> distractorPool = const [],
  bool shuffle = true,
  math.Random? random,
  int optionCount = 4,
}) {
  final rng = random ?? math.Random();
  final order = List.of(deck);
  if (shuffle) order.shuffle(rng);
  final pool = [
    ...deck,
    ...distractorPool.where((point) => !deck.contains(point)),
  ];
  final questions = <QuizQuestion>[];
  for (final point in order) {
    final layouts = quizLayoutsFor(point, ask: ask, answer: answer);
    if (layouts.isEmpty) continue;
    final (lines, reply) = layouts[rng.nextInt(layouts.length)];
    final correct = reply.valueOf(point);
    final seen = {_normalized(correct)};
    final deckDistractors = <String>[];
    final extraDistractors = <String>[];
    for (final other in pool) {
      if (identical(other, point)) continue;
      final value = reply.valueOf(other);
      if (value.isEmpty || !seen.add(_normalized(value))) continue;
      (deck.contains(other) ? deckDistractors : extraDistractors).add(value);
    }
    deckDistractors.shuffle(rng);
    extraDistractors.shuffle(rng);
    final distractors = [
      ...deckDistractors,
      ...extraDistractors,
    ].take(optionCount - 1).toList();
    if (distractors.isEmpty) continue;
    final options = [correct, ...distractors]..shuffle(rng);
    questions.add(
      QuizQuestion(
        point: point,
        promptLines: lines,
        answer: reply,
        options: options,
        correctIndex: options.indexOf(correct),
      ),
    );
  }
  return questions;
}

/// Bộ nên học hôm nay: bộ chưa học hôm nay, lâu chưa học nhất (bộ chưa học
/// lần nào xếp trước theo thứ tự tạo).
FlashcardDeck? deckForToday(List<FlashcardDeck> decks, DateTime now) {
  final pending = decks
      .where((deck) => deck.pointIds.isNotEmpty && !deck.studiedOn(now))
      .toList();
  if (pending.isEmpty) return null;
  pending.sort((a, b) {
    final aLast = a.lastStudiedAt;
    final bLast = b.lastStudiedAt;
    if (aLast == null && bLast == null) {
      // Auto-split decks share a timestamp; keep their library order.
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0
          ? byCreated
          : decks.indexOf(a).compareTo(decks.indexOf(b));
    }
    if (aLast == null) return -1;
    if (bLast == null) return 1;
    return aLast.compareTo(bLast);
  });
  return pending.first;
}
