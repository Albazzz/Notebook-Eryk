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

  /// Tra đúng từ, không tính gợi ý gần nghĩa (nhanh, dùng để kiểm chứng
  /// cách đọc/Hán Việt do AI trả về).
  Future<DictionaryEntry?> lookupBasic(String text);
}

const _iRowToURow = {
  'い': 'う',
  'き': 'く',
  'ぎ': 'ぐ',
  'し': 'す',
  'ち': 'つ',
  'に': 'ぬ',
  'び': 'ぶ',
  'み': 'む',
  'り': 'る',
};

/// Thể từ điển có thể có của một động từ ở thể ます, theo thứ tự nên thử:
/// 書きます → 書く, 書きる; 話します → 話す, 話する, 話; 食べます → 食べる.
/// Không biết nhóm động từ nên trả về mọi khả năng để từ điển quyết định;
/// dạng godan đứng trước để 話します không bị khớp nhầm danh từ 話.
List<String> dictionaryFormCandidates(String word) {
  final value = word.trim();
  if (!value.endsWith('ます') || value.length < 3) return const [];
  final stem = value.substring(0, value.length - 2);
  if (stem == 'き' || stem == '来') return ['$stemる', 'くる'];
  if (stem == 'し') return const ['する'];
  // One-kana stems are almost always ichidan (います, みます, ねます).
  if (stem.length == 1) return ['$stemる'];
  final candidates = <String>[];
  final head = stem.substring(0, stem.length - 1);
  final godan = _iRowToURow[stem.substring(stem.length - 1)];
  if (godan != null) candidates.add('$head$godan');
  if (stem.endsWith('し')) {
    candidates
      ..add('$headする')
      ..add(head);
  }
  candidates.add('$stemる');
  return candidates.toSet().toList(growable: false);
}

/// Cách đọc AI ghi cho tiêu đề thể ます (たべます) khớp với cách đọc thể từ
/// điển (たべる) thì không phải là sai lệch cần cảnh báo.
bool readingsMatch(String aiReading, String dictionaryReading) {
  String kana(String value) => value.replaceAll(RegExp(r'[\s・.]'), '');
  final ai = kana(aiReading);
  final dictionary = kana(dictionaryReading);
  return ai == dictionary || dictionaryFormCandidates(ai).contains(dictionary);
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
  Future<DictionaryEntry?> lookupBasic(String text) async {
    final value = text.trim().replaceAll(RegExp(r'^[〜~～]+'), '');
    if (value.isEmpty) return null;
    final db = await _database;
    // Weak-point titles keep verbs in ます form while the dictionary mostly
    // stores the dictionary form, so try the exact title first and then its
    // plain-form candidates.
    for (final candidate in [value, ...dictionaryFormCandidates(value)]) {
      // Prefer a kanji match: a kana-only title such as かける is ambiguous.
      for (final column in const ['kanji', 'hiragana']) {
        final rows = await db.query(
          'japanese_dictionary',
          where: '$column = ?',
          whereArgs: [candidate],
          limit: 1,
        );
        if (rows.isNotEmpty) return _entryFromRow(rows.first);
      }
    }
    return null;
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

class _StructuredOutputSpec {
  const _StructuredOutputSpec(this.name, this.schema);

  final String name;
  final Map<String, dynamic> schema;
}

/// Chiến lược giải cho từng dạng đề JLPT, dùng chung cho Kiểm tra nhanh,
/// Giải thích và Điểm yếu để mọi luồng AI xử lý đề giống nhau.
const jlptQuestionTypeGuide = '''
Nhận dạng dạng đề JLPT (questionType) của từng câu rồi giải theo đúng chiến lược:
- 漢字読み: chọn cách đọc của từ gạch chân. Kiểm tra âm On/Kun, trường âm (う/ー), âm ngắt っ, âm đục/bán đục, âm ghép ゃゅょ — đây là các bẫy chính. Điểm yếu là chính từ đó với cách đọc chuẩn.
- 表記: chọn kanji đúng cho từ viết bằng hiragana. So sánh các chữ đồng âm hoặc giống hình; dùng Hán Việt để phân biệt nghĩa.
- 語形成: tiền tố/hậu tố (再〜, 非〜, 未〜, 〜化, 〜的, 〜感, 〜性...). Giải thích quy tắc ghép từ.
- 文脈規定: chọn từ hợp ngữ cảnh. Dựa vào cụm từ đi kèm (collocation), sắc thái và từ loại; nêu vì sao từng từ nhiễu không hợp.
- 言い換え類義: chọn từ/cụm gần nghĩa nhất với phần gạch chân; so sánh sắc thái. Điểm yếu ghi cặp từ đồng nghĩa.
- 用法: chọn câu dùng từ đúng. Với từng câu sai nêu chỗ sai (sai collocation, sắc thái hoặc từ loại) và từ lẽ ra phải dùng.
- 文法形式の判断: chọn mẫu ngữ pháp điền vào （　）. Xét cách nối (接続) với từ đứng trước, chủ thể, sắc thái và văn phong; so sánh với mẫu dễ nhầm.
- 文の組み立て (★): sắp xếp 4 mảnh vào ＿＿＿. Ghép thành câu hoàn chỉnh trước dựa vào cách nối ngữ pháp và trợ từ; đáp án là mảnh nằm ở vị trí ★. Bắt buộc ghi thứ tự đúng và cả câu hoàn chỉnh.
- 文章の文法: điền chỗ trống trong đoạn văn. Xét mạch văn trước–sau: liên từ, từ chỉ thị こ/そ/あ, bị động/sai khiến, cách kết câu (のだ, わけだ...).
- 内容理解 (短文/中文/長文): tìm câu làm căn cứ (根拠) trong bài và trích nguyên văn; lựa chọn sai thường diễn đạt lại sai, nói quá mức hoặc không được nhắc tới.
- 統合理解・主張理解: so sánh quan điểm A/B hoặc chủ trương của tác giả; chú ý câu cuối đoạn và các từ しかし, つまり, むしろ.
- 情報検索: đối chiếu từng điều kiện trong câu hỏi với bảng/thông báo rồi loại dần.
- その他: câu không thuộc các dạng trên.''';

/// Dạng chuẩn của tiêu đề điểm yếu theo từ loại, dùng chung khi tạo mới và
/// khi chuẩn hóa để hai luồng cho ra cùng một tiêu đề (và so trùng được).
const weakPointTitleGuide = '''
Dạng chuẩn của title theo từ loại (không chép nguyên dạng đã chia trong đề):
- Động từ: thể ます (食べます, 書きます, 勉強します, 来ます).
- Danh từ, phó từ, liên từ, cụm cố định: dạng đứng đơn (勉強, ゆっくり, しかし).
- Tính từ い: dạng kết thúc bằng い (高い); tính từ な: bỏ な (静か).
- kanji: chỉ chữ kanji; grammar: mẫu ngữ pháp có 〜 (〜わけではない).
reading là cách đọc của đúng title đã chuẩn hóa (食べます → たべます).''';

bool isJapaneseLanguage(String language) {
  final value = language.trim().toLowerCase();
  return value == '日本語' || value == 'japanese' || value == 'tiếng nhật';
}

/// Đề bài toàn tiếng Nhật kéo model trả lời luôn bằng tiếng Nhật, nên quy tắc
/// ngôn ngữ được nhắc ở cả đầu và cuối prompt.
String answerLanguageRule(String language) {
  if (isJapaneseLanguage(language)) return 'Ngôn ngữ trả lời: 日本語.';
  return 'QUY TẮC NGÔN NGỮ (bắt buộc): mọi lời giải thích, lý do, nghĩa, chỗ dễ '
      'nhầm, mẹo nhớ và cảnh báo phải viết bằng $language. Chỉ giữ tiếng Nhật '
      'khi chép nguyên văn đề, nội dung lựa chọn, câu ví dụ hoặc trích đúng '
      'từ/mẫu đang nói tới. Không viết câu giải thích bằng tiếng Nhật.';
}

/// Câu "giải thích" gần như toàn kana/kanji, không có chữ Latin: dấu hiệu
/// model đã trả lời bằng tiếng Nhật thay vì ngôn ngữ được yêu cầu.
bool looksJapaneseOnly(String text) {
  var japanese = 0;
  var latin = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x3040 && rune <= 0x30ff) ||
        (rune >= 0x4e00 && rune <= 0x9fff)) {
      japanese++;
    } else if ((rune >= 0x41 && rune <= 0x5a) ||
        (rune >= 0x61 && rune <= 0x7a) ||
        (rune >= 0xc0 && rune <= 0x1ef9)) {
      latin++;
    }
  }
  return japanese >= 8 && latin < (japanese + latin) * .15;
}

/// Quy tắc tách đề khi vùng khoanh chứa nhiều câu hỏi.
const multiQuestionGuide = '''
Vùng khoanh có thể chứa NHIỀU câu hỏi (đánh số 1, 2, 問1, (1), ①...). Tách và xử lý TỪNG câu riêng theo đúng thứ tự xuất hiện; không trộn lựa chọn hay ngữ cảnh giữa các câu. Số của lựa chọn (1 2 3 4) khác số câu hỏi: nhóm 4 phương án ngắn liên tiếp là lựa chọn của câu ngay phía trên. Câu hỏi đọc hiểu dùng chung một bài đọc thì mỗi câu vẫn là một mục riêng. Nếu một câu bị cắt mất lựa chọn thì vẫn xử lý phần còn lại và ghi vào warning.''';

class OpenRouterService {
  static const _baseUrl = 'https://openrouter.ai/api/v1';
  static const _completionTimeout = Duration(seconds: 150);
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  final Map<String, String> _completionCache = {};
  final Map<String, String> _visionOcrCache = {};
  final Map<String, Future<String>> _visionOcrInFlight = {};

  /// Mức suy luận áp dụng cho các tác vụ văn bản. AppState đồng bộ giá trị
  /// này từ Cài đặt.
  AiReasoningEffort reasoningEffort = AiReasoningEffort.high;

  /// Model/provider đã từ chối tham số `reasoning`; lần sau gửi không kèm.
  final Set<String> _reasoningUnsupportedModels = {};

  /// Model không nhận `temperature` (GPT-5/6, Claude 5...). Với
  /// require_parameters, gửi kèm tham số này làm OpenRouter không tìm được
  /// provider nào và trả lỗi; model lạ được phát hiện ở lần gọi đầu.
  final Set<String> _temperatureUnsupportedModels = {};

  bool _acceptsTemperature(String modelId) {
    final id = modelId.toLowerCase();
    if (_temperatureUnsupportedModels.contains(modelId)) return false;
    return !id.contains('gpt-5') &&
        !id.contains('gpt-6') &&
        !RegExp(r'claude-(haiku|sonnet|opus)-5').hasMatch(id);
  }

  /// Ngân sách token dành riêng cho phần suy luận ẩn. Phần này được cộng vào
  /// max_tokens để suy luận không ăn mất chỗ của JSON kết quả (nguyên nhân
  /// JSON bị cắt và phải gọi lại lần hai).
  int _reasoningBudget(AiReasoningEffort effort) => switch (effort) {
    AiReasoningEffort.low => 1500,
    AiReasoningEffort.medium => 5000,
    AiReasoningEffort.high => 12000,
  };

  /// Mức suy luận của người dùng nhưng không vượt [cap]: tác vụ ngắn như dịch
  /// hay giải thích không cần suy luận sâu và sẽ chậm đi hàng chục giây.
  AiReasoningEffort _cappedEffort(AiReasoningEffort cap) =>
      reasoningEffort.index <= cap.index ? reasoningEffort : cap;

  /// null: không gửi tham số reasoning (nhanh nhất).
  AiReasoningEffort? _effortFor(AiTask task) => switch (task) {
    AiTask.translate || AiTask.dictionary => null,
    AiTask.explain => _cappedEffort(AiReasoningEffort.low),
    AiTask.createWeakPoint => _cappedEffort(AiReasoningEffort.medium),
    AiTask.solve => reasoningEffort,
  };

  Map<String, dynamic> _structuredRequestOptions(
    _StructuredOutputSpec spec, {
    bool preferLatency = false,
  }) => {
    'stream': false,
    'provider': {
      'require_parameters': true,
      // Route short interactive tasks to the provider answering fastest.
      if (preferLatency) 'sort': 'latency',
    },
    'response_format': {
      'type': 'json_schema',
      'json_schema': {'name': spec.name, 'strict': true, 'schema': spec.schema},
    },
    'plugins': [
      {'id': 'response-healing'},
    ],
  };

  Map<String, dynamic> _chatCompletionPayload({
    required String modelId,
    required String instruction,
    required Object userContent,
    required double temperature,
    required int maxTokens,
    required _StructuredOutputSpec spec,
    AiReasoningEffort? effort,
    bool preferLatency = false,
  }) {
    // GPT-5/Luna endpoints expose max_completion_tokens and may reject
    // temperature. Omitting that unsupported parameter lets OpenRouter route
    // the request to a provider that can enforce the schema.
    final gpt5Family = modelId.toLowerCase().contains('gpt-5');
    final reasoning = effort != null;
    final tokenLimit = reasoning
        ? maxTokens + _reasoningBudget(effort)
        : maxTokens;
    return {
      'model': modelId,
      'messages': [
        {'role': 'system', 'content': instruction},
        {'role': 'user', 'content': userContent},
      ],
      // Reasoning models ignore/refuse temperature; sampling only matters
      // for non-reasoning requests.
      if (!reasoning && _acceptsTemperature(modelId))
        'temperature': temperature,
      if (gpt5Family) 'max_completion_tokens': tokenLimit,
      if (!gpt5Family) 'max_tokens': tokenLimit,
      // The hidden reasoning text is never shown, so exclude it from the
      // response to save bandwidth and parsing time.
      if (reasoning) 'reasoning': {'effort': effort.name, 'exclude': true},
      ..._structuredRequestOptions(spec, preferLatency: preferLatency),
    };
  }

  @visibleForTesting
  Map<String, dynamic> chatPayloadForTesting({
    required String modelId,
    bool reasoning = true,
  }) => _chatCompletionPayload(
    modelId: modelId,
    instruction: 'test',
    userContent: 'test',
    temperature: .2,
    maxTokens: 1000,
    spec: _quickCheckSpec,
    effort: reasoning ? reasoningEffort : null,
  );

  bool _isReasoningRejected(_HttpResult response) {
    if (response.statusCode < 400 || response.statusCode >= 500) return false;
    final detail = response.body.toLowerCase();
    return detail.contains('reasoning') || _isParameterRejected(response);
  }

  bool _isParameterRejected(_HttpResult response) {
    if (response.statusCode < 400 || response.statusCode >= 500) return false;
    final detail = response.body.toLowerCase();
    return detail.contains('no endpoints found') ||
        detail.contains('require_parameters') ||
        detail.contains('temperature');
  }

  /// Every AI response must pass the same strict JSON Schema validation. A
  /// second request is allowed for transient malformed/truncated output, but
  /// it uses the strict contract again; plain-text fallback is deliberately
  /// forbidden so the UI can never receive an unvalidated object.
  Future<Map<String, dynamic>?> _requestValidatedObject({
    required String apiKey,
    required String modelId,
    required String instruction,
    required Object userContent,
    required double temperature,
    required int maxTokens,
    required _StructuredOutputSpec spec,
    required String operation,
    bool retryRateLimit = false,
    AiReasoningEffort? effort,
    bool preferLatency = false,
  }) async {
    var attempts = 0;
    var rateLimitRetries = 0;
    while (attempts < 2) {
      final attemptMaxTokens = attempts == 0
          ? maxTokens
          : (maxTokens * 3 ~/ 2).clamp(maxTokens, maxTokens + 1600);
      final reasoning =
          effort != null && !_reasoningUnsupportedModels.contains(modelId);
      final sentTemperature = !reasoning && _acceptsTemperature(modelId);
      final response = await _request(
        'POST',
        '/chat/completions',
        apiKey,
        timeout: _completionTimeout,
        body: jsonEncode(
          _chatCompletionPayload(
            modelId: modelId,
            instruction: instruction,
            userContent: userContent,
            temperature: temperature,
            maxTokens: attemptMaxTokens,
            spec: spec,
            effort: reasoning ? effort : null,
            preferLatency: preferLatency,
          ),
        ),
      );
      if (reasoning && _isReasoningRejected(response)) {
        // Non-reasoning models have no endpoint that accepts the parameter
        // while require_parameters is on. Remember it and resend without it;
        // this does not consume a schema attempt.
        _reasoningUnsupportedModels.add(modelId);
        continue;
      }
      if (sentTemperature && _isParameterRejected(response)) {
        // Same idea for sampling: resend once without temperature.
        _temperatureUnsupportedModels.add(modelId);
        continue;
      }
      if (response.statusCode == 429 && retryRateLimit) {
        if (rateLimitRetries == 0) {
          rateLimitRetries++;
          await Future<void>.delayed(
            response.retryAfter ?? const Duration(seconds: 2),
          );
          continue;
        }
        throw HttpException('$operation đang giới hạn lượt (429)');
      }
      _throwIfRequestFailed(response, operation: operation);
      final result = _validatedResponseObject(response.body, spec.schema);
      if (result != null) return result;
      attempts++;
    }
    return null;
  }

  @visibleForTesting
  Map<String, dynamic> structuredRequestOptionsForTesting(AiTask task) =>
      _structuredRequestOptions(_outputSpecFor(task));

  @visibleForTesting
  Map<String, dynamic> weakPointDraftRequestOptionsForTesting() =>
      _structuredRequestOptions(_weakPointDraftsSpec);

  @visibleForTesting
  Map<String, dynamic> ocrRequestOptionsForTesting() =>
      _structuredRequestOptions(_ocrSpec);

  Map<String, dynamic> _stringProperty(
    String description, {
    List<String>? values,
  }) => {'type': 'string', 'description': description, 'enum': ?values};

  Map<String, dynamic> _booleanProperty(String description) => {
    'type': 'boolean',
    'description': description,
  };

  Map<String, dynamic> _objectSchema(Map<String, dynamic> properties) => {
    'type': 'object',
    'properties': properties,
    'required': properties.keys.toList(growable: false),
    'additionalProperties': false,
  };

  Map<String, dynamic> _objectArrayProperty(
    String description,
    Map<String, dynamic> properties,
  ) => {
    'type': 'array',
    'description': description,
    'items': _objectSchema(properties),
  };

  _StructuredOutputSpec _outputSpecFor(AiTask task) => switch (task) {
    AiTask.translate => _StructuredOutputSpec(
      'translation_result',
      _objectSchema({
        'translation': _stringProperty(
          'Bản dịch đầy đủ, chính xác theo ngôn ngữ và phong cách được yêu cầu.',
        ),
        'nuance': _stringProperty(
          'Một câu ngắn về sắc thái đáng chú ý; để chuỗi rỗng nếu không có.',
        ),
        'warning': _stringProperty(
          'Cảnh báo về OCR hoặc phần đã phục dựng; để chuỗi rỗng nếu không có.',
        ),
      }),
    ),
    AiTask.explain => _StructuredOutputSpec(
      'explanation_result',
      _objectSchema({
        'meaning': _stringProperty('Nghĩa tổng quát của nội dung tiếng Nhật.'),
        'structures':
            _objectArrayProperty('Tối đa ba cấu trúc ngữ pháp chính.', {
              'pattern': _stringProperty('Mẫu hoặc cấu trúc ngữ pháp.'),
              'meaning': _stringProperty('Nghĩa ngắn của cấu trúc.'),
              'usage': _stringProperty('Cách dùng hoặc cách kết hợp.'),
            }),
        'segments': _objectArrayProperty(
          'Tối đa sáu đoạn dùng để tách và giải nghĩa câu.',
          {
            'japanese': _stringProperty('Đoạn tiếng Nhật nguyên văn.'),
            'meaning': _stringProperty('Nghĩa của đoạn bằng ngôn ngữ yêu cầu.'),
          },
        ),
        'questions': _objectArrayProperty(
          'Mỗi câu hỏi trắc nghiệm trong vùng chọn là một mục riêng; để mảng rỗng nếu không có câu hỏi.',
          {
            'label': _stringProperty('Số câu, ví dụ 1 hoặc 問3.'),
            'questionType': _questionTypeProperty(),
            'answer': _stringProperty('Đáp án đúng kèm nội dung lựa chọn.'),
            'choices': _objectArrayProperty('Phân tích từng lựa chọn.', {
              'label': _stringProperty('Nhãn lựa chọn, ví dụ 1 hoặc A.'),
              'correct': _booleanProperty(
                'Lựa chọn này có phải đáp án đúng không.',
              ),
              'reason': _stringProperty('Lý do ngắn vì sao đúng hoặc sai.'),
            }),
          },
        ),
        'warning': _stringProperty(
          'Cảnh báo về OCR hoặc phần đã phục dựng; để chuỗi rỗng nếu không có.',
        ),
      }),
    ),
    AiTask.solve => _quickCheckSpec,
    AiTask.createWeakPoint => _StructuredOutputSpec(
      'weak_point_result',
      _objectSchema(_weakPointItemProperties()),
    ),
    AiTask.dictionary => _StructuredOutputSpec(
      'dictionary_result',
      _objectSchema({
        'word': _stringProperty('Từ hoặc cụm từ tiếng Nhật cần tra.'),
        'reading': _stringProperty('Cách đọc bằng kana.'),
        'meaning': _stringProperty('Nghĩa ngắn gọn trong ngữ cảnh.'),
        'partOfSpeech': _stringProperty('Từ loại.'),
        'jlpt': _stringProperty('Trình độ JLPT nếu xác định được.'),
        'hanViet': _stringProperty('Hán Việt; để chuỗi rỗng nếu không có.'),
        'example': _stringProperty('Câu ví dụ tiếng Nhật ngắn.'),
        'exampleMeaning': _stringProperty('Nghĩa của câu ví dụ.'),
        'warning': _stringProperty(
          'Cảnh báo về OCR hoặc phần đã phục dựng; để chuỗi rỗng nếu không có.',
        ),
      }),
    ),
  };

  Map<String, dynamic> _questionTypeProperty() => _stringProperty(
    'Dạng đề JLPT của câu hỏi.',
    values: JlptQuestionType.values
        .map((type) => type.japanese)
        .toList(growable: false),
  );

  Map<String, dynamic> _kindProperty() => _stringProperty(
    'Loại điểm yếu.',
    values: WeaknessKind.values.map((kind) => kind.name).toList(),
  );

  /// Các trường của một điểm yếu. Không có `note`/`tags`: ghi chú là của
  /// người học, còn tag (JLPT, dạng đề) do app tự gắn.
  Map<String, dynamic> _weakPointItemProperties() => {
    'questionLabel': _stringProperty(
      'Số câu hỏi chứa điểm này, ví dụ 2 hoặc 問3; chuỗi rỗng nếu không phải đề.',
    ),
    'questionType': _questionTypeProperty(),
    'kind': _kindProperty(),
    'title': _stringProperty(
      'grammar: chỉ mẫu ngữ pháp (vd 〜わけではない); vocabulary: động từ ở thể ます (食べます), danh từ/phó từ/tính từ ở dạng đứng đơn (勉強, 高い, 静か); kanji: chữ kanji; reading/other: tên ngắn của kỹ năng hoặc bẫy.',
    ),
    'meaning': _stringProperty('Nghĩa ngắn gọn trong đúng ngữ cảnh của đề.'),
    'reading': _stringProperty(
      'Cách đọc bằng kana cho vocabulary/kanji; chuỗi rỗng với loại khác.',
    ),
    'hanViet': _stringProperty(
      'Âm Hán Việt nếu chắc chắn; chuỗi rỗng nếu không chắc hoặc không có kanji.',
    ),
    'conjugation': _stringProperty(
      'grammar: cách nối (接続), ví dụ V辞書形/Nの + わけではない; chuỗi rỗng với loại khác.',
    ),
    'examples': _objectArrayProperty(
      'Một đến hai ví dụ ngắn, tự nhiên, khác câu trong đề.',
      {
        'japanese': _stringProperty('Câu ví dụ tiếng Nhật.'),
        'meaning': _stringProperty('Nghĩa của câu ví dụ.'),
      },
    ),
    'sourceSentence': _stringProperty(
      'Câu trong đề chứa điểm này, chép nguyên văn.',
    ),
    'correctAnswer': _stringProperty(
      'Đáp án đúng của câu hỏi liên quan (nhãn + nội dung); chuỗi rỗng nếu không phải đề.',
    ),
    'mistake': _stringProperty(
      'Chỗ dễ sai: so sánh với lựa chọn nhiễu hoặc mẫu dễ nhầm và vì sao sai. Nếu biết người học chọn sai thì giải thích đúng lựa chọn đó.',
    ),
    'memoryTip': _stringProperty(
      'Một mẹo ghi nhớ ngắn; chuỗi rỗng nếu không có mẹo thật sự hữu ích.',
    ),
    'uncertain': _stringProperty(
      'Phần AI chưa chắc (OCR phục dựng, Hán Việt, cách đọc...); chuỗi rỗng nếu chắc chắn.',
    ),
  };

  _StructuredOutputSpec get _weakPointDraftsSpec => _StructuredOutputSpec(
    'weak_point_drafts',
    _objectSchema({
      'items': _objectArrayProperty(
        'Một mục độc lập cho mỗi điểm cần học trong vùng đã khoanh.',
        _weakPointItemProperties(),
      ),
      'warning': _stringProperty(
        'Cảnh báo chung về OCR hoặc phần đã phục dựng; để chuỗi rỗng nếu không có.',
      ),
    }),
  );

  _StructuredOutputSpec get _quickCheckSpec => _quickCheckSpecFor('');

  /// [language] được ghi thẳng vào mô tả các trường giải thích: model đọc
  /// schema sát hơn prompt, nên đây là chỗ giữ ngôn ngữ hiệu quả nhất.
  _StructuredOutputSpec _quickCheckSpecFor(String language) {
    final inLanguage = language.isEmpty || isJapaneseLanguage(language)
        ? ''
        : ' Viết bằng $language, không viết bằng tiếng Nhật.';
    return _StructuredOutputSpec(
      'quick_check_result',
      _objectSchema({
        'questions': _objectArrayProperty(
          'Mỗi câu hỏi là một mục riêng, đúng thứ tự trong đề.',
          {
            'label': _stringProperty('Số câu, ví dụ 1 hoặc 問3.'),
            'questionType': _questionTypeProperty(),
            'stem': _stringProperty(
              'Nội dung câu hỏi nguyên văn; rút gọn bài đọc dài thành câu hỏi chính.',
            ),
            'choices': _objectArrayProperty(
              'Các lựa chọn theo đúng thứ tự trong đề; mảng rỗng nếu là câu tự luận/điền từ.',
              {
                'label': _stringProperty(
                  'Nhãn lựa chọn như trong đề: 1, A, ア...',
                ),
                'text': _stringProperty('Nội dung lựa chọn.'),
                'correct': _booleanProperty(
                  'true cho đúng một lựa chọn là đáp án.',
                ),
                'reason': _stringProperty(
                  'Tối đa 1 câu: vì sao đúng, hoặc vì sao người chọn nó bị sai.$inLanguage',
                ),
              },
            ),
            'answer': _stringProperty('Đáp án đúng dạng chữ.'),
            'explanation': _stringProperty(
              'Giải thích ngắn (tối đa 2 câu) theo chiến lược của dạng đề; với 文の組み立て ghi thứ tự và câu hoàn chỉnh.$inLanguage',
            ),
            'point': _stringProperty(
              'Điểm kiến thức được kiểm tra: mẫu ngữ pháp, từ hoặc kỹ năng.',
            ),
            'kind': _kindProperty(),
          },
        ),
        'warning': _stringProperty(
          'Cảnh báo về OCR hoặc phần đã phục dựng; để chuỗi rỗng nếu không có.$inLanguage',
        ),
      }),
    );
  }

  @visibleForTesting
  Map<String, dynamic> quickCheckRequestOptionsForTesting() =>
      _structuredRequestOptions(_quickCheckSpec);

  _StructuredOutputSpec get _ocrSpec => _StructuredOutputSpec(
    'japanese_ocr_result',
    _objectSchema({
      'text': _stringProperty('Toàn bộ nội dung tiếng Nhật đã nhận dạng.'),
      'warning': _stringProperty(
        'Phần đã phục dựng hoặc chưa chắc chắn; để chuỗi rỗng nếu không có.',
      ),
    }),
  );

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
      reasoningEffort.name,
      text.trim(),
    ].join('|');
    final cached = _completionCache[cacheKey];
    if (cached != null) return cached;
    final spec = _outputSpecFor(task);
    final resultObject = await _requestValidatedObject(
      apiKey: apiKey,
      modelId: normalizedModelId,
      instruction: instruction,
      userContent: text,
      temperature: 0.25,
      // Dictionary responses are intentionally short; limiting output
      // reduces latency and leaves less room for speculative explanations.
      maxTokens: switch (task) {
        AiTask.dictionary => 220,
        AiTask.explain => 1800,
        AiTask.translate => 1200,
        AiTask.solve => 3200,
        AiTask.createWeakPoint => 1400,
      },
      spec: spec,
      operation: 'Yêu cầu AI',
      effort: _effortFor(task),
      preferLatency: task != AiTask.solve,
    );
    if (resultObject == null) {
      throw const FormatException(
        'AI trả về dữ liệu không đúng cấu trúc sau 2 lần thử',
      );
    }
    final formatted = _formatStructuredResult(task, jsonEncode(resultObject));
    // Keep the cache bounded; repeated OCR/AI taps then return instantly.
    if (_completionCache.length >= 60) {
      _completionCache.remove(_completionCache.keys.first);
    }
    _completionCache[cacheKey] = formatted;
    return formatted;
  }

  /// Tách tất cả điểm yếu có trong một câu hỏi/câu trả lời thành các mục
  /// độc lập để người học duyệt từng mục trước khi lưu. [kinds] rỗng hoặc null
  /// nghĩa là để AI tự phát hiện mọi loại. [learnerContext] mô tả người học đã
  /// chọn sai gì (từ Kiểm tra nhanh) để AI tập trung vào đúng chỗ nhầm.
  /// [focusTerms] là các cụm người học tự tô trên OCR: khi có, AI chỉ tạo
  /// điểm yếu cho đúng các cụm đó thay vì tự dò toàn bộ vùng.
  Future<({List<WeakPointDraft> items, String warning})>
  completeWeakPointDrafts({
    required String apiKey,
    required String modelId,
    required String text,
    required String jlpt,
    required String language,
    Set<WeaknessKind>? kinds,
    String learnerContext = '',
    List<String> focusTerms = const [],
  }) async {
    final focused = focusTerms.isNotEmpty;
    final kindRule = kinds == null || kinds.isEmpty
        ? 'Tự xác định loại (kind) phù hợp cho từng điểm.'
        : 'Chỉ tạo điểm yếu thuộc các loại: ${kinds.map((kind) => kind.name).join(', ')}.';
    final scopeRule = focused
        ? '''- Người học đã TỰ TÔ các cụm cần học (danh sách ở cuối đầu vào). Tạo đúng
  một mục cho mỗi cụm đã tô, theo đúng thứ tự; không thêm điểm nào khác.
  Cụm tô có thể là dạng đã chia, thiếu/thừa chữ do tô lệch: dựa vào câu chứa nó
  để xác định đúng từ/mẫu rồi đưa title về dạng chuẩn.'''
        : '''- Tối đa 8 mục; ưu tiên điểm quyết định đáp án và điểm dễ nhầm, bỏ qua từ
  quá cơ bản so với trình độ $jlpt.
- Một câu có nhiều mẫu ngữ pháp hoặc nhiều từ đáng học thì tạo nhiều mục riêng;
  không tạo hai mục trùng nhau.''';
    final instruction =
        '''
Bạn là giáo viên luyện thi JLPT. Người học khoanh một vùng trong vở/đề để lưu
"điểm yếu" ôn lại bằng flashcard. Phân tích đúng nội dung đã khoanh: có thể là
câu hỏi, các lựa chọn, đáp án hoặc một đoạn văn bất kỳ.
${answerLanguageRule(language)}
$multiQuestionGuide
$jlptQuestionTypeGuide
$weakPointTitleGuide
Quy tắc tạo điểm yếu:
- $kindRule
$scopeRule
- title phải ngắn gọn để làm mặt trước flashcard; meaning ngắn gọn đúng ngữ cảnh.
- grammar: conjugation ghi cách nối; examples là câu mới, khác câu trong đề.
- vocabulary/kanji: bắt buộc có reading; hanViet chỉ ghi khi chắc chắn.
- Với câu hỏi: correctAnswer là đáp án đúng; mistake giải thích lựa chọn nhiễu
  dễ bị chọn và vì sao sai (với 用法/言い換え nêu khác biệt sắc thái/collocation).
- reading (đọc hiểu): title là kỹ năng/bẫy (vd "Bẫy diễn đạt lại"), sourceSentence
  là câu căn cứ (根拠) trích nguyên văn.
- Không bịa: phần chưa chắc ghi vào uncertain. Không lấy nội dung ngoài vùng chọn.
Bỏ qua nét ghi chú hoặc chữ rác rời rạc ngoài đoạn chính. Nếu OCR sai/thiếu 1–2
chữ nhưng ngữ cảnh đủ rõ, phục dựng phương án hợp lý nhất và ghi vào warning.
Dòng "Lưu ý OCR:" trong đầu vào là metadata, không phải nội dung tiếng Nhật.
Nếu không có điểm phù hợp thì để items rỗng.
Trình độ: $jlpt. ${answerLanguageRule(language)}''';
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) throw ArgumentError('Chưa chọn model AI');
    final userContent = [
      text,
      if (learnerContext.trim().isNotEmpty)
        'Thông tin làm bài của người học:\n${learnerContext.trim()}',
      if (focused)
        'Các cụm người học đã tô:\n${focusTerms.indexed.map((entry) => '${entry.$1 + 1}. ${entry.$2}').join('\n')}',
    ].join('\n\n');
    final object = await _requestValidatedObject(
      apiKey: apiKey,
      modelId: normalizedModelId,
      instruction: instruction,
      userContent: userContent,
      temperature: 0.15,
      // A focused request only fills in known items, so it needs far fewer
      // output tokens and almost no reasoning.
      maxTokens: focused ? (450 * focusTerms.length).clamp(600, 3000) : 3000,
      spec: _weakPointDraftsSpec,
      operation: 'Yêu cầu AI tạo điểm yếu',
      effort: focused
          ? _cappedEffort(AiReasoningEffort.low)
          : _effortFor(AiTask.createWeakPoint),
    );
    if (object == null) {
      throw const FormatException(
        'AI trả về bản nháp điểm yếu không đúng cấu trúc sau 2 lần thử',
      );
    }
    final rawItems = object['items'] as List<dynamic>? ?? const [];
    final seen = <String>{};
    final items = rawItems
        .whereType<Map>()
        .map((item) => WeakPointDraft.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.title.isNotEmpty)
        .where(
          (item) => kinds == null || kinds.isEmpty || kinds.contains(item.kind),
        )
        .where((item) => seen.add(weakPointDedupeKey(item.kind, item.title)))
        .toList(growable: false);
    return (items: items, warning: (object['warning'] as String? ?? '').trim());
  }

  /// Số mục gửi trong một lần chuẩn hóa: đủ lớn để chia sẻ prompt hệ thống,
  /// đủ nhỏ để một lỗi JSON không làm hỏng cả loạt.
  static const reformatBatchSize = 6;

  /// Chuẩn hóa một loạt mục cũ trong MỘT lần gọi AI. Trả về bản nháp theo id;
  /// mục AI bỏ sót hoặc trả sai không có trong kết quả.
  Future<Map<String, WeakPointDraft>> reformatWeakPoints({
    required String apiKey,
    required String modelId,
    required List<WeakPoint> points,
    required String jlpt,
    required String language,
  }) async {
    if (points.isEmpty) return const {};
    final source = jsonEncode([
      for (final (index, point) in points.indexed)
        {
          'ref': '$index',
          'kind': point.kind.name,
          'title': point.title,
          'meaning': point.content,
          'reading': point.reading,
          'hanViet': point.hanViet,
          'conjugation': point.conjugation,
          'examples': point.examples,
          'sourceSentence': point.sourceSentence,
          'correctAnswer': point.correctAnswer,
          'mistake': point.mistake,
          'memoryTip': point.reminder,
          'uncertain': point.warning,
          // The full OCR crop is only context; sending it for every item is
          // the largest token cost, so include a short excerpt only when the
          // item has no source sentence of its own.
          if (point.sourceSentence.trim().isEmpty && point.ocrText.isNotEmpty)
            'ocrExcerpt': point.ocrText.length > 240
                ? point.ocrText.substring(0, 240)
                : point.ocrText,
        },
    ]);
    final object = await _requestValidatedObject(
      apiKey: apiKey,
      modelId: modelId.trim(),
      instruction:
          '''Bạn là giáo viên JLPT. Chuẩn hóa TỪNG điểm yếu cũ trong danh sách vào schema
mới; mỗi mục đầu vào trả về đúng một mục với cùng ref.
${answerLanguageRule(language)}
$weakPointTitleGuide
Chỉ sửa nội dung sai định dạng, đưa title về dạng chuẩn, tách thông tin bị đặt
nhầm trường, sửa lỗi OCR khi có bằng chứng. Giữ đúng từ/mẫu/kỹ năng gốc, không
gộp hay tạo điểm học khác. Không bịa nghĩa, cách đọc, Hán Việt hoặc ví dụ; ghi
điều chưa chắc vào uncertain. Thiếu thông tin thì để trường tương ứng rỗng.
questionLabel để rỗng. Trình độ: $jlpt.''',
      userContent: source,
      temperature: 0.1,
      maxTokens: (550 * points.length).clamp(900, 4000),
      spec: _StructuredOutputSpec(
        'reformatted_weak_points',
        _objectSchema({
          'items': _objectArrayProperty('Một mục cho mỗi mục đầu vào.', {
            'ref': _stringProperty('ref của mục đầu vào tương ứng.'),
            ..._weakPointItemProperties(),
          }),
        }),
      ),
      operation: 'Chuẩn hóa điểm yếu',
      effort: _cappedEffort(AiReasoningEffort.low),
    );
    if (object == null) {
      throw const FormatException('AI không trả về điểm yếu hợp lệ');
    }
    final drafts = <String, WeakPointDraft>{};
    for (final raw in (object['items'] as List).whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final index = int.tryParse(item['ref']?.toString() ?? '');
      if (index == null || index < 0 || index >= points.length) continue;
      final draft = WeakPointDraft.fromJson(item);
      if (draft.title.isEmpty) continue;
      drafts[points[index].id] = draft;
    }
    return drafts;
  }

  /// Kiểm tra nhanh: AI giải mọi câu trong vùng chọn, người học tự bấm đáp án
  /// và app chấm tại chỗ (không cần gọi AI lần hai).
  Future<QuickCheckResult> completeQuickCheck({
    required String apiKey,
    required String modelId,
    required String text,
    required String jlpt,
    required String language,
  }) async {
    final instruction =
        '''
Bạn là giáo viên luyện thi JLPT, giải đề chính xác tuyệt đối. Người học đã tự làm
các câu trong vùng khoanh và sẽ so đáp án với bạn.
${answerLanguageRule(language)}
$multiQuestionGuide
$jlptQuestionTypeGuide
Với mỗi câu: xác định questionType, chép stem và từng lựa chọn đúng thứ tự, đánh
dấu correct=true cho đúng một lựa chọn. reason của từng lựa chọn tối đa 1 câu,
explanation tối đa 2 câu, viết đơn giản cho người học $jlpt. Suy luận cẩn thận
trước khi chọn đáp án; nếu đề thiếu dữ kiện thì chọn phương án hợp lý nhất và ghi
rõ vào warning. Không thêm câu hỏi không có trong đề.
Bỏ qua nét viết tay, số trang, chữ rác. Dòng "Lưu ý OCR:" là metadata.
${answerLanguageRule(language)}''';
    return _requestQuickCheck(
      apiKey: apiKey,
      modelId: modelId,
      instruction: instruction,
      userContent: text,
      language: language,
      operation: 'Kiểm tra đáp án',
    );
  }

  /// Tạo đề trắc nghiệm kiểu JLPT từ các điểm yếu để luyện tập; dùng chung
  /// giao diện chấm của Kiểm tra nhanh.
  Future<QuickCheckResult> completePracticeQuestions({
    required String apiKey,
    required String modelId,
    required List<WeakPoint> points,
    required String jlpt,
    required String language,
  }) async {
    if (points.isEmpty) return const QuickCheckResult(questions: []);
    final source = points
        .asMap()
        .entries
        .map((entry) {
          final point = entry.value;
          return [
            '#${entry.key + 1} [${point.kind.name}] ${point.title}',
            if (point.reading.isNotEmpty) 'Cách đọc: ${point.reading}',
            if (point.content.isNotEmpty) 'Nghĩa: ${point.content}',
            if (point.conjugation.isNotEmpty) 'Cách nối: ${point.conjugation}',
            if (point.mistake.isNotEmpty) 'Chỗ hay nhầm: ${point.mistake}',
            if (point.sourceSentence.isNotEmpty)
              'Câu gốc: ${point.sourceSentence}',
          ].join('\n');
        })
        .join('\n\n');
    final instruction =
        '''
Bạn là người ra đề JLPT $jlpt. Với MỖI điểm yếu được liệt kê, tạo đúng một câu
trắc nghiệm mới theo dạng đề JLPT phù hợp nhất (漢字読み/表記 cho kanji,
文脈規定/言い換え類義/用法 cho từ vựng, 文法形式の判断/文の組み立て cho ngữ pháp).
$jlptQuestionTypeGuide
Yêu cầu: 4 lựa chọn nhãn 1–4, đúng một đáp án; lựa chọn nhiễu phải hợp lý, ưu
tiên dựa vào "Chỗ hay nhầm". Không dùng lại nguyên văn câu gốc. label là số thứ
tự (#). point là tiêu đề điểm yếu tương ứng. reason tối đa 1 câu, explanation tối
đa 2 câu. ${answerLanguageRule(language)}''';
    return _requestQuickCheck(
      apiKey: apiKey,
      modelId: modelId,
      instruction: instruction,
      userContent: source,
      language: language,
      operation: 'Tạo đề luyện tập',
      temperature: .6,
      effort: _cappedEffort(AiReasoningEffort.medium),
    );
  }

  Future<QuickCheckResult> _requestQuickCheck({
    required String apiKey,
    required String modelId,
    required String instruction,
    required String userContent,
    required String language,
    required String operation,
    double temperature = .1,
    AiReasoningEffort? effort,
  }) async {
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) throw ArgumentError('Chưa chọn model AI');
    final spec = _quickCheckSpecFor(language);
    Future<QuickCheckResult> request(String systemPrompt) async {
      final object = await _requestValidatedObject(
        apiKey: apiKey,
        modelId: normalizedModelId,
        instruction: systemPrompt,
        userContent: userContent,
        temperature: temperature,
        maxTokens: 3200,
        spec: spec,
        operation: operation,
        effort: effort ?? reasoningEffort,
      );
      if (object == null) {
        throw FormatException(
          '$operation: AI trả về sai cấu trúc sau 2 lần thử',
        );
      }
      final questions = (object['questions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                QuickCheckQuestion.fromJson(Map<String, dynamic>.from(item)),
          )
          .where(
            (question) =>
                question.choices.isNotEmpty || question.answer.isNotEmpty,
          )
          .toList(growable: false);
      if (questions.isEmpty) {
        throw const FormatException(
          'Không tìm thấy câu hỏi nào trong vùng đã khoanh',
        );
      }
      return QuickCheckResult(
        questions: questions,
        warning: (object['warning'] as String? ?? '').trim(),
      );
    }

    final first = await request(instruction);
    if (isJapaneseLanguage(language) || !_explainedInJapanese(first)) {
      return first;
    }
    // The prompt and schema already demand the target language; one retry
    // naming the concrete mistake fixes a model that still mirrors the
    // Japanese of the exam text.
    try {
      final retried = await request(
        '$instruction\n\nLần trước bạn đã viết explanation/reason bằng tiếng Nhật — '
        'sai. Viết lại toàn bộ explanation, reason và warning bằng $language.',
      );
      return _explainedInJapanese(retried) ? first : retried;
    } catch (_) {
      return first;
    }
  }

  bool _explainedInJapanese(QuickCheckResult result) {
    final texts = [
      for (final question in result.questions) ...[
        question.explanation,
        for (final choice in question.choices) choice.reason,
      ],
    ].where((text) => text.trim().isNotEmpty).toList(growable: false);
    if (texts.isEmpty) return false;
    // The explanation is what the learner reads first; one in Japanese is
    // already a failure even if the per-choice reasons came out right.
    return result.questions.any(
          (question) => looksJapaneseOnly(question.explanation),
        ) ||
        texts.where(looksJapaneseOnly).length * 2 > texts.length;
  }

  @visibleForTesting
  bool explainedInJapaneseForTesting(QuickCheckResult result) =>
      _explainedInJapanese(result);

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
    const instruction =
        'Bạn là OCR tiếng Nhật. Đọc đoạn nội dung chính, giữ nguyên kanji/kana và xuống dòng; bỏ qua nét viết tay, số trang hoặc chữ rác rời rạc ở ngoài đoạn chính. Nếu chỉ thiếu hoặc sai 1–2 chữ và ngữ cảnh đủ rõ, phục dựng phương án hợp lý nhất rồi ghi rõ câu đã phục dựng và phần chưa chắc trong warning. Không âm thầm đoán phần bị cắt lớn.';
    final data = await _requestValidatedObject(
      apiKey: apiKey,
      modelId: modelId,
      instruction: instruction,
      userContent: [
        {
          'type': 'text',
          'text': 'Đọc toàn bộ chữ Nhật trong vùng ảnh đã khoanh.',
        },
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,${base64Encode(bytes)}'},
        },
      ],
      temperature: 0,
      // A full reading passage can easily exceed 220 tokens once JSON
      // escaping and an uncertainty note are included.
      maxTokens: 1400,
      spec: _ocrSpec,
      operation: 'Nhận diện ảnh',
      retryRateLimit: true,
      preferLatency: true,
    );
    if (data == null) {
      throw const FormatException(
        'AI trả về OCR không đúng cấu trúc sau 2 lần thử',
      );
    }
    final text = (data['text'] as String).trim();
    if (text.isEmpty) throw const FormatException('OCR trống');
    final warning = (data['warning'] as String).trim();
    return warning.isEmpty ? text : '$text\n\nLưu ý OCR: $warning';
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
Bạn là giáo viên tiếng Nhật chính xác và súc tích. Chỉ phân tích nội dung người dùng đã chủ động khoanh. Bỏ qua note viết tay, số trang hoặc chữ rác rời rạc không thuộc đoạn chính. Nếu OCR sai hoặc thiếu 1–2 chữ nhưng ngữ cảnh đủ rõ, hãy phục dựng cả cụm/câu hợp lý nhất để hoàn thành nhiệm vụ; trong warning bắt buộc ghi "Đã phục dựng: ..." và nêu phần còn chưa chắc. Nếu đầu vào đã có dòng "Lưu ý OCR:", đó là metadata: đưa thông tin cần thiết vào warning, không dịch hoặc phân tích nó như nội dung tiếng Nhật. Không âm thầm sửa OCR và không suy đoán phần bị mất lớn. Không trò chuyện, không chào hỏi và không thêm lời dẫn.''';
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
Giữ tên riêng; nuance tối đa 1 câu. $translationInstruction''',
      AiTask.explain =>
        '''
Nhiệm vụ: giải thích tiếng Nhật bằng $language ở độ khó phù hợp $jlpt.
Chọn tối đa 3 cấu trúc chính cho mỗi câu (tổng tối đa 8) và tối đa 10 đoạn tách câu.
Với một câu hoàn chỉnh, meaning, structures và segments đều bắt buộc có nội dung; không được chỉ trả meaning. Mỗi cấu trúc phải có pattern, meaning và usage. Mỗi đoạn phải giữ nguyên japanese rồi mới giải nghĩa.
Nếu nội dung là đề có câu hỏi và lựa chọn: mỗi câu hỏi là một mục trong questions, xác định questionType, đáp án đúng rồi giải thích thật đơn giản vì sao đúng và vì sao từng lựa chọn còn lại sai (mỗi reason tối đa 2 câu). Nếu không có câu hỏi, trả questions là [].
$multiQuestionGuide
$jlptQuestionTypeGuide''',
      AiTask.solve =>
        '''
Nhiệm vụ: giải từng câu bằng $language, phù hợp $jlpt. Đánh dấu đúng một lựa chọn đúng, giải thích vì sao đúng và vì sao từng lựa chọn còn lại không phù hợp.
$multiQuestionGuide
$jlptQuestionTypeGuide''',
      AiTask.createWeakPoint =>
        '''
Nhiệm vụ: tạo bản nháp điểm yếu bằng $language cho người học $jlpt.
Loại người dùng đã chọn: ${weaknessKind ?? 'grammar'}.
Nếu là grammar, title chỉ ghi mẫu ngữ pháp, meaning thật ngắn; conjugation ghi cách nối. mistake so sánh ngắn với mẫu dễ nhầm nếu có.
Nếu là vocabulary hoặc kanji, bắt buộc ghi cách đọc; Hán Việt chỉ ghi khi chắc chắn, phần chưa chắc ghi vào uncertain.
$jlptQuestionTypeGuide''',
      AiTask.dictionary =>
        '''
Nhiệm vụ: tra từ tiếng Nhật bằng AI cho người học $jlpt, trả lời bằng $language.
Chỉ tra đúng từ/cụm từ người dùng đã khoanh. Nếu có nhiều cách đọc hoặc nghĩa, chọn cách thông dụng nhất và ghi các nghĩa ngắn gọn. Không tự bịa khi OCR không rõ; ghi lý do trong warning.''',
    };
    if (task == AiTask.translate) return '$shared\n$taskPrompt';
    return '$shared\n$taskPrompt\n${answerLanguageRule(language)}';
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
        AiTask.createWeakPoint => _formatWeakPoint(data) + suffix,
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

  String _responseContent(String responseBody) {
    final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty || choices.first is! Map) {
      throw const FormatException('AI không trả về nội dung');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map) {
      throw const FormatException('AI không trả về nội dung');
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('AI không trả về nội dung');
    }
    return content;
  }

  Map<String, dynamic>? _validatedResponseObject(
    String responseBody,
    Map<String, dynamic> schema,
  ) {
    try {
      final candidate = _decodeJsonObject(_responseContent(responseBody));
      return _matchesSchema(candidate, schema) ? candidate : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  void _throwIfRequestFailed(
    _HttpResult response, {
    required String operation,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (_isStructuredOutputUnsupported(response)) {
      throw HttpException(
        '$operation thất bại: model hoặc provider không hỗ trợ Structured Outputs',
      );
    }
    throw HttpException('$operation thất bại (${response.statusCode})');
  }

  bool _isStructuredOutputUnsupported(_HttpResult response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return false;
    final detail = response.body.toLowerCase();
    return detail.contains('response_format') ||
        detail.contains('structured output') ||
        detail.contains('require_parameters') ||
        detail.contains('no endpoints found');
  }

  bool _matchesSchema(Object? value, Map<String, dynamic> schema) {
    final allowedValues = schema['enum'];
    if (allowedValues is List && !allowedValues.contains(value)) return false;
    switch (schema['type']) {
      case 'string':
        return value is String;
      case 'boolean':
        return value is bool;
      case 'number':
        return value is num;
      case 'integer':
        return value is int;
      case 'array':
        if (value is! List) return false;
        final items = schema['items'];
        if (items is! Map) return true;
        final itemSchema = Map<String, dynamic>.from(items);
        return value.every((item) => _matchesSchema(item, itemSchema));
      case 'object':
        if (value is! Map) return false;
        final propertiesValue = schema['properties'];
        if (propertiesValue is! Map) return false;
        final properties = Map<String, dynamic>.from(propertiesValue);
        final required = (schema['required'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toSet();
        if (!required.every(value.containsKey)) return false;
        if (schema['additionalProperties'] == false &&
            value.keys.any((key) => !properties.containsKey(key))) {
          return false;
        }
        for (final entry in value.entries) {
          final propertySchema = properties[entry.key];
          if (propertySchema is Map &&
              !_matchesSchema(
                entry.value,
                Map<String, dynamic>.from(propertySchema),
              )) {
            return false;
          }
        }
        return true;
      default:
        return false;
    }
  }

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
    final questions = data['questions'];
    if (questions is List && questions.whereType<Map>().isNotEmpty) {
      buffer.write('\n\nĐáp án từng câu');
      for (final item in questions.whereType<Map>()) {
        _writeQuestion(buffer, Map<String, dynamic>.from(item));
      }
      return buffer.toString();
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

  String _formatWeakPoint(Map<String, dynamic> data) {
    final draft = WeakPointDraft.fromJson(data);
    return [
      draft.title,
      _optionalLine('Nghĩa', draft.content).trim(),
      _optionalLine('Cách đọc', draft.reading).trim(),
      _optionalLine('Hán Việt', draft.hanViet).trim(),
      _optionalLine('Cách nối', draft.conjugation).trim(),
      _optionalLine('Ví dụ', draft.examples.join('\n')).trim(),
      _optionalLine('Đáp án đúng', draft.correctAnswer).trim(),
      _optionalLine('Chỗ dễ nhầm', draft.mistake).trim(),
      _optionalLine('Mẹo nhớ', draft.reminder).trim(),
      _optionalLine('Chưa chắc', draft.warning).trim(),
    ].where((part) => part.isNotEmpty).join('\n\n');
  }

  /// Một câu hỏi: "Câu 2 · 文脈規定 — Đáp án: 3" rồi từng lựa chọn.
  void _writeQuestion(StringBuffer buffer, Map<String, dynamic> item) {
    final label = _firstText(item, const ['label']);
    final type = _firstText(item, const ['questionType']);
    final heading = [
      label.isEmpty ? 'Câu hỏi' : 'Câu $label',
      if (type.isNotEmpty && type != JlptQuestionType.other.japanese)
        '${jlptQuestionTypeFrom(type).label} ($type)',
    ].join(' · ');
    final question = QuickCheckQuestion.fromJson(item);
    final answer = question.choices.isEmpty
        ? _firstText(item, const ['answer'])
        : question.correctText;
    buffer.write('\n\n$heading');
    if (answer.isNotEmpty) buffer.write('\nĐáp án: $answer');
    final explanation = _firstText(item, const ['explanation', 'reason']);
    if (explanation.isNotEmpty) buffer.write('\n$explanation');
    final rawChoices = item['choices'];
    if (rawChoices is List) {
      for (final raw in rawChoices.whereType<Map>()) {
        final choice = Map<String, dynamic>.from(raw);
        final choiceLabel = _firstText(choice, const ['label']);
        final text = _firstText(choice, const ['text']);
        final reason = _firstText(choice, const ['reason']);
        final mark = _isTrue(choice['correct']) ? '✓' : '✗';
        buffer.write(
          '\n$mark ${[choiceLabel, text].where((part) => part.isNotEmpty).join('. ')}'
          '${reason.isEmpty ? '' : ': $reason'}',
        );
      }
    }
  }

  String _formatSolution(Map<String, dynamic> data) {
    final questions = data['questions'];
    if (questions is List) {
      final buffer = StringBuffer();
      for (final item in questions.whereType<Map>()) {
        _writeQuestion(buffer, Map<String, dynamic>.from(item));
      }
      return buffer.toString().trim();
    }
    return _formatLegacySolution(data);
  }

  String _formatLegacySolution(Map<String, dynamic> data) {
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
    Duration timeout = const Duration(seconds: 30),
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
    final response = await request.close().timeout(timeout);
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
