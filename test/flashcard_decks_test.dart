import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteeryk/app_state.dart';
import 'package:noteeryk/flashcard_decks.dart';
import 'package:noteeryk/models.dart';
import 'package:noteeryk/screens/quiz_screen.dart';
import 'package:noteeryk/widgets/paged_point_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

WeakPoint _word(
  String id,
  String title, {
  String reading = '',
  String hanViet = '',
  String meaning = '',
}) => WeakPoint(
  id: id,
  title: title,
  kind: WeaknessKind.vocabulary,
  content: meaning,
  reminder: '',
  note: '',
  tags: const [],
  notebookId: 'n',
  notebookTitle: 'Vở',
  page: 1,
  ocrText: '',
  createdAt: DateTime(2026),
  reading: reading,
  hanViet: hanViet,
);

final _words = [
  _word('a', '仮設', reading: 'かせつ', hanViet: 'GIẢ THIẾT', meaning: 'tạm thời'),
  _word('b', '被災', reading: 'ひさい', hanViet: 'BỊ TAI', meaning: 'bị thiên tai'),
  _word('c', '発電', reading: 'はつでん', hanViet: 'PHÁT ĐIỆN', meaning: 'phát điện'),
  _word('d', '受け入れる', reading: 'うけいれる', meaning: 'tiếp nhận'),
  _word('e', 'ばったり', reading: 'ばったり', meaning: 'tình cờ'),
];

void main() {
  test('split into balanced decks', () {
    final points = [for (var i = 0; i < 45; i++) _word('$i', 'w$i')];
    final decks = splitIntoDecks(points, 20);
    expect(decks.map((deck) => deck.length), [15, 15, 15]);
    expect(decks.expand((deck) => deck).toSet().length, 45);
    expect(splitIntoDecks(points.take(7).toList(), 20).single.length, 7);
    final shuffled = splitIntoDecks(
      points,
      20,
      shuffle: true,
      random: math.Random(3),
    );
    expect(shuffled.expand((deck) => deck).toSet().length, 45);
  });

  test('quiz uses the chosen fields and only valid cards', () {
    final quiz = buildQuiz(
      _words,
      ask: QuizField.meaning,
      answer: QuizField.kanji,
      random: math.Random(1),
    );
    // ばったり has no kanji, so it cannot be answered with the Kanji field.
    expect(quiz.map((q) => q.point.id).toSet(), {'a', 'b', 'c', 'd'});
    for (final question in quiz) {
      expect(question.prompt, question.point.content);
      expect(question.correctText, question.point.title);
      expect(question.options.length, 4);
      expect(question.options.toSet().length, 4);
    }

    // Kana-only words never ask "reading → kanji" style giveaways.
    expect(
      quizPairsFor(
        _words[4],
      ).where((pair) => {pair.$1, pair.$2}.containsAll({QuizField.kanji})),
      isEmpty,
    );

    final random = buildQuiz(_words, random: math.Random(2));
    expect(random, isNotEmpty);
    for (final question in random) {
      expect(question.ask, isNot(question.answer));
    }
  });

  test('deck JSON round trip and today suggestion', () {
    final deck =
        FlashcardDeck(
          id: 'd1',
          name: 'Bộ 1',
          pointIds: ['a', 'b'],
          createdAt: DateTime(2026, 1, 1),
        )..record(
          DeckSession(
            at: DateTime(2026, 1, 2, 9),
            activity: DeckActivity.quiz,
            correct: 3,
            total: 4,
          ),
          ['b'],
        );
    final copy = FlashcardDeck.fromJson(deck.toJson());
    expect(copy.pointIds, ['a', 'b']);
    expect(copy.wrongCounts, {'b': 1});
    expect(copy.lastOf(DeckActivity.quiz)?.accuracy, .75);

    final fresh = FlashcardDeck(
      id: 'd2',
      name: 'Bộ 2',
      pointIds: ['c'],
      createdAt: DateTime(2026, 1, 1),
    );
    expect(deckForToday([copy, fresh], DateTime(2026, 1, 2)), fresh);
    expect(deckForToday([copy], DateTime(2026, 1, 2)), isNull);
    expect(deckForToday([copy], DateTime(2026, 1, 3)), copy);
  });

  test('app state splits decks and skips deleted cards', () {
    SharedPreferences.setMockInitialValues({'autoSave': false});
    final state = AppState()..autoSave = false;
    addTearDown(state.dispose);
    state.weakPoints = List.of(_words);
    final decks = state.createSplitDecks(_words, maxSize: 2, shuffle: false);
    expect(decks.map((deck) => deck.name), ['Bộ 1', 'Bộ 2', 'Bộ 3']);
    expect(state.pointIdsInDecks, {'a', 'b', 'c', 'd', 'e'});
    state.deleteWeakPoints(['a']);
    expect(state.pointsForDeck(decks.first).map((p) => p.id), ['b']);
  });

  testWidgets('quiz grades answers and records the session', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'autoSave': false});
    final state = AppState()..autoSave = false;
    addTearDown(state.dispose);
    state.weakPoints = List.of(_words);
    final deck = state.createDeck('Bộ N2', _words.take(4));

    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(
          state: state,
          deck: deck,
          ask: QuizField.meaning,
          answer: QuizField.reading,
        ),
      ),
    );
    expect(find.text('Chọn đáp án đúng · Cách đọc'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);

    for (var question = 0; question < 4; question++) {
      // Always "don't know", then continue.
      await tester.tap(find.text('Bạn không biết?'));
      await tester.pump();
      await tester.tap(find.text(question == 3 ? 'Xem kết quả' : 'Tiếp tục'));
      await tester.pump();
    }
    expect(find.text('0%'), findsOneWidget);
    expect(deck.sessions.single.total, 4);
    expect(deck.wrongCounts.length, 4);
    expect(find.text('Làm lại 4 câu sai'), findsOneWidget);
  });

  testWidgets('picker shows 10 items per page and swipes to the next', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final points = [for (var i = 1; i <= 23; i++) _word('$i', 'Từ $i')];
    var selected = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PagedPointPicker(
              points: points,
              selectedIds: selected,
              onChanged: (ids) => setState(() => selected = ids),
            ),
          ),
        ),
      ),
    );
    expect(find.text('1–10 / 23'), findsOneWidget);
    expect(find.text('Từ 10'), findsOneWidget);
    expect(find.text('Từ 11'), findsNothing);

    await tester.tap(find.text('Chọn trang này'));
    await tester.pump();
    expect(selected.length, 10);

    await tester.fling(find.text('Từ 5'), const Offset(-600, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('11–20 / 23'), findsOneWidget);
    expect(find.text('Từ 11'), findsOneWidget);
  });
}
