import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart';

import 'models.dart';

abstract class DictionaryRepository {
  Future<DictionaryEntry?> lookupExact(String text);
  Future<DictionaryEntry?> lookupNormalized(String text);
  Future<List<DictionaryEntry>> search(String text, {int limit = 30});
}

class LocalDictionaryRepository implements DictionaryRepository {
  static const _databaseVersion = 2;
  static const _dictionaryAsset = 'assets/japanese_dictionary.sql';
  static const _similarResultLimit = 5;
  static const _ignoredMeaningWords = <String>{
    'bị',
    'cái',
    'cho',
    'con',
    'có',
    'của',
    'để',
    'đến',
    'điều',
    'được',
    'hoặc',
    'khi',
    'không',
    'là',
    'làm',
    'một',
    'này',
    'người',
    'như',
    'nơi',
    'sự',
    'trong',
    'từ',
    'và',
    'về',
    'việc',
    'với',
  };

  Database? _databaseInstance;

  Iterable<String> _sqlStatements(String script) sync* {
    var buffer = StringBuffer();
    var inString = false;
    var inLineComment = false;
    var inBlockComment = false;

    for (var index = 0; index < script.length; index++) {
      final character = script[index];
      final next = index + 1 < script.length ? script[index + 1] : '';

      if (inLineComment) {
        if (character == '\n') {
          inLineComment = false;
          buffer.write(character);
        }
        continue;
      }
      if (inBlockComment) {
        if (character == '*' && next == '/') {
          inBlockComment = false;
          index++;
        }
        continue;
      }
      if (!inString && character == '-' && next == '-') {
        inLineComment = true;
        index++;
        continue;
      }
      if (!inString && character == '/' && next == '*') {
        inBlockComment = true;
        index++;
        continue;
      }
      if (character == "'") {
        buffer.write(character);
        if (inString && next == "'") {
          buffer.write(next);
          index++;
        } else {
          inString = !inString;
        }
        continue;
      }
      if (!inString && character == ';') {
        final statement = buffer.toString().trim();
        if (statement.isNotEmpty) yield statement;
        buffer = StringBuffer();
        continue;
      }
      buffer.write(character);
    }

    final statement = buffer.toString().trim();
    if (statement.isNotEmpty) yield statement;
  }

  Future<void> _importBundledDictionary(Database db) async {
    final script = await rootBundle.loadString(_dictionaryAsset);
    for (final sql in _sqlStatements(script)) {
      final command = sql.toUpperCase();
      // openDatabase already wraps create/upgrade callbacks in a transaction.
      if (command == 'BEGIN' ||
          command == 'BEGIN TRANSACTION' ||
          command == 'COMMIT') {
        continue;
      }
      await db.execute(sql);
    }
  }

  Future<Database> get _database async {
    final existing = _databaseInstance;
    if (existing != null && existing.isOpen) return existing;
    final databasesPath = await getDatabasesPath();
    _databaseInstance = await openDatabase(
      path.join(databasesPath, 'japanese_dictionary.db'),
      version: _databaseVersion,
      onCreate: (db, version) => _importBundledDictionary(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // The dictionary is read-only bundled data, so replacing the old
          // sample schema is safer than trying to infer a level per row.
          await db.execute('DROP TABLE IF EXISTS japanese_dictionary');
          await _importBundledDictionary(db);
        }
      },
    );
    return _databaseInstance!;
  }

  DictionaryEntry _entryFromRow(
    Map<String, Object?> row, {
    List<DictionaryEntry> similarEntries = const [],
  }) {
    final kanji = (row['kanji'] as String? ?? '').trim();
    return DictionaryEntry(
      word: kanji.isEmpty ? row['hiragana'] as String : kanji,
      reading: row['hiragana'] as String,
      hanViet: (row['han_viet'] as String? ?? '').trim(),
      meaning: row['meaning'] as String,
      level: (row['level'] as String? ?? '').trim(),
      similarEntries: similarEntries,
    );
  }

  Set<String> _meaningWords(String meaning) {
    return meaning
        .toLowerCase()
        .split(RegExp(r'[^a-zà-ỹđ0-9]+', caseSensitive: false))
        .where(
          (word) => word.length >= 2 && !_ignoredMeaningWords.contains(word),
        )
        .toSet();
  }

  Set<String> _meaningPhrases(String meaning) {
    return meaning
        .toLowerCase()
        .split(RegExp(r'[,;/()]'))
        .map((phrase) => phrase.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((phrase) => phrase.isNotEmpty)
        .toSet();
  }

  int _similarityScore(
    String sourceMeaning,
    String candidateMeaning,
    String sourceLevel,
    String candidateLevel,
  ) {
    final source = sourceMeaning.trim().toLowerCase();
    final candidate = candidateMeaning.trim().toLowerCase();
    if (source.isEmpty || candidate.isEmpty) return 0;

    final sourceWords = _meaningWords(source);
    final commonWords = sourceWords.intersection(_meaningWords(candidate));
    if (commonWords.isEmpty) return 0;
    final commonPhrases = _meaningPhrases(
      source,
    ).intersection(_meaningPhrases(candidate));
    // A one-word meaning must match a complete comma-separated sense. This
    // avoids treating "ăn" and "ăn khớp" as synonyms.
    if (sourceWords.length == 1 && commonPhrases.isEmpty) return 0;

    var score = source == candidate ? 1000 : 0;
    score += commonPhrases.length * 150;
    score += commonWords.length * 30;
    score += commonWords.fold<int>(0, (sum, word) => sum + word.length);
    if (sourceLevel == candidateLevel) score += 1;
    return score;
  }

  Future<List<DictionaryEntry>> _findSimilarEntries(
    Database db,
    Map<String, Object?> sourceRow,
  ) async {
    final sourceId = sourceRow['id'] as int;
    final sourceMeaning = sourceRow['meaning'] as String;
    final sourceLevel = sourceRow['level'] as String? ?? '';
    if (_meaningWords(sourceMeaning).isEmpty) return const [];

    final rows = await db.query(
      'japanese_dictionary',
      where: 'id <> ?',
      whereArgs: [sourceId],
    );
    final scored = <({int score, Map<String, Object?> row})>[];
    for (final row in rows) {
      final score = _similarityScore(
        sourceMeaning,
        row['meaning'] as String,
        sourceLevel,
        row['level'] as String? ?? '',
      );
      if (score > 0) scored.add((score: score, row: row));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (a.row['id'] as int).compareTo(b.row['id'] as int);
    });
    return scored
        .take(_similarResultLimit)
        .map((item) => _entryFromRow(item.row))
        .toList(growable: false);
  }

  Future<DictionaryEntry> _entryWithSuggestions(
    Database db,
    Map<String, Object?> row,
  ) async {
    final similarEntries = await _findSimilarEntries(db, row);
    return _entryFromRow(row, similarEntries: similarEntries);
  }

  @override
  Future<DictionaryEntry?> lookupExact(String text) async {
    final value = text.trim();
    if (value.isEmpty) return null;
    final db = await _database;
    final rows = await db.query(
      'japanese_dictionary',
      where: 'hiragana = TRIM(?) OR kanji = TRIM(?) OR han_viet = TRIM(?)',
      whereArgs: [value, value, value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _entryWithSuggestions(db, rows.first);
  }

  @override
  Future<DictionaryEntry?> lookupNormalized(String text) async {
    final value = text.trim();
    if (value.isEmpty) return null;
    final exact = await lookupExact(value);
    if (exact != null) return exact;
    final db = await _database;
    final rows = await db.query(
      'japanese_dictionary',
      where: '''
        instr(?, hiragana) > 0 OR
        (kanji IS NOT NULL AND instr(?, kanji) > 0) OR
        (han_viet IS NOT NULL AND instr(?, han_viet) > 0)
      ''',
      whereArgs: [value, value, value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _entryWithSuggestions(db, rows.first);
  }

  @override
  Future<List<DictionaryEntry>> search(String text, {int limit = 30}) async {
    final value = text.trim();
    if (value.isEmpty) return const [];
    final safeLimit = limit.clamp(1, 100);
    final capitalized = value.isEmpty
        ? value
        : '${value[0].toUpperCase()}${value.substring(1)}';
    final patterns = <String>{'%$value%', '%$capitalized%'};
    final clauses = <String>[];
    final args = <String>[];
    for (final pattern in patterns) {
      clauses.add(
        '(hiragana LIKE ? COLLATE NOCASE OR '
        'kanji LIKE ? COLLATE NOCASE OR '
        'han_viet LIKE ? COLLATE NOCASE OR '
        'meaning LIKE ? COLLATE NOCASE)',
      );
      args.addAll(List.filled(4, pattern));
    }
    final rows = await (await _database).query(
      'japanese_dictionary',
      columns: const [
        'id',
        'hiragana',
        'kanji',
        'han_viet',
        'meaning',
        'level',
      ],
      where: clauses.join(' OR '),
      whereArgs: args,
      limit: safeLimit,
    );
    return rows.map(_entryFromRow).toList(growable: false);
  }
}

abstract class OcrService {
  Future<String> recognizeImage(String imagePath);
}

class MlKitJapaneseOcrService implements OcrService {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.japanese,
  );

  @override
  Future<String> recognizeImage(String imagePath) async {
    final image = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(image);
    final text = result.text.trim();
    if (text.isEmpty) {
      throw const FormatException(
        'Không nhận dạng được chữ trong vùng đã chọn',
      );
    }
    return text;
  }
}

enum AiTask { translate, explain, solve, createWeakPoint, dictionary }

class OpenRouterService {
  static const _baseUrl = 'https://openrouter.ai/api/v1';
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  final Map<String, String> _completionCache = {};

  Future<void> testConnection(String apiKey) async {
    final response = await _request('GET', '/key', apiKey);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('OpenRouter trả về mã ${response.statusCode}');
    }
  }

  Future<List<OpenRouterModel>> listModels(String apiKey) async {
    final response = await _request('GET', '/models', apiKey);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Không tải được danh sách model');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? const [];
    return data
        .take(120)
        .map((raw) {
          final item = raw as Map<String, dynamic>;
          final architecture = item['architecture'] as Map<String, dynamic>?;
          final modalities =
              architecture?['input_modalities'] as List<dynamic>? ?? const [];
          final pricing = item['pricing'] as Map<String, dynamic>?;
          return OpenRouterModel(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? item['id'] as String? ?? 'Model',
            contextLength: item['context_length'] as int? ?? 0,
            vision: modalities.contains('image'),
            free:
                (pricing?['prompt'] == '0' ||
                (item['id'] as String? ?? '').endsWith(':free')),
          );
        })
        .where((model) => model.id.isNotEmpty)
        .toList();
  }

  Future<String> complete({
    required String apiKey,
    required String modelId,
    required AiTask task,
    required String text,
    required String jlpt,
    required String language,
    String? weaknessKind,
  }) async {
    final instruction = _promptFor(
      task,
      jlpt: jlpt,
      language: language,
      weaknessKind: weaknessKind,
    );
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) {
      throw ArgumentError('Chưa chọn model AI');
    }
    final cacheKey = [
      normalizedModelId,
      task.name,
      jlpt,
      language,
      weaknessKind ?? '',
      text.trim(),
    ].join('|');
    final cached = _completionCache[cacheKey];
    if (cached != null) return cached;
    final response = await _request(
      'POST',
      '/chat/completions',
      apiKey,
      body: jsonEncode({
        'model': normalizedModelId,
        'messages': [
          {'role': 'system', 'content': instruction},
          {'role': 'user', 'content': text},
        ],
        'temperature': 0.25,
        // Dictionary responses are intentionally short; limiting output
        // reduces latency and leaves less room for speculative explanations.
        'max_tokens': task == AiTask.dictionary ? 220 : 700,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Yêu cầu AI thất bại (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('AI không trả về nội dung');
    }
    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>;
    final content = message['content'] as String? ?? '';
    if (content.trim().isEmpty) {
      throw const FormatException('AI không trả về nội dung');
    }
    final formatted = _formatStructuredResult(task, content);
    // Keep the cache bounded; repeated OCR/AI taps then return instantly.
    if (_completionCache.length >= 60) {
      _completionCache.remove(_completionCache.keys.first);
    }
    _completionCache[cacheKey] = formatted;
    return formatted;
  }

  void dispose() => _client.close(force: true);

  /// Optional paid OCR path. The editor still defaults to on-device ML Kit;
  /// this is only used when the user explicitly enables AI image recognition.
  Future<String> recognizeImageWithAi({
    required String apiKey,
    required String modelId,
    required String imagePath,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final response = await _request(
      'POST',
      '/chat/completions',
      apiKey,
      body: jsonEncode({
        'model': modelId.trim(),
        'messages': [
          {
            'role': 'system',
            'content':
                'Bạn là OCR tiếng Nhật. Chỉ đọc đúng chữ nhìn thấy trong ảnh, giữ nguyên kanji/kana và xuống dòng. Trả về DUY NHẤT JSON object dạng {"text":"...","warning":""}. Không suy đoán phần bị cắt hoặc mờ.',
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': 'Đọc toàn bộ chữ Nhật trong vùng ảnh đã khoanh.',
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,${base64Encode(bytes)}',
                },
              },
            ],
          },
        ],
        'temperature': 0,
        'max_tokens': 160,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Nhận diện ảnh thất bại (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('AI không trả về nội dung OCR');
    }
    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>;
    final raw = message['content'] as String? ?? '';
    try {
      var jsonText = raw.trim();
      if (jsonText.startsWith('```')) {
        jsonText = jsonText.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
        jsonText = jsonText.replaceFirst(RegExp(r'\s*```$'), '');
      }
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      final text = (data['text'] as String? ?? '').trim();
      if (text.isEmpty) throw const FormatException('OCR trống');
      final warning = (data['warning'] as String? ?? '').trim();
      return warning.isEmpty ? text : '$text\n\nLưu ý OCR: $warning';
    } catch (_) {
      return raw.trim();
    }
  }

  String _promptFor(
    AiTask task, {
    required String jlpt,
    required String language,
    String? weaknessKind,
  }) {
    const shared = '''
Bạn là giáo viên tiếng Nhật chính xác và súc tích. Chỉ phân tích nội dung người dùng đã chủ động khoanh; không suy đoán phần nằm ngoài vùng chọn. Không trò chuyện, không chào hỏi, không dùng Markdown và không thêm lời dẫn. Nếu OCR có vẻ sai, ghi rõ trong trường warning thay vì tự bịa nội dung. Trả về DUY NHẤT một JSON object hợp lệ, không đặt trong code fence.''';
    final taskPrompt = switch (task) {
      AiTask.translate =>
        '''
Nhiệm vụ: dịch nguyên văn sang $language cho người học $jlpt.
Schema bắt buộc: {"translation":"...","nuance":"...","warning":""}.
Giữ tên riêng; câu dịch tự nhiên; nuance tối đa 1 câu.''',
      AiTask.explain =>
        '''
Nhiệm vụ: giải thích tiếng Nhật bằng $language ở độ khó phù hợp $jlpt.
Schema bắt buộc: {"meaning":"...","structures":[{"pattern":"...","meaning":"...","usage":"..."}],"segments":[{"japanese":"...","meaning":"..."}],"choiceAnalysis":[{"label":"A","correct":false,"reason":"..."}],"warning":""}.
Chỉ chọn tối đa 3 cấu trúc chính và tối đa 6 đoạn tách câu.
Nếu nội dung là câu hỏi có các lựa chọn, xác định đáp án đúng rồi giải thích thật đơn giản vì sao đúng và vì sao từng lựa chọn còn lại sai. Mỗi reason tối đa 2 câu. Nếu không có lựa chọn, trả choiceAnalysis là [].''',
      AiTask.solve =>
        '''
Nhiệm vụ: giải bài bằng $language, phù hợp $jlpt.
Schema bắt buộc: {"answer":"...","reason":"...","choices":[{"label":"A","correct":false,"reason":"..."}],"warning":""}.
Giải thích vì sao đúng và vì sao từng lựa chọn còn lại không phù hợp.''',
      AiTask.createWeakPoint =>
        '''
Nhiệm vụ: tạo bản nháp điểm yếu bằng $language cho người học $jlpt.
Loại người dùng đã chọn: ${weaknessKind ?? 'grammar'}.
Nếu là grammar, bắt buộc ghi nghĩa, cách chia/cấu trúc và ít nhất một ví dụ.
Nếu là vocabulary hoặc kanji, bắt buộc ghi cách đọc, nghĩa và Hán Việt nếu có; không được đoán nếu OCR không rõ.
Schema bắt buộc: {"title":"...","type":"Ngữ pháp|Từ vựng|Kanji|Đọc hiểu|Khác","meaning":"...","reading":"...","hanViet":"...","conjugation":"...","examples":["..."],"reminder":"...","note":"...","tags":["$jlpt"],"warning":""}.''',
      AiTask.dictionary =>
        '''
Nhiệm vụ: tra từ tiếng Nhật bằng AI cho người học $jlpt, trả lời bằng $language.
Chỉ tra đúng từ/cụm từ người dùng đã khoanh. Nếu có nhiều cách đọc hoặc nghĩa, chọn cách thông dụng nhất và ghi các nghĩa ngắn gọn. Không tự bịa khi OCR không rõ; ghi lý do trong warning.
Schema bắt buộc: {"word":"...","reading":"...","meaning":"...","partOfSpeech":"...","jlpt":"...","hanViet":"...","example":"...","exampleMeaning":"...","warning":""}.''',
    };
    return '$shared\n$taskPrompt';
  }

  String _formatStructuredResult(AiTask task, String raw) {
    try {
      var jsonText = raw.trim();
      if (jsonText.startsWith('```')) {
        jsonText = jsonText.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
        jsonText = jsonText.replaceFirst(RegExp(r'\s*```$'), '');
      }
      final data = jsonDecode(jsonText) as Map<String, dynamic>;
      final warning = (data['warning'] as String? ?? '').trim();
      final suffix = warning.isEmpty ? '' : '\n\nLưu ý OCR: $warning';
      return switch (task) {
        AiTask.translate =>
          '${data['translation'] ?? ''}${_optionalLine('Sắc thái', data['nuance'])}$suffix',
        AiTask.explain => _formatExplanation(data) + suffix,
        AiTask.solve => _formatSolution(data) + suffix,
        AiTask.createWeakPoint =>
          '${data['title'] ?? ''}\n\nNghĩa\n${data['meaning'] ?? data['content'] ?? ''}\n\nCách đọc\n${data['reading'] ?? ''}\n\nHán Việt\n${data['hanViet'] ?? ''}\n\nCách chia\n${data['conjugation'] ?? ''}\n\nVí dụ\n${(data['examples'] as List<dynamic>? ?? const []).join('\n')}\n\nĐiểm cần nhớ\n${data['reminder'] ?? ''}\n\nGhi chú\n${data['note'] ?? ''}$suffix',
        AiTask.dictionary =>
          '${data['word'] ?? ''}${_optionalLine('Cách đọc', data['reading'])}\n\nNghĩa\n${data['meaning'] ?? ''}${_optionalLine('Từ loại', data['partOfSpeech'])}${_optionalLine('JLPT', data['jlpt'])}${_optionalLine('Hán Việt', data['hanViet'])}${_optionalLine('Ví dụ', data['example'])}${_optionalLine('Dịch ví dụ', data['exampleMeaning'])}$suffix',
      };
    } catch (_) {
      // Keep the result useful when a selected model ignores the JSON contract.
      return raw.trim();
    }
  }

  String _formatExplanation(Map<String, dynamic> data) {
    final buffer = StringBuffer('Nghĩa\n${data['meaning'] ?? ''}');
    final structures = data['structures'] as List<dynamic>? ?? const [];
    if (structures.isNotEmpty) buffer.write('\n\nCấu trúc chính');
    for (final rawItem in structures) {
      final item = rawItem as Map<String, dynamic>;
      buffer.write('\n${item['pattern'] ?? ''} — ${item['meaning'] ?? ''}');
      final usage = item['usage'] as String? ?? '';
      if (usage.isNotEmpty) buffer.write('\n$usage');
    }
    final segments = data['segments'] as List<dynamic>? ?? const [];
    if (segments.isNotEmpty) buffer.write('\n\nTách câu');
    for (final rawItem in segments) {
      final item = rawItem as Map<String, dynamic>;
      buffer.write('\n${item['japanese'] ?? ''} → ${item['meaning'] ?? ''}');
    }
    final choices = data['choiceAnalysis'] as List<dynamic>? ?? const [];
    if (choices.isNotEmpty) {
      final correctLabels = choices
          .whereType<Map<String, dynamic>>()
          .where((item) => item['correct'] == true)
          .map((item) => '${item['label'] ?? ''}')
          .where((label) => label.isNotEmpty)
          .join(', ');
      if (correctLabels.isNotEmpty) {
        buffer.write('\n\nĐáp án đúng: $correctLabels');
      }
      buffer.write('\nGiải thích đơn giản từng lựa chọn:');
    }
    for (final rawItem in choices) {
      final item = rawItem as Map<String, dynamic>;
      buffer.write(
        '\n${item['label'] ?? ''}${item['correct'] == true ? ' ✓' : ' ✗'}: ${item['reason'] ?? ''}',
      );
    }
    return buffer.toString();
  }

  String _formatSolution(Map<String, dynamic> data) {
    final buffer = StringBuffer(
      'Đáp án\n${data['answer'] ?? ''}\n\nVì sao?\n${data['reason'] ?? ''}',
    );
    final choices = data['choices'] as List<dynamic>? ?? const [];
    if (choices.isNotEmpty) buffer.write('\n\nPhân tích lựa chọn');
    for (final rawItem in choices) {
      final item = rawItem as Map<String, dynamic>;
      buffer.write(
        '\n${item['label'] ?? ''}${item['correct'] == true ? ' ✓' : ''}: ${item['reason'] ?? ''}',
      );
    }
    return buffer.toString();
  }

  String _optionalLine(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '' : '\n\n$label\n$text';
  }

  Future<_HttpResult> _request(
    String method,
    String path,
    String apiKey, {
    String? body,
  }) async {
    final request = await _client.openUrl(method, Uri.parse('$_baseUrl$path'));
    var normalizedApiKey = apiKey.trim().replaceAll(RegExp(r'\s+'), '');
    // Pasted keys are sometimes copied with surrounding JSON quotes.
    if (normalizedApiKey.length >= 2 &&
        normalizedApiKey.startsWith('"') &&
        normalizedApiKey.endsWith('"')) {
      normalizedApiKey = normalizedApiKey.substring(
        1,
        normalizedApiKey.length - 1,
      );
    }
    if (normalizedApiKey.isEmpty) {
      throw ArgumentError('API key trống');
    }
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $normalizedApiKey',
    );
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set('HTTP-Referer', 'https://nihongo-notebook.local');
    request.headers.set('X-Title', 'Note Eryk');
    // HttpClientRequest.write can reject non-ASCII chunks on some Android
    // runtimes. Sending explicit UTF-8 bytes is deterministic for Japanese
    // and Vietnamese prompts.
    if (body != null) {
      final bodyBytes = utf8.encode(body);
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await utf8.decoder.bind(response).join();
    return _HttpResult(response.statusCode, responseBody);
  }
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
