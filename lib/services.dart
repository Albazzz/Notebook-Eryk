import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

/// Japanese OCR backed by Apple's Vision framework on iPadOS.
class AppleVisionJapaneseOcrService implements OcrService {
  static const _channel = MethodChannel('noteeryk/apple_vision_ocr');

  @override
  Future<String> recognizeImage(String imagePath) async {
    try {
      final text = await _channel.invokeMethod<String>(
        'recognizeJapaneseText',
        {'imagePath': imagePath},
      );
      final normalized = text?.trim() ?? '';
      if (normalized.isEmpty) {
        throw const FormatException('Vision OCR returned no text');
      }
      return normalized;
    } on PlatformException catch (error) {
      throw FormatException(error.message ?? 'Apple Vision OCR failed');
    }
  }
}

enum AiTask { translate, explain, solve, createWeakPoint, dictionary }

class OpenRouterService {
  static const _baseUrl = 'https://openrouter.ai/api/v1';
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  final Map<String, String> _completionCache = {};
  final Map<String, String> _visionOcrCache = {};
  final Map<String, Future<String>> _visionOcrInFlight = {};

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
    TranslationStyle translationStyle = TranslationStyle.balanced,
  }) async {
    final instruction = _promptFor(
      task,
      jlpt: jlpt,
      language: language,
      weaknessKind: weaknessKind,
      translationStyle: translationStyle,
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
      translationStyle.name,
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
        'max_tokens': switch (task) {
          AiTask.dictionary => 220,
          AiTask.explain => 1050,
          AiTask.translate => 1200,
          AiTask.solve => 900,
          AiTask.createWeakPoint => 1000,
        },
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

  /// Tách tất cả điểm yếu có trong một câu hỏi/câu trả lời thành các mục
  /// độc lập để người học duyệt từng mục trước khi lưu.
  Future<List<WeakPointDraft>> completeWeakPointDrafts({
    required String apiKey,
    required String modelId,
    required String text,
    required String jlpt,
    required String language,
    required Set<WeaknessKind> kinds,
  }) async {
    final selected = kinds.map((kind) => kind.name).join(', ');
    final instruction =
        '''
Bạn là giáo viên tiếng Nhật. Hãy phân tích đúng nội dung người học đã khoanh,
có thể gồm câu hỏi, các lựa chọn và đáp án. Chỉ tạo điểm yếu thuộc các loại
được yêu cầu: $selected. Nếu câu hỏi hỏi về một từ hoặc kanji, hãy lấy chính
từ/kanji xuất hiện trong câu hỏi hoặc đáp án và giải thích nghĩa trong đúng
ngữ cảnh đó. Bỏ qua các nét ghi chú hoặc chữ rác rời rạc nằm ngoài đoạn chính.
Nếu OCR sai hoặc thiếu 1–2 chữ nhưng ngữ cảnh đủ rõ, hãy phục dựng phương án hợp
lý nhất và ghi câu đã phục dựng cùng phần còn chưa chắc vào warning. Không âm
thầm sửa OCR và không lấy thêm nội dung ngoài vùng chọn.
Nếu đầu vào đã có dòng "Lưu ý OCR:", đó là metadata: dùng nó để kiểm tra và ghi
warning, không coi là một phần của câu tiếng Nhật.
Một câu có nhiều mẫu ngữ pháp hoặc nhiều từ đáng học thì tạo nhiều item riêng.
Với grammar: title chỉ là mẫu ngữ pháp (ví dụ のに), meaning là nghĩa thật ngắn;
conjugation và examples chứa phần học chi tiết. Nếu có mẫu dễ nhầm trong chính
đề hoặc thường gặp ở cùng trình độ, reminder so sánh khác biệt trong một câu.
Với vocabulary: title là từ khóa trong câu, có reading, meaning, hanViet nếu
chắc chắn và sourceSentence là câu chứa từ đó. meaning chỉ ghi nghĩa ngắn gọn.
Với kanji: title là chữ kanji, có reading, meaning và sourceSentence.
Trả về DUY NHẤT JSON object: {
  "items": [
    {
      "title":"...", "kind":"grammar|vocabulary|kanji|reading|other",
      "meaning":"...", "reading":"", "hanViet":"", "conjugation":"",
      "examples":[], "sourceSentence":"", "reminder":"", "note":"",
      "tags":["$jlpt"]
    }
  ],
  "warning":""
}
Ngôn ngữ trả lời: $language. Trình độ: $jlpt.
''';
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) throw ArgumentError('Chưa chọn model AI');
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
        'temperature': 0.15,
        'max_tokens': 1400,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Yêu cầu AI tạo điểm yếu thất bại (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('AI không trả về bản nháp điểm yếu');
    }
    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>;
    final raw = message['content'] as String? ?? '';
    final object = _decodeJsonObject(raw);
    if (object == null) {
      throw const FormatException('AI trả về dữ liệu điểm yếu không hợp lệ');
    }
    final items = object['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map>()
        .map((item) => WeakPointDraft.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.title.isNotEmpty && item.content.isNotEmpty)
        .where((item) => kinds.contains(item.kind))
        .toList(growable: false);
  }

  void dispose() => _client.close(force: true);

  /// Optional paid OCR path. The editor defaults to on-device Apple Vision;
  /// this is only used when the user explicitly enables AI image recognition.
  Future<String> recognizeImageWithAi({
    required String apiKey,
    required String modelId,
    required String imagePath,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) {
      throw ArgumentError('Chưa chọn model nhận diện ảnh');
    }
    final cacheKey =
        '$normalizedModelId|${bytes.length}|${_byteFingerprint(bytes)}';
    final cached = _visionOcrCache[cacheKey];
    if (cached != null) return cached;
    final running = _visionOcrInFlight[cacheKey];
    if (running != null) return running;
    final operation = _recognizeImageBytesWithAi(
      apiKey: apiKey,
      modelId: normalizedModelId,
      bytes: bytes,
    );
    _visionOcrInFlight[cacheKey] = operation;
    try {
      final result = await operation;
      if (_visionOcrCache.length >= 30) {
        _visionOcrCache.remove(_visionOcrCache.keys.first);
      }
      _visionOcrCache[cacheKey] = result;
      return result;
    } finally {
      _visionOcrInFlight.remove(cacheKey);
    }
  }

  Future<String> _recognizeImageBytesWithAi({
    required String apiKey,
    required String modelId,
    required List<int> bytes,
  }) async {
    final body = jsonEncode({
      'model': modelId,
      'messages': [
        {
          'role': 'system',
          'content':
              'Bạn là OCR tiếng Nhật. Đọc đoạn nội dung chính, giữ nguyên kanji/kana và xuống dòng; bỏ qua nét viết tay, số trang hoặc chữ rác rời rạc ở ngoài đoạn chính. Nếu chỉ thiếu hoặc sai 1–2 chữ và ngữ cảnh đủ rõ, phục dựng phương án hợp lý nhất rồi ghi rõ câu đã phục dựng và phần chưa chắc trong warning. Không âm thầm đoán phần bị cắt lớn. Trả về DUY NHẤT JSON object dạng {"text":"...","warning":""}.',
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
      // A full reading passage can easily exceed 220 tokens once JSON
      // escaping and an uncertainty note are included.
      'max_tokens': 1400,
    });
    late _HttpResult response;
    for (var attempt = 0; attempt < 2; attempt++) {
      response = await _request(
        'POST',
        '/chat/completions',
        apiKey,
        body: body,
      );
      if (response.statusCode != 429 || attempt == 1) break;
      await Future<void>.delayed(
        response.retryAfter ?? const Duration(seconds: 2),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 429) {
        throw const HttpException(
          'Model nhận diện ảnh đang giới hạn lượt (429)',
        );
      }
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
      final data = _decodeJsonObject(raw);
      if (data == null) throw const FormatException('OCR không đúng JSON');
      final text = (data['text'] as String? ?? '').trim();
      if (text.isEmpty) throw const FormatException('OCR trống');
      final warning = (data['warning'] as String? ?? '').trim();
      return warning.isEmpty ? text : '$text\n\nLưu ý OCR: $warning';
    } catch (_) {
      return _cleanAiText(raw);
    }
  }

  int _byteFingerprint(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash;
  }

  String _promptFor(
    AiTask task, {
    required String jlpt,
    required String language,
    String? weaknessKind,
    required TranslationStyle translationStyle,
  }) {
    const shared = '''
Bạn là giáo viên tiếng Nhật chính xác và súc tích. Chỉ phân tích nội dung người dùng đã chủ động khoanh. Bỏ qua note viết tay, số trang hoặc chữ rác rời rạc không thuộc đoạn chính. Nếu OCR sai hoặc thiếu 1–2 chữ nhưng ngữ cảnh đủ rõ, hãy phục dựng cả cụm/câu hợp lý nhất để hoàn thành nhiệm vụ; trong warning bắt buộc ghi "Đã phục dựng: ..." và nêu phần còn chưa chắc. Nếu đầu vào đã có dòng "Lưu ý OCR:", đó là metadata: đưa thông tin cần thiết vào warning, không dịch hoặc phân tích nó như nội dung tiếng Nhật. Không âm thầm sửa OCR và không suy đoán phần bị mất lớn. Không trò chuyện, không chào hỏi, không dùng Markdown và không thêm lời dẫn. Trả về DUY NHẤT một JSON object hợp lệ, không đặt trong code fence.''';
    final translationInstruction = switch (translationStyle) {
      TranslationStyle.literal =>
        'Phong cách: sát nghĩa. Bám sát từ ngữ, quan hệ ngữ pháp và trật tự câu gốc tối đa; không lược ý.',
      TranslationStyle.balanced =>
        'Phong cách: tự nhiên vừa phải. Giữ đầy đủ ý và sắc thái, chỉ điều chỉnh cấu trúc khi cần để dễ đọc.',
      TranslationStyle.fluent =>
        'Phong cách: mượt mà. Ưu tiên cách diễn đạt tự nhiên trong ngôn ngữ đích, được đổi trật tự nhưng không thêm hoặc bỏ ý.',
    };
    final taskPrompt = switch (task) {
      AiTask.translate =>
        '''
Nhiệm vụ: dịch nguyên văn sang $language cho người học $jlpt.
Schema bắt buộc: {"translation":"...","nuance":"...","warning":""}.
Giữ tên riêng; nuance tối đa 1 câu. $translationInstruction''',
      AiTask.explain =>
        '''
Nhiệm vụ: giải thích tiếng Nhật bằng $language ở độ khó phù hợp $jlpt.
Schema bắt buộc: {"meaning":"...","structures":[{"pattern":"...","meaning":"...","usage":"..."}],"segments":[{"japanese":"...","meaning":"..."}],"choiceAnalysis":[{"label":"A","correct":false,"reason":"..."}],"warning":""}.
Chỉ chọn tối đa 3 cấu trúc chính và tối đa 6 đoạn tách câu.
Với một câu hoàn chỉnh, meaning, structures và segments đều bắt buộc có nội dung; không được chỉ trả meaning. Mỗi cấu trúc phải có pattern, meaning và usage. Mỗi đoạn phải giữ nguyên japanese rồi mới giải nghĩa.
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
Nếu là grammar, title chỉ ghi mẫu ngữ pháp, meaning thật ngắn; conjugation và examples chứa chi tiết. reminder so sánh ngắn với mẫu dễ nhầm nếu có.
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
    final data = _decodeJsonObject(raw);
    if (data == null) return _cleanAiText(raw);
    try {
      final warning = _displayText(data['warning']);
      final suffix = warning.isEmpty ? '' : '\n\nLưu ý OCR: $warning';
      return switch (task) {
        AiTask.translate =>
          '${_displayText(data['translation'])}${_optionalLine('Sắc thái', data['nuance'])}$suffix',
        AiTask.explain => _formatExplanation(data) + suffix,
        AiTask.solve => _formatSolution(data) + suffix,
        AiTask.createWeakPoint =>
          '${_displayText(data['title'])}\n\nNghĩa\n${_displayText(data['meaning'] ?? data['content'])}\n\nCách đọc\n${_displayText(data['reading'])}\n\nHán Việt\n${_displayText(data['hanViet'])}\n\nCách chia\n${_displayText(data['conjugation'])}\n\nVí dụ\n${_displayText((data['examples'] as List<dynamic>? ?? const []).join('\n'))}\n\nĐiểm cần nhớ\n${_displayText(data['reminder'])}\n\nGhi chú\n${_displayText(data['note'])}$suffix',
        AiTask.dictionary =>
          '${_displayText(data['word'])}${_optionalLine('Cách đọc', data['reading'])}\n\nNghĩa\n${_displayText(data['meaning'])}${_optionalLine('Từ loại', data['partOfSpeech'])}${_optionalLine('JLPT', data['jlpt'])}${_optionalLine('Hán Việt', data['hanViet'])}${_optionalLine('Ví dụ', data['example'])}${_optionalLine('Dịch ví dụ', data['exampleMeaning'])}$suffix',
      };
    } catch (_) {
      // Keep the result useful when a selected model ignores the JSON contract.
      return _cleanAiText(raw);
    }
  }

  @visibleForTesting
  String formatStructuredResultForTesting(AiTask task, String raw) =>
      _formatStructuredResult(task, raw);

  /// Models occasionally wrap the required object in prose or a markdown
  /// code fence. Find and decode the first balanced JSON object so the user
  /// never sees the transport/schema payload in the result card.
  Map<String, dynamic>? _decodeJsonObject(String raw) {
    final candidates = <String>{
      raw.trim(),
      _repairJsonControlCharacters(_normalizeJsonPunctuation(raw.trim())),
    };
    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    final source = candidates.last;

    for (var start = 0; start < source.length; start++) {
      if (source.codeUnitAt(start) != 0x7b) continue; // {
      var depth = 0;
      var quoted = false;
      var escaped = false;
      for (var index = start; index < source.length; index++) {
        final code = source.codeUnitAt(index);
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (code == 0x5c) {
            escaped = true;
          } else if (code == 0x22) {
            quoted = false;
          }
          continue;
        }
        if (code == 0x22) {
          quoted = true;
        } else if (code == 0x7b) {
          depth++;
        } else if (code == 0x7d) {
          depth--;
          if (depth == 0) {
            try {
              final decoded = jsonDecode(source.substring(start, index + 1));
              if (decoded is Map) return Map<String, dynamic>.from(decoded);
            } catch (_) {}
            break;
          }
        }
      }
    }
    return null;
  }

  String _cleanAiText(String raw) {
    var text = raw.trim();
    text = text.replaceFirst(
      RegExp(r'^```(?:json|text)?\s*', caseSensitive: false),
      '',
    );
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
    final data = _decodeJsonObject(text);
    if (data == null) {
      final normalized = _displayText(_normalizeJsonPunctuation(text));
      if (!RegExp(r'^\s*\{').hasMatch(normalized) ||
          !normalized.contains(':')) {
        return normalized;
      }
      // Salvage readable values from a truncated JSON-like reply, but never
      // leak transport keys such as {"translation": into the result card.
      final values = RegExp(r':\s*"(.*?)(?="\s*[,}]|$)', dotAll: true)
          .allMatches(normalized)
          .map((match) => _displayText(match.group(1)))
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      return values.isEmpty
          ? 'AI trả về kết quả chưa hoàn chỉnh. Hãy thử lại.'
          : values.join('\n\n');
    }
    final readable = data.values
        .whereType<String>()
        .map(_displayText)
        .where((value) => value.isNotEmpty)
        .join('\n\n');
    return readable.isEmpty ? _displayText(text) : readable;
  }

  String _normalizeJsonPunctuation(String value) => value
      .replaceAll('\u201c', '"')
      .replaceAll('\u201d', '"')
      .replaceAll('\u201e', '"')
      .replaceAll('\ufeff', '');

  String _repairJsonControlCharacters(String value) {
    final output = StringBuffer();
    var quoted = false;
    var escaped = false;
    for (final codePoint in value.runes) {
      final character = String.fromCharCode(codePoint);
      if (quoted && (character == '\n' || character == '\r')) {
        output.write(character == '\n' ? r'\n' : r'\r');
        continue;
      }
      output.write(character);
      if (escaped) {
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else if (character == '"') {
        quoted = !quoted;
      }
    }
    return output.toString().replaceAllMapped(
      RegExp(r',\s*([}\]])'),
      (match) => match.group(1)!,
    );
  }

  String _displayText(Object? value) {
    var text = value?.toString().trim() ?? '';
    // Some models double-escape line breaks inside an otherwise valid JSON
    // response. Flutter renders those backslashes literally unless decoded.
    text = text
        .replaceAll(r'\r\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\n');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _formatExplanation(Map<String, dynamic> data) {
    final meaning = _firstText(data, const [
      'meaning',
      'summary',
      'overallMeaning',
      'explanation',
    ]);
    final buffer = StringBuffer('Nghĩa\n$meaning');
    final structures = _firstItems(data, const [
      'structures',
      'grammar',
      'grammarPoints',
      'patterns',
    ]);
    if (structures.isNotEmpty) buffer.write('\n\nCấu trúc chính');
    for (final rawItem in structures) {
      if (rawItem is! Map) {
        final text = _displayText(rawItem);
        if (text.isNotEmpty) buffer.write('\n$text');
        continue;
      }
      final item = Map<String, dynamic>.from(rawItem);
      final pattern = _firstText(item, const ['pattern', 'form', 'grammar']);
      final itemMeaning = _firstText(item, const ['meaning', 'explanation']);
      final heading = [
        pattern,
        itemMeaning,
      ].where((value) => value.isNotEmpty).join(' — ');
      if (heading.isNotEmpty) buffer.write('\n$heading');
      final usage = _firstText(item, const ['usage', 'use', 'conjugation']);
      if (usage.isNotEmpty) buffer.write('\n$usage');
    }
    final segments = _firstItems(data, const [
      'segments',
      'breakdown',
      'sentenceBreakdown',
      'parts',
    ]);
    if (segments.isNotEmpty) buffer.write('\n\nTách câu');
    for (final rawItem in segments) {
      if (rawItem is! Map) {
        final text = _displayText(rawItem);
        if (text.isNotEmpty) buffer.write('\n$text');
        continue;
      }
      final item = Map<String, dynamic>.from(rawItem);
      final japanese = _firstText(item, const ['japanese', 'text', 'segment']);
      final itemMeaning = _firstText(item, const [
        'meaning',
        'translation',
        'explanation',
      ]);
      final line = [
        japanese,
        itemMeaning,
      ].where((value) => value.isNotEmpty).join(' → ');
      if (line.isNotEmpty) buffer.write('\n$line');
    }
    final choices = _firstItems(data, const [
      'choiceAnalysis',
      'choices',
      'options',
      'answers',
    ]);
    if (choices.isNotEmpty) {
      final correctLabels = choices
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => _isTrue(item['correct']))
          .map((item) => _firstText(item, const ['label', 'option', 'answer']))
          .where((label) => label.isNotEmpty)
          .join(', ');
      if (correctLabels.isNotEmpty) {
        buffer.write('\n\nĐáp án đúng: $correctLabels');
      }
      buffer.write('\nGiải thích đơn giản từng lựa chọn:');
    }
    for (final rawItem in choices) {
      if (rawItem is! Map) {
        final text = _displayText(rawItem);
        if (text.isNotEmpty) buffer.write('\n$text');
        continue;
      }
      final item = Map<String, dynamic>.from(rawItem);
      final label = _firstText(item, const ['label', 'option', 'answer']);
      final correct = _isTrue(item['correct']);
      final reason = _firstText(item, const [
        'reason',
        'explanation',
        'meaning',
      ]);
      buffer.write('\n$label${correct ? ' ✓' : ' ✗'}: $reason');
    }
    if (structures.isEmpty && segments.isEmpty && choices.isEmpty) {
      buffer.write(
        '\n\nPhân tích\nAI chưa trả đủ phần cấu trúc và tách câu; kết quả trên mới chỉ có nghĩa tổng quát.',
      );
    }
    return buffer.toString();
  }

  String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return _displayText(value);
      }
      if (value is num || value is bool) return value.toString();
    }
    return '';
  }

  List<dynamic> _firstItems(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is List && value.isNotEmpty) return value;
      if (value is Map) return [value];
      if (value is String && value.trim().isNotEmpty) {
        return [_displayText(value)];
      }
    }
    return const [];
  }

  bool _isTrue(Object? value) =>
      value == true || value?.toString().toLowerCase() == 'true';

  String _formatSolution(Map<String, dynamic> data) {
    final buffer = StringBuffer(
      'Đáp án\n${_displayText(data['answer'])}\n\nVì sao?\n${_displayText(data['reason'])}',
    );
    final choices = data['choices'] as List<dynamic>? ?? const [];
    if (choices.isNotEmpty) buffer.write('\n\nPhân tích lựa chọn');
    for (final rawItem in choices) {
      final item = rawItem as Map<String, dynamic>;
      buffer.write(
        '\n${_displayText(item['label'])}${item['correct'] == true ? ' ✓' : ''}: ${_displayText(item['reason'])}',
      );
    }
    return buffer.toString();
  }

  String _optionalLine(String label, Object? value) {
    final text = _displayText(value);
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
    final retryAfter = _retryAfter(response.headers.value('retry-after'));
    final responseBody = await utf8.decoder.bind(response).join();
    return _HttpResult(response.statusCode, responseBody, retryAfter);
  }

  Duration? _retryAfter(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final seconds = int.tryParse(value.trim());
    Duration? duration;
    if (seconds != null) {
      duration = Duration(seconds: seconds);
    } else {
      try {
        duration = HttpDate.parse(
          value.trim(),
        ).difference(DateTime.now().toUtc());
      } catch (_) {}
    }
    if (duration == null || duration.isNegative) return null;
    if (duration < const Duration(milliseconds: 500)) {
      duration = const Duration(milliseconds: 500);
    }
    if (duration > const Duration(seconds: 5)) {
      duration = const Duration(seconds: 5);
    }
    return duration;
  }
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body, this.retryAfter);
  final int statusCode;
  final String body;
  final Duration? retryAfter;
}
