import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:noteeryk/app_state.dart';
import 'package:noteeryk/models.dart';
import 'package:noteeryk/review.dart';
import 'package:noteeryk/services.dart';
import 'package:noteeryk/widgets/quick_check_sheet.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AI always validates strict structured output', () async {
    final serviceSource = await File('lib/services.dart').readAsString();

    expect(serviceSource, contains('_isStructuredOutputUnsupported(response)'));
    expect(serviceSource, contains('Every AI response must pass'));
    expect(
      serviceSource,
      contains("..._structuredRequestOptions(spec, preferLatency"),
    );
    expect(serviceSource, isNot(contains('compatibilityMode')));
  });

  test('reasoning payload reserves tokens and omits sampling params', () {
    final service = OpenRouterService()
      ..reasoningEffort = AiReasoningEffort.high;
    addTearDown(service.dispose);

    final luna = service.chatPayloadForTesting(modelId: 'openai/gpt-5.6-luna');
    expect(luna.containsKey('temperature'), isFalse);
    expect(luna.containsKey('max_tokens'), isFalse);
    expect(luna['max_completion_tokens'], greaterThan(1000));
    expect(luna['reasoning'], {'effort': 'high', 'exclude': true});

    final plain = service.chatPayloadForTesting(
      modelId: 'some/chat-model',
      reasoning: false,
    );
    expect(plain['temperature'], isNotNull);
    expect(plain['max_tokens'], 1000);
    expect(plain.containsKey('reasoning'), isFalse);

    // Claude 5 and GPT-6 reject temperature; sending it with
    // require_parameters leaves OpenRouter without any provider.
    for (final model in ['anthropic/claude-haiku-5.5', 'openai/gpt-6-luna']) {
      final payload = service.chatPayloadForTesting(
        modelId: model,
        reasoning: false,
      );
      expect(payload.containsKey('temperature'), isFalse, reason: model);
    }
  });

  test(
    'delete weak points can be undone and duplicates are reencountered',
    () async {
      SharedPreferences.setMockInitialValues({'autoSave': false});
      final state = AppState()..autoSave = false;
      addTearDown(state.dispose);
      WeakPoint point(String id, String title) => WeakPoint(
        id: id,
        title: title,
        kind: WeaknessKind.grammar,
        content: 'nghĩa',
        reminder: '',
        note: '',
        tags: const [],
        notebookId: 'n',
        notebookTitle: 'Vở',
        page: 1,
        ocrText: '',
        createdAt: DateTime(2026),
      );
      state.weakPoints = [point('a', 'のに'), point('b', 'ために'), point('c', 'ば')];

      final removed = state.deleteWeakPoints(['a', 'c']);
      expect(state.weakPoints.map((item) => item.id), ['b']);
      state.restoreWeakPoints(removed);
      expect(state.weakPoints.map((item) => item.id), ['a', 'b', 'c']);

      final duplicate = state.findDuplicateWeakPoint(
        WeaknessKind.grammar,
        '〜 ために',
      );
      expect(duplicate?.id, 'b');
      duplicate!
        ..lastReviewedAt = DateTime(2026)
        ..dueAt = DateTime(2030);
      state.reencounterWeakPoint(duplicate, sourceSentence: '合格するために勉強する。');
      expect(state.weakPoints.first.id, 'b');
      expect(duplicate.lapses, 1);
      expect(duplicate.isDue(DateTime.now()), isTrue);
      expect(duplicate.examples, contains('合格するために勉強する。'));
    },
  );

  test('SRS schedules again/good/easy like Anki and queues due cards', () {
    const scheduler = ReviewScheduler();
    final now = DateTime(2026, 9, 30, 9);
    WeakPoint point(String id) => WeakPoint(
      id: id,
      title: id,
      kind: WeaknessKind.vocabulary,
      content: 'nghĩa',
      reminder: '',
      note: '',
      tags: const [],
      notebookId: 'n',
      notebookTitle: 'Vở',
      page: 1,
      ocrText: '',
      createdAt: now,
    );

    final card = point('a');
    expect(card.isNewCard, isTrue);
    scheduler.apply(card, ReviewRating.good, now: now);
    expect(card.dueAt, now.add(const Duration(days: 1)));
    scheduler.apply(card, ReviewRating.good, now: now);
    expect(card.intervalDays, 3);
    scheduler.apply(card, ReviewRating.again, now: now);
    expect(card.lapses, 1);
    expect(card.needsRevisit, isTrue);
    expect(WeakPoint.fromJson(card.toJson()).needsRevisit, isTrue);
    expect(card.reps, 0);
    expect(card.dueAt, now.add(ReviewScheduler.relearnDelay));
    expect(card.ease, closeTo(2.3, 1e-9));

    final fresh = point('b');
    final later = point('c')
      ..lastReviewedAt = now
      ..dueAt = now.add(const Duration(days: 2));
    final queue = scheduler.dueQueue([later, fresh, card], now: now);
    expect(queue.map((item) => item.id), ['b']);
    final afterRelearn = scheduler.dueQueue([
      later,
      fresh,
      card,
    ], now: now.add(const Duration(minutes: 11)));
    expect(afterRelearn.map((item) => item.id), ['a', 'b']);
    scheduler.apply(
      card,
      ReviewRating.good,
      now: now.add(const Duration(days: 1)),
    );
    expect(card.needsRevisit, isFalse);
  });

  test(
    'flashcard uses selected fields on each side and skips missing Kanji',
    () {
      final point = WeakPoint(
        id: 'kanji',
        title: '認識する',
        kind: WeaknessKind.vocabulary,
        content: 'nhận thức',
        reminder: '',
        note: '',
        tags: const [],
        notebookId: 'n',
        notebookTitle: 'Vở',
        page: 1,
        ocrText: '',
        createdAt: DateTime(2026),
        hanViet: 'NHẬN THỨC',
      );
      expect(kanjiOnCard(point), '認識');
      const front = {FlashcardField.kanji, FlashcardField.hanViet};
      const back = {FlashcardField.meaning, FlashcardField.word};
      expect(flashcardSideContent(point, front), [
        (FlashcardField.kanji, '認識'),
        (FlashcardField.hanViet, 'NHẬN THỨC'),
      ]);
      expect(flashcardSideContent(point, back), [
        (FlashcardField.word, '認識する'),
        (FlashcardField.meaning, 'nhận thức'),
      ]);
      expect(canShowConfiguredFlashcard(point, front, back), isTrue);
      point.title = 'たべる';
      expect(canShowConfiguredFlashcard(point, front, back), isFalse);
    },
  );

  test('flashcard face settings are saved', () async {
    final root = await Directory.systemTemp.createTemp('noteeryk_cards_');
    addTearDown(() => root.delete(recursive: true));
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(root.path);
    addTearDown(() => PathProviderPlatform.instance = originalProvider);
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    addTearDown(state.dispose);
    state.setFlashcardFields(
      front: true,
      fields: {FlashcardField.meaning, FlashcardField.hanViet},
    );
    state.setFlashcardFields(front: false, fields: {FlashcardField.word});
    await state.saveFlashcardSettings();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('flashcardFrontFields'),
      containsAll(['meaning', 'hanViet']),
    );
    expect(prefs.getStringList('flashcardBackFields'), ['word']);
    final reopened = AppState();
    addTearDown(reopened.dispose);
    await reopened.initialize();
    expect(reopened.flashcardFrontFields, {
      FlashcardField.meaning,
      FlashcardField.hanViet,
    });
    expect(reopened.flashcardBackFields, {FlashcardField.word});
  });

  test('grammar flashcard blanks the pattern in the source sentence', () {
    final point = WeakPoint(
      id: 'g',
      title: '〜わけではない',
      kind: WeaknessKind.grammar,
      content: 'không hẳn là',
      reminder: '',
      note: '',
      tags: const [],
      notebookId: 'n',
      notebookTitle: 'Vở',
      page: 1,
      ocrText: '',
      createdAt: DateTime(2026),
      sourceSentence: '嫌いなわけではないが、あまり食べない。',
    );
    final face = buildFlashcard(point);
    expect(face.front, '嫌いな＿＿＿が、あまり食べない。');
    expect(face.answer, '〜わけではない');

    final tsv = exportAnkiTsv([point]);
    expect(tsv, startsWith('#separator:tab'));
    expect(tsv.trim().split('\n').last.split('\t'), hasLength(3));
  });

  test('old or partly broken weak points still load', () {
    final legacy = WeakPoint.fromJson({
      'id': 'old',
      'title': '認識',
      'kind': 'vocabulary',
      'content': 'nhận thức',
      'reminder': '',
      'note': '',
      'tags': ['N2'],
      'notebookId': 'n',
      'notebookTitle': 'Vở',
      'page': 2,
      'ocrText': '',
      'createdAt': '2026-08-01T10:00:00.000',
    });
    expect(legacy.isNewCard, isTrue);
    expect(legacy.mistake, isEmpty);

    final broken = WeakPoint.fromJson({
      'id': 'x',
      'kind': 'unknown',
      'page': null,
    });
    expect(broken.kind, WeaknessKind.other);
    expect(broken.page, 1);
  });

  test('quick check keeps exactly one correct choice per question', () {
    final question = QuickCheckQuestion.fromJson({
      'label': '2',
      'questionType': '文脈規定',
      'stem': '（　）に入れるのに最もよいもの',
      'choices': [
        {'label': '1', 'text': 'A', 'correct': false, 'reason': ''},
        {'label': '2', 'text': 'B', 'correct': true, 'reason': ''},
        {'label': '3', 'text': 'C', 'correct': true, 'reason': ''},
      ],
      'answer': '2',
      'explanation': '',
      'point': 'B',
      'kind': 'vocabulary',
    });
    expect(question.correctIndex, 1);
    expect(question.choices.where((choice) => choice.correct), hasLength(1));
    expect(question.questionType, JlptQuestionType.contextVocab);
    expect(question.correctText, '2. B');
  });

  test('question count estimate treats ★ ordering as one question', () {
    expect(
      estimateQuestionCount(
        '1 彼は（　）行った。\n1 a 2 b 3 c 4 d\n2 私は ＿＿ ＿＿ ★ ＿＿ です。',
      ),
      2,
    );
    expect(estimateQuestionCount('ただの文'), 1);
  });

  test('weak point schemas include mistake, question type and no AI tags', () {
    final service = OpenRouterService();
    addTearDown(service.dispose);
    Map<String, dynamic> itemSchema(Map<String, dynamic> options) {
      final schema =
          ((options['response_format'] as Map)['json_schema'] as Map)['schema']
              as Map;
      return Map<String, dynamic>.from(
        ((schema['properties'] as Map)['items'] as Map)['items'] as Map,
      );
    }

    final properties =
        itemSchema(
              service.weakPointDraftRequestOptionsForTesting(),
            )['properties']
            as Map;
    expect(
      properties.keys,
      containsAll(['mistake', 'correctAnswer', 'questionType']),
    );
    expect(properties.keys, isNot(contains('tags')));
    expect(properties.keys, isNot(contains('note')));
    final typeEnum = (properties['questionType'] as Map)['enum'] as List;
    expect(typeEnum, contains('文の組み立て'));

    final draft = WeakPointDraft.fromJson({
      'kind': 'grammar',
      'title': 'のに',
      'meaning': 'vậy mà',
      'examples': [
        {'japanese': '雨なのに出かけた。', 'meaning': 'Trời mưa vậy mà vẫn đi.'},
      ],
      'questionType': '文法形式の判断',
      'uncertain': '',
    });
    expect(draft.examples.single, '雨なのに出かけた。 — Trời mưa vậy mà vẫn đi.');
    expect(draft.questionType.tag, '問題:文法形式の判断');
  });

  test('solve output formats every question separately', () {
    final service = OpenRouterService();
    addTearDown(service.dispose);
    final formatted = service.formatStructuredResultForTesting(
      AiTask.solve,
      jsonEncode({
        'questions': [
          {
            'label': '1',
            'questionType': '漢字読み',
            'stem': '',
            'choices': [
              {'label': '1', 'text': 'きょう', 'correct': true, 'reason': 'Đúng'},
            ],
            'answer': 'きょう',
            'explanation': 'Âm On.',
            'point': '今日',
            'kind': 'kanji',
          },
          {
            'label': '2',
            'questionType': '文の組み立て',
            'stem': '',
            'choices': [],
            'answer': '3',
            'explanation': 'Thứ tự 2-4-3-1.',
            'point': '',
            'kind': 'grammar',
          },
        ],
        'warning': '',
      }),
    );
    expect(formatted, contains('Câu 1 · Đọc Kanji'));
    expect(formatted, contains('Câu 2 · Sắp xếp câu'));
    expect(formatted, contains('Thứ tự 2-4-3-1.'));
  });

  test('autosave batches pen changes without lifecycle backup', () async {
    final stateSource = await File('lib/app_state.dart').readAsString();
    final appSource = await File('lib/app.dart').readAsString();

    expect(stateSource, contains('Timer(_persistenceDebounce'));
    expect(
      stateSource,
      contains('await Isolate.run(() => jsonEncode(snapshot))'),
    );
    expect(stateSource, contains('encoded.length <= _preferencesMirrorLimit'));
    expect(stateSource, isNot(contains('_persistStrokes()')));
    expect(appSource, isNot(contains('flushPersistence(snapshot: true)')));
  });

  test(
    'storage cleanup keeps referenced files and limits generated backups',
    () async {
      final stateSource = await File('lib/app_state.dart').readAsString();
      final settingsSource = await File(
        'lib/screens/settings_screen.dart',
      ).readAsString();

      expect(stateSource, contains('cleanupUnusedStorage'));
      expect(stateSource, contains('_maxRetainedBackups = 2'));
      expect(stateSource, contains('_migratePdfBackgroundsToOnDemand'));
      expect(stateSource, contains('renderPdfPage'));
      expect(stateSource, contains('quality: 100'));
      expect(
        stateSource,
        contains('referenced.contains(entity.absolute.path)'),
      );
      expect(settingsSource, contains('Dọn dung lượng thừa'));
    },
  );

  test('Luna chỉ nhận text sau OCR, không nhận lại ảnh đã khoanh', () async {
    final editorSource = await File(
      'lib/screens/editor_screen.dart',
    ).readAsString();

    expect(editorSource, isNot(contains('imagePath: crop.path')));
    expect(editorSource, isNot(contains('imagePath: resolvedImage')));
  });

  test('prompt không còn tự ép JSON bằng văn bản', () async {
    final serviceSource = await File('lib/services.dart').readAsString();

    expect(serviceSource, isNot(contains('Schema bắt buộc:')));
    expect(serviceSource, isNot(contains('Trả về DUY NHẤT JSON')));
  });

  test('giải thích giữ đủ phần dù model trả cấu trúc hơi khác schema', () {
    final service = OpenRouterService();
    addTearDown(service.dispose);
    final formatted = service.formatStructuredResultForTesting(
      AiTask.explain,
      jsonEncode({
        'meaning': 'Nghĩa tổng quát',
        'grammar': {
          'form': '〜わけではない',
          'explanation': 'Không hẳn là',
          'use': 'Dùng để phủ định một phần.',
        },
        'breakdown': ['彼が来ない → Anh ấy không đến'],
        'choices': {
          'option': 'B',
          'correct': true,
          'explanation': 'Phù hợp với ngữ cảnh.',
        },
        'warning': '',
      }),
    );

    expect(formatted, contains('Nghĩa tổng quát'));
    expect(formatted, contains('Cấu trúc chính'));
    expect(formatted, contains('〜わけではない'));
    expect(formatted, contains('Tách câu'));
    expect(formatted, contains('Đáp án đúng: B'));
  });

  test('không âm thầm coi mỗi nghĩa là một giải thích đầy đủ', () {
    final service = OpenRouterService();
    addTearDown(service.dispose);
    final formatted = service.formatStructuredResultForTesting(
      AiTask.explain,
      jsonEncode({'meaning': 'Chỉ có nghĩa', 'warning': ''}),
    );

    expect(formatted, contains('Chỉ có nghĩa'));
    expect(formatted, contains('AI chưa trả đủ'));
  });

  test(
    'kết quả JSON dấu ngoặc cong không lộ schema và hiện đúng xuống dòng',
    () {
      final service = OpenRouterService();
      addTearDown(service.dispose);
      final formatted = service.formatStructuredResultForTesting(
        AiTask.translate,
        r'{“translation”:“Dòng 1\\n\\nDòng 2”,“nuance”:“”,“warning”:“”}',
      );

      expect(formatted, 'Dòng 1\n\nDòng 2');
      expect(formatted, isNot(contains('translation')));
      expect(formatted, isNot(contains(r'\n')));
      expect(formatted, isNot(contains('{')));
    },
  );

  test('JSON bị cắt vẫn chỉ hiện phần đọc được, không lộ khóa transport', () {
    final service = OpenRouterService();
    addTearDown(service.dispose);
    final formatted = service.formatStructuredResultForTesting(
      AiTask.translate,
      '{“translation”:“Bản dịch chưa đóng',
    );

    expect(formatted, 'Bản dịch chưa đóng');
    expect(formatted, isNot(contains('translation')));
    expect(formatted, isNot(contains('{')));
  });

  test('mọi luồng AI dùng JSON Schema strict ở tầng OpenRouter', () {
    final service = OpenRouterService();
    addTearDown(service.dispose);

    void verifySchema(Map<String, dynamic> schema) {
      if (schema['type'] == 'object') {
        expect(schema['additionalProperties'], isFalse);
        final properties = Map<String, dynamic>.from(
          schema['properties'] as Map,
        );
        expect((schema['required'] as List).toSet(), properties.keys.toSet());
        for (final property in properties.values.whereType<Map>()) {
          verifySchema(Map<String, dynamic>.from(property));
        }
      } else if (schema['type'] == 'array' && schema['items'] is Map) {
        verifySchema(Map<String, dynamic>.from(schema['items'] as Map));
      }
    }

    void verifyOptions(Map<String, dynamic> options) {
      expect(options['stream'], isFalse);
      expect((options['provider'] as Map)['require_parameters'], isTrue);
      expect(
        (options['plugins'] as List).single,
        containsPair('id', 'response-healing'),
      );
      final responseFormat = Map<String, dynamic>.from(
        options['response_format'] as Map,
      );
      expect(responseFormat['type'], 'json_schema');
      final jsonSchema = Map<String, dynamic>.from(
        responseFormat['json_schema'] as Map,
      );
      expect(jsonSchema['strict'], isTrue);
      expect(jsonSchema['name'], isNotEmpty);
      verifySchema(Map<String, dynamic>.from(jsonSchema['schema'] as Map));
    }

    for (final task in AiTask.values) {
      verifyOptions(service.structuredRequestOptionsForTesting(task));
    }
    verifyOptions(service.weakPointDraftRequestOptionsForTesting());
    verifyOptions(service.ocrRequestOptionsForTesting());
  });

  test(
    'từ chối backup thiếu ảnh trang và giữ nguyên thư viện hiện tại',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      state.autoSave = false;
      state.addNotebook(
        const NotebookData(
          id: 'current-book',
          title: 'Dữ liệu hiện tại',
          type: 'Notebook',
          pages: 1,
          color: Color(0xff000000),
        ),
      );
      final temporary = await Directory.systemTemp.createTemp(
        'noteeryk_backup_test_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final backup = File('${temporary.path}/broken.json');
      await backup.writeAsString(
        jsonEncode({
          'format': 'note-eryk-backup',
          // Backups created by older builds used the library version as the
          // envelope version. Keep accepting those files.
          'version': 2,
          'notebooks': [
            const NotebookData(
              id: 'imported-book',
              title: 'Bản lỗi',
              type: 'Notebook',
              pages: 1,
              color: Color(0xff000000),
            ).toJson(),
          ],
          'strokes': <String, dynamic>{},
          'pageImages': {
            'imported-book': {
              '1': ['/missing/page-1.jpg'],
            },
          },
          'attachments': <String, String>{},
        }),
        flush: true,
      );

      expect(await state.importBackupFile(backup.path), isFalse);
      expect(state.notebooks.single.id, 'current-book');
      expect(state.lastBackupError, contains('thiếu'));
    },
  );

  test('backup đầy đủ có thể khôi phục cả ảnh trang', () async {
    final root = await Directory.systemTemp.createTemp(
      'noteeryk_backup_roundtrip_',
    );
    addTearDown(() => root.delete(recursive: true));
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(root.path);
    addTearDown(() => PathProviderPlatform.instance = originalProvider);

    final sourceImage = File('${root.path}/page-1.jpg');
    const imageBytes = <int>[1, 2, 3, 4, 5, 6, 7, 8];
    await sourceImage.writeAsBytes(imageBytes, flush: true);
    final sourceState = AppState()..autoSave = false;
    addTearDown(sourceState.dispose);
    sourceState.addNotebook(
      const NotebookData(
        id: 'source-book',
        title: 'Vở có ảnh',
        type: 'Notebook',
        pages: 1,
        color: Color(0xff000000),
      ),
    );
    sourceState.attachImages('source-book', 1, [sourceImage.path]);

    final backup = await sourceState.exportBackupSnapshot();
    expect(await backup.exists(), isTrue);

    final restoredState = AppState()..autoSave = false;
    addTearDown(restoredState.dispose);
    restoredState.addNotebook(
      const NotebookData(
        id: 'old-book',
        title: 'Dữ liệu cũ',
        type: 'Notebook',
        pages: 1,
        color: Color(0xff000000),
      ),
    );

    expect(await restoredState.importBackupFile(backup.path), isTrue);
    expect(restoredState.notebooks.single.id, 'source-book');
    final restoredImage = File(
      restoredState.imagesForPage('source-book', 1).single,
    );
    expect(await restoredImage.exists(), isTrue);
    expect(await restoredImage.readAsBytes(), imageBytes);
  });

  test(
    'tự nối lại đường dẫn ảnh khi thư mục ứng dụng đổi sau cập nhật',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'noteeryk_relocated_path_',
      );
      addTearDown(() => root.delete(recursive: true));
      final originalProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(root.path);
      addTearDown(() => PathProviderPlatform.instance = originalProvider);
      SharedPreferences.setMockInitialValues({'autoSave': false});

      final documents = Directory('${root.path}/documents');
      final support = Directory('${root.path}/support');
      final currentImage = File(
        '${documents.path}${Platform.pathSeparator}imports${Platform.pathSeparator}page_images${Platform.pathSeparator}page-1.jpg',
      );
      await currentImage.parent.create(recursive: true);
      await currentImage.writeAsBytes(const [9, 8, 7, 6], flush: true);
      const oldPath = '/old/container/imports/page_images/page-1.jpg';
      final snapshot = {
        'version': 2,
        'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
        'notebooks': [
          const NotebookData(
            id: 'relocated-book',
            title: 'Vở sau cập nhật',
            type: 'Notebook',
            pages: 1,
            color: Color(0xff000000),
          ).toJson(),
        ],
        'folders': <dynamic>[],
        'strokes': <String, dynamic>{},
        'pinnedNotes': <String, dynamic>{},
        'pageImages': {
          'relocated-book': {
            '1': [oldPath],
          },
        },
        'imagePlacements': {
          'relocated-book:1:background': const PageImagePlacement(
            id: 'relocated-book:1:background',
            path: oldPath,
            rect: Rect.fromLTWH(0, 0, 1, 1),
            isBackground: true,
          ).toJson(),
        },
        'blankPages': <dynamic>[],
        'sourceDocuments': <String, dynamic>{},
        'lastPages': <String, dynamic>{},
        'weakPoints': <dynamic>[],
      };
      await documents.create(recursive: true);
      await support.create(recursive: true);
      await File(
        '${root.path}/support/notebook_library_v2.json',
      ).writeAsString(jsonEncode(snapshot), flush: true);

      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      await state.flushPersistence();

      expect(state.imagesForPage('relocated-book', 1), [currentImage.path]);
      expect(
        state.imagePlacementsForPage('relocated-book', 1).single.path,
        currentImage.path,
      );
    },
  );

  test('gán một model cho nhiều chức năng', () {
    final state = AppState();
    addTearDown(state.dispose);
    const model = OpenRouterModel(
      id: 'example/model',
      name: 'Model dùng chung',
      contextLength: 32000,
      vision: false,
      free: false,
    );

    state.setModelForSlots(const {
      AiModelSlot.translate,
      AiModelSlot.explain,
    }, model);

    expect(state.modelIds[AiModelSlot.translate], model.id);
    expect(state.modelIds[AiModelSlot.explain], model.id);
    expect(state.modelIds[AiModelSlot.solve], isNull);
  });

  test(
    'tùy chọn tự về bút chỉ áp dụng cho công cụ hỗ trợ và được lưu',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      addTearDown(state.dispose);

      expect(state.shouldReturnToPenAfter(EditorTool.translate), isFalse);
      state.autoReturnToPenAfterAssistiveTool = true;

      expect(state.shouldReturnToPenAfter(EditorTool.translate), isTrue);
      expect(state.shouldReturnToPenAfter(EditorTool.dictionary), isTrue);
      expect(state.shouldReturnToPenAfter(EditorTool.pen), isFalse);
      expect(state.shouldReturnToPenAfter(EditorTool.highlighter), isFalse);

      await state.saveGeneralSettings();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('autoReturnToPenAfterAssistiveTool'), isTrue);
    },
  );

  test('tách bản nháp điểm yếu theo loại và giữ câu gốc', () {
    final draft = WeakPointDraft.fromJson({
      'title': '尊重',
      'kind': 'vocabulary',
      'meaning': 'tôn trọng trong câu đã khoanh',
      'reading': 'そんちょう',
      'sourceSentence': '彼の意見を尊重する。',
      'tags': ['N3', 'Từ vựng'],
    });

    expect(draft.kind, WeaknessKind.vocabulary);
    expect(draft.title, '尊重');
    expect(draft.content, contains('trong câu'));
    expect(draft.sourceSentence, contains('尊重'));
    expect(draft.tags, contains('Từ vựng'));
  });

  test('ảnh nền và ảnh chèn có vị trí độc lập', () {
    final state = AppState();
    addTearDown(state.dispose);

    state.attachImages('book', 1, const ['/tmp/pdf-page.png']);
    state.attachImages('book', 1, const [
      '/tmp/photo.png',
    ], asPageBackground: false);
    final placements = state.imagePlacementsForPage('book', 1);
    final background = placements.singleWhere((item) => item.isBackground);
    final editable = placements.singleWhere((item) => !item.isBackground);

    expect(background.rect, const Rect.fromLTWH(0, 0, 1, 1));
    expect(editable.rect.width, lessThan(1));

    state.updateImagePlacement(
      editable.copyWith(rect: const Rect.fromLTWH(.2, .2, .4, .3)),
    );
    expect(
      state
          .imagePlacementsForPage('book', 1)
          .singleWhere((item) => item.id == editable.id)
          .rect,
      const Rect.fromLTWH(.2, .2, .4, .3),
    );

    state.removePageImage('book', 1, editable.id);
    expect(state.imagesForPage('book', 1), const ['/tmp/pdf-page.png']);
  });

  test('mỗi vở giữ cài đặt giấy riêng', () {
    final state = AppState();
    addTearDown(state.dispose);
    const notebook = NotebookData(
      id: 'book',
      title: 'N3',
      type: 'Vở ghi',
      pages: 1,
      color: Color(0xff000000),
      paperStyle: PaperStyle.lined,
      paperLineOpacity: .12,
    );
    state.addNotebook(notebook);
    state.updateNotebook(
      notebook.copyWith(paperStyle: PaperStyle.grid, paperLineOpacity: .28),
    );

    expect(state.notebooks.single.paperStyle, PaperStyle.grid);
    expect(state.notebooks.single.paperLineOpacity, .28);
  });

  test('crop ảnh thay đường dẫn nhưng giữ nguyên vị trí', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.attachImages('book', 1, const [
      '/tmp/original.png',
    ], asPageBackground: false);
    final placement = state.imagePlacementsForPage('book', 1).single;

    state.replacePageImage('book', 1, placement, '/tmp/cropped.png');

    final updated = state.imagePlacementsForPage('book', 1).single;
    expect(updated.path, '/tmp/cropped.png');
    expect(updated.rect, placement.rect);
  });

  test('nét viết được lưu riêng theo từng trang', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.autoSave = false;
    final stroke = InkStroke(
      points: [StrokePoint(Offset(10, 10), 1)],
      color: Color(0xff000000),
      width: 3,
      tool: EditorTool.pen,
      createdAt: DateTime(2026, 1, 1),
    );
    final otherStroke = InkStroke(
      points: [StrokePoint(Offset(20, 20), 1)],
      color: Color(0xffff0000),
      width: 3,
      tool: EditorTool.pen,
      createdAt: DateTime(2026, 1, 1),
    );

    state.saveStrokes('book', [stroke], 1);
    state.saveStrokes('book', [otherStroke], 2);

    expect(state.strokesFor('book', 1), [stroke]);
    expect(state.strokesFor('book', 2), [otherStroke]);
  });

  test('mỗi vở nhớ trang cuối và model mặc định là Gemini Flash', () {
    final state = AppState();
    addTearDown(state.dispose);
    const notebook = NotebookData(
      id: 'book-pages',
      title: 'Book',
      type: 'Notebook',
      pages: 600,
      color: Color(0xff000000),
    );
    state.addNotebook(notebook);
    state.open(notebook, page: 340);
    state.closeEditor();
    state.open(notebook);

    expect(state.openPage, 340);
    expect(state.selectedModelId, AppState.defaultAiModelId);
  });

  test('folder nested move, cycle protection and undo', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.autoSave = false;
    state.addNotebook(
      const NotebookData(
        id: 'book',
        title: 'Book',
        type: 'Notebook',
        pages: 1,
        color: Color(0xff000000),
      ),
    );
    state.createFolder('JLPT');
    final root = state.folders.single;
    state.createFolder('N3', parentId: root.id);
    final child = state.folders.last;
    expect(state.moveFolder(root.id, child.id), isFalse);
    expect(state.moveNotebookToFolder('book', child.id), isTrue);
    expect(state.folderNoteCount(root.id), 1);
    state.undoFolderAction();
    expect(state.notebooks.single.folderId, isNull);
  });

  test('deleting folder can move notes to trash and undo', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.autoSave = false;
    state.addNotebook(
      const NotebookData(
        id: 'book',
        title: 'Book',
        type: 'Notebook',
        pages: 1,
        color: Color(0xff000000),
      ),
    );
    state.createFolder('JLPT');
    final folder = state.folders.single;
    state.moveNotebookToFolder('book', folder.id);
    state.deleteFolder(folder.id, moveToTrash: true);
    expect(state.notebooks.single.isTrashed, isTrue);
    expect(state.folders.single.isTrashed, isTrue);
    state.undoFolderAction();
    expect(state.notebooks.single.isTrashed, isFalse);
  });

  test('deleting a root folder moves notes to the library root', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.autoSave = false;
    state.addNotebook(
      const NotebookData(
        id: 'book',
        title: 'Book',
        type: 'Notebook',
        pages: 1,
        color: Color(0xff000000),
      ),
    );
    state.createFolder('JLPT');
    final folder = state.folders.single;
    expect(state.moveNotebookToFolder('book', folder.id), isTrue);

    state.deleteFolder(folder.id, moveToTrash: false);

    expect(state.folders, isEmpty);
    expect(state.notebooks.single.folderId, isNull);
    expect(state.notebooks.single.isTrashed, isFalse);
  });

  test('moving to the current folder is a no-op', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.autoSave = false;
    state.addNotebook(
      const NotebookData(
        id: 'book',
        title: 'Book',
        type: 'Notebook',
        pages: 1,
        color: Color(0xff000000),
      ),
    );
    state.createFolder('JLPT');
    final folder = state.folders.single;
    expect(state.moveNotebookToFolder('book', folder.id), isTrue);
    expect(state.moveNotebookToFolder('book', folder.id), isFalse);
    expect(state.moveFolder(folder.id, null), isFalse);
  });

  test('bulk trash and restore notebooks supports undo', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.autoSave = false;
    for (final id in ['book-1', 'book-2', 'book-3']) {
      state.addNotebook(
        NotebookData(
          id: id,
          title: id,
          type: 'Notebook',
          pages: 1,
          color: const Color(0xff000000),
        ),
      );
    }

    expect(state.moveNotebooksToTrash(['book-1', 'book-2']), isTrue);
    expect(
      state.notebooks.where((note) => note.isTrashed).map((note) => note.id),
      containsAll(['book-1', 'book-2']),
    );
    state.undoFolderAction();
    expect(state.notebooks.where((note) => note.isTrashed), isEmpty);

    state.moveNotebooksToTrash(['book-1', 'book-2']);
    expect(state.restoreNotebooksFromTrash(['book-1', 'book-2']), isTrue);
    expect(state.notebooks.where((note) => note.isTrashed), isEmpty);
  });

  test('pinned folders are sorted before normal folders', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.autoSave = false;
    state.createFolder('Alpha');
    state.createFolder('Zulu');
    expect(state.folders.map((folder) => folder.id).toSet(), hasLength(2));
    final zulu = state.folders.singleWhere((folder) => folder.name == 'Zulu');
    state.pinFolder(zulu.id);

    expect(state.childFolders(null).map((folder) => folder.name), [
      'Zulu',
      'Alpha',
    ]);
  });

  test('tags remain independent from a notebook folder', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.autoSave = false;
    state.addNotebook(
      const NotebookData(
        id: 'book',
        title: 'Book',
        type: 'Notebook',
        pages: 1,
        color: Color(0xff000000),
      ),
    );
    state.createFolder('JLPT');
    final folder = state.folders.single;
    expect(state.moveNotebookToFolder('book', folder.id), isTrue);
    state.setNotebookTags('book', ['N3', ' dễ nhầm ', 'N3']);
    expect(state.notebooks.single.folderId, folder.id);
    expect(state.notebooks.single.tags, ['N3', 'dễ nhầm']);
  });

  test('old Luna default moves to Gemini once, custom models stay', () async {
    final root = await Directory.systemTemp.createTemp('noteeryk_model_');
    addTearDown(() => root.delete(recursive: true));
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(root.path);
    addTearDown(() => PathProviderPlatform.instance = originalProvider);
    SharedPreferences.setMockInitialValues({
      'autoSave': false,
      'selectedModelId': 'openai/gpt-5.6-luna',
      'selectedModelName': 'GPT-5.6 Luna',
      'ai_model_ids': jsonEncode({
        'translate': 'openai/gpt-5.6-luna',
        'dictionary': 'anthropic/claude-haiku-5.5',
      }),
    });

    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    expect(state.selectedModelId, 'google/gemini-3.8-flash');
    expect(state.modelIds[AiModelSlot.translate], 'google/gemini-3.8-flash');
    expect(
      state.modelIds[AiModelSlot.dictionary],
      'anthropic/claude-haiku-5.5',
    );
    // Slots that were never assigned get the per-feature defaults.
    expect(state.modelIds[AiModelSlot.solve], 'google/gemini-3.8-flash');

    // After the one-time migration, picking Luna again is respected.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedModelId', 'openai/gpt-5.6-luna');
    await prefs.remove('ai_model_ids');
    final again = AppState();
    addTearDown(again.dispose);
    await again.initialize();
    expect(again.selectedModelId, 'openai/gpt-5.6-luna');
  });

  test('fresh install uses Haiku for AI lookup and Gemini elsewhere', () async {
    final root = await Directory.systemTemp.createTemp('noteeryk_fresh_');
    addTearDown(() => root.delete(recursive: true));
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(root.path);
    addTearDown(() => PathProviderPlatform.instance = originalProvider);
    SharedPreferences.setMockInitialValues({'autoSave': false});

    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    expect(
      state.modelIds[AiModelSlot.dictionary],
      AppState.defaultDictionaryModelId,
    );
    for (final slot in AiModelSlot.values.where(
      (slot) => slot != AiModelSlot.dictionary,
    )) {
      expect(state.modelIds[slot], AppState.defaultAiModelId, reason: '$slot');
    }
  });

  test('ます titles map back to dictionary-form candidates', () {
    expect(dictionaryFormCandidates('食べます'), contains('食べる'));
    expect(dictionaryFormCandidates('書きます'), contains('書く'));
    expect(dictionaryFormCandidates('帰ります').first, '帰る');
    expect(dictionaryFormCandidates('勉強します'), ['勉強す', '勉強する', '勉強', '勉強しる']);
    expect(dictionaryFormCandidates('来ます'), contains('来る'));
    expect(dictionaryFormCandidates('勉強'), isEmpty);
    expect(readingsMatch('たべます', 'たべる'), isTrue);
    expect(readingsMatch('たべ ます', 'たべる'), isTrue);
    expect(readingsMatch('のみます', 'たべる'), isFalse);
  });

  test('quick check explanations written in Japanese are detected', () {
    final service = OpenRouterService();
    addTearDown(service.dispose);
    QuickCheckResult result(String explanation, String reason) =>
        QuickCheckResult(
          questions: [
            QuickCheckQuestion(
              label: '1',
              stem: '彼は（　）来なかった。',
              choices: [
                QuickCheckChoice(
                  label: '1',
                  text: 'ついに',
                  correct: true,
                  reason: reason,
                ),
              ],
              answer: '',
              explanation: explanation,
              point: 'ついに',
              kind: WeaknessKind.vocabulary,
            ),
          ],
        );
    expect(
      service.explainedInJapaneseForTesting(
        result('「ついに」は最後まで期待したことが起こらない場合に使う。', '文脈に合うので正解です。'),
      ),
      isTrue,
    );
    expect(
      service.explainedInJapaneseForTesting(
        result(
          '「ついに」nghĩa là "rốt cuộc", hợp với câu phủ định.',
          'Đúng vì hợp ngữ cảnh.',
        ),
      ),
      isFalse,
    );
    expect(looksJapaneseOnly('食べます'), isFalse); // too short to judge
    expect(answerLanguageRule('日本語'), isNot(contains('QUY TẮC')));
    expect(answerLanguageRule('Tiếng Việt'), contains('Tiếng Việt'));
  });

  test('format version and pen style survive JSON round trips', () {
    final point = WeakPoint.fromJson({
      'id': 'w',
      'title': '食べます',
      'kind': 'vocabulary',
      'formatVersion': weakPointFormatVersion,
    });
    expect(point.isNormalized, isTrue);
    expect(
      WeakPoint.fromJson(point.toJson()).formatVersion,
      weakPointFormatVersion,
    );
    expect(
      WeakPoint.fromJson({'id': 'old', 'title': 'x'}).isNormalized,
      isFalse,
    );

    final stroke = InkStroke(
      points: const [StrokePoint(Offset.zero, 1), StrokePoint(Offset(4, 4), 1)],
      color: const Color(0xff000000),
      width: 3,
      tool: EditorTool.pen,
      createdAt: DateTime(2026),
      penStyle: PenStyle.pencil,
    );
    expect(InkStroke.fromJson(stroke.toJson()).penStyle, PenStyle.pencil);
    final legacy = Map<String, dynamic>.from(stroke.toJson())
      ..remove('penStyle');
    expect(InkStroke.fromJson(legacy).penStyle, PenStyle.calligraphy);
  });
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final directory = Directory('$rootPath/documents');
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    final directory = Directory('$rootPath/support');
    await directory.create(recursive: true);
    return directory.path;
  }
}
