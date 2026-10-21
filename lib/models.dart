import 'dart:ui';

enum AppDestination { library, weaknesses, dictionary, settings }

enum EditorTool {
  pen,
  highlighter,
  eraser,
  lasso,
  ruler,
  image,
  dictionary,
  quickDictionary,
  aiDictionary,
  translate,
  explain,
  weakness,
  quickCheck,
}

enum PaperStyle { blank, lined, grid, dotted, genkou }

/// Màu đường kẻ giấy mặc định (vở cũ chưa lưu màu dùng màu này).
const defaultPaperLineColor = Color(0xff758ab4);

/// Kiểu nét của công cụ Bút. Nét cũ không lưu kiểu được đọc là thư pháp.
enum PenStyle {
  calligraphy('Bút thư pháp', 'Đầu vát, nét đổi độ rộng theo hướng và lực'),
  fountain('Bút máy', 'Nét mảnh, đậm dần theo lực, thuôn hai đầu'),
  ballpoint('Bút bi', 'Nét đều, hơi đổi theo lực'),
  marker('Bút dạ', 'Nét dày đều, đầu tròn, không thuôn'),
  pencil('Bút chì', 'Nét mảnh, rõ, có vân chì');

  const PenStyle(this.label, this.helper);
  final String label;
  final String helper;
}

class PageImagePlacement {
  const PageImagePlacement({
    required this.id,
    required this.path,
    required this.rect,
    this.rotation = 0,
    this.isBackground = false,
  });

  final String id;
  final String path;
  final Rect rect;
  final double rotation;
  final bool isBackground;

  PageImagePlacement copyWith({String? path, Rect? rect, double? rotation}) =>
      PageImagePlacement(
        id: id,
        path: path ?? this.path,
        rect: rect ?? this.rect,
        rotation: rotation ?? this.rotation,
        isBackground: isBackground,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
    'rotation': rotation,
    'isBackground': isBackground,
  };

  factory PageImagePlacement.fromJson(Map<String, dynamic> json) =>
      PageImagePlacement(
        id: json['id'] as String,
        path: json['path'] as String,
        rect: Rect.fromLTWH(
          (json['left'] as num?)?.toDouble() ?? 0,
          (json['top'] as num?)?.toDouble() ?? 0,
          (json['width'] as num?)?.toDouble() ?? 1,
          (json['height'] as num?)?.toDouble() ?? 1,
        ),
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        isBackground: json['isBackground'] as bool? ?? false,
      );
}

enum WeaknessKind { grammar, vocabulary, kanji, reading, other }

enum TranslationStyle { literal, balanced, fluent }

/// Mức suy luận gửi cho model hỗ trợ reasoning. Mức cao cho kết quả kỹ hơn
/// nhưng tốn thời gian hơn; model không hỗ trợ sẽ tự bỏ qua tham số này.
enum AiReasoningEffort { low, medium, high }

extension AiReasoningEffortLabel on AiReasoningEffort {
  String get label => switch (this) {
    AiReasoningEffort.low => 'Nhanh',
    AiReasoningEffort.medium => 'Cân bằng',
    AiReasoningEffort.high => 'Kỹ (high)',
  };

  String get helper => switch (this) {
    AiReasoningEffort.low => 'Trả lời nhanh nhất, phù hợp câu đơn giản.',
    AiReasoningEffort.medium => 'Cân bằng giữa tốc độ và độ chính xác.',
    AiReasoningEffort.high =>
      'Suy luận kỹ nhất, chính xác hơn với đề nhiều câu nhưng chậm hơn.',
  };
}

/// Các dạng đề (問題) của JLPT phần 言語知識・読解. AI nhận dạng dạng đề để
/// áp dụng đúng cách giải; app lưu dạng đề vào điểm yếu để thống kê.
enum JlptQuestionType {
  kanjiReading,
  orthography,
  wordFormation,
  contextVocab,
  paraphrase,
  usage,
  grammarForm,
  sentenceOrder,
  textGrammar,
  readingComprehension,
  integratedReading,
  infoRetrieval,
  other,
}

extension JlptQuestionTypeInfo on JlptQuestionType {
  /// Tên gốc trong đề JLPT, cũng là giá trị enum gửi cho AI.
  String get japanese => switch (this) {
    JlptQuestionType.kanjiReading => '漢字読み',
    JlptQuestionType.orthography => '表記',
    JlptQuestionType.wordFormation => '語形成',
    JlptQuestionType.contextVocab => '文脈規定',
    JlptQuestionType.paraphrase => '言い換え類義',
    JlptQuestionType.usage => '用法',
    JlptQuestionType.grammarForm => '文法形式の判断',
    JlptQuestionType.sentenceOrder => '文の組み立て',
    JlptQuestionType.textGrammar => '文章の文法',
    JlptQuestionType.readingComprehension => '内容理解',
    JlptQuestionType.integratedReading => '統合理解・主張理解',
    JlptQuestionType.infoRetrieval => '情報検索',
    JlptQuestionType.other => 'その他',
  };

  String get label => switch (this) {
    JlptQuestionType.kanjiReading => 'Đọc Kanji',
    JlptQuestionType.orthography => 'Viết Kanji',
    JlptQuestionType.wordFormation => 'Cấu tạo từ',
    JlptQuestionType.contextVocab => 'Từ theo ngữ cảnh',
    JlptQuestionType.paraphrase => 'Từ đồng nghĩa',
    JlptQuestionType.usage => 'Cách dùng từ',
    JlptQuestionType.grammarForm => 'Chọn ngữ pháp',
    JlptQuestionType.sentenceOrder => 'Sắp xếp câu (★)',
    JlptQuestionType.textGrammar => 'Ngữ pháp đoạn văn',
    JlptQuestionType.readingComprehension => 'Đọc hiểu nội dung',
    JlptQuestionType.integratedReading => 'Đọc tổng hợp/chủ trương',
    JlptQuestionType.infoRetrieval => 'Tìm thông tin',
    JlptQuestionType.other => 'Khác',
  };

  /// Loại điểm yếu mặc định sinh ra từ dạng đề này.
  WeaknessKind get defaultKind => switch (this) {
    JlptQuestionType.kanjiReading ||
    JlptQuestionType.orthography => WeaknessKind.kanji,
    JlptQuestionType.wordFormation ||
    JlptQuestionType.contextVocab ||
    JlptQuestionType.paraphrase ||
    JlptQuestionType.usage => WeaknessKind.vocabulary,
    JlptQuestionType.grammarForm ||
    JlptQuestionType.sentenceOrder ||
    JlptQuestionType.textGrammar => WeaknessKind.grammar,
    JlptQuestionType.readingComprehension ||
    JlptQuestionType.integratedReading ||
    JlptQuestionType.infoRetrieval => WeaknessKind.reading,
    JlptQuestionType.other => WeaknessKind.other,
  };

  /// Tag lưu trong điểm yếu để lọc/thống kê theo dạng đề.
  String get tag => '問題:$japanese';
}

JlptQuestionType jlptQuestionTypeFrom(String? raw) {
  final value = (raw ?? '').trim();
  return JlptQuestionType.values.firstWhere(
    (type) => type.japanese == value || type.name == value,
    orElse: () => JlptQuestionType.other,
  );
}

/// Mức đánh giá khi ôn flashcard.
enum ReviewRating { again, hard, good, easy }

extension ReviewRatingLabel on ReviewRating {
  String get label => switch (this) {
    ReviewRating.again => 'Quên',
    ReviewRating.hard => 'Khó',
    ReviewRating.good => 'Được',
    ReviewRating.easy => 'Dễ',
  };
}

extension TranslationStyleLabel on TranslationStyle {
  String get label => switch (this) {
    TranslationStyle.literal => 'Sát nghĩa',
    TranslationStyle.balanced => 'Tự nhiên',
    TranslationStyle.fluent => 'Mượt mà',
  };

  String get helper => switch (this) {
    TranslationStyle.literal =>
      'Bám sát từ ngữ và cấu trúc câu gốc, không lược ý.',
    TranslationStyle.balanced =>
      'Giữ đủ ý nhưng điều chỉnh vừa phải để dễ đọc.',
    TranslationStyle.fluent =>
      'Ưu tiên câu tiếng Việt trôi chảy, có thể đổi trật tự diễn đạt.',
  };
}

/// Nơi gọi AI. Cả hai đều dùng API kiểu OpenAI `/chat/completions`.
enum AiProvider {
  openRouter(
    label: 'OpenRouter',
    description: 'Một API key, nhiều model của nhiều hãng',
    baseUrl: 'https://openrouter.ai/api/v1',
    keyHint: 'sk-or-v1-...',
    keyUrl: 'openrouter.ai/keys',
  ),
  gemini(
    label: 'Gemini',
    description: 'Key Google AI Studio, gọi thẳng model Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    keyHint: 'AIza...',
    keyUrl: 'aistudio.google.com/apikey',
  );

  const AiProvider({
    required this.label,
    required this.description,
    required this.baseUrl,
    required this.keyHint,
    required this.keyUrl,
  });
  final String label;
  final String description;
  final String baseUrl;
  final String keyHint;
  final String keyUrl;
}

/// Các ngăn model độc lập. Một API key có thể dùng nhiều model.
enum AiModelSlot { vision, translate, explain, solve, weakness, dictionary }

extension AiModelSlotLabel on AiModelSlot {
  String get label => switch (this) {
    AiModelSlot.vision => 'Nhận diện ảnh',
    AiModelSlot.translate => 'AI Dịch',
    AiModelSlot.explain => 'AI Giải thích',
    AiModelSlot.solve => 'Kiểm tra đáp án',
    AiModelSlot.weakness => 'Tạo điểm yếu',
    AiModelSlot.dictionary => 'AI Tra từ',
  };

  String get helper => switch (this) {
    AiModelSlot.vision => 'OCR bằng model Vision (tùy chọn, có thể tính phí)',
    AiModelSlot.translate => 'Dịch vùng chữ bạn đã khoanh',
    AiModelSlot.explain => 'Phân tích ngữ pháp và tách câu',
    AiModelSlot.solve => 'Kiểm tra nhanh đáp án và tạo đề luyện tập',
    AiModelSlot.weakness => 'Tạo bản nháp sổ điểm yếu',
    AiModelSlot.dictionary =>
      'Tra từ bằng AI, không dùng cơ sở dữ liệu ngoại tuyến',
  };
}

extension WeaknessKindLabel on WeaknessKind {
  String get label => switch (this) {
    WeaknessKind.grammar => 'Ngữ pháp',
    WeaknessKind.vocabulary => 'Từ vựng',
    WeaknessKind.kanji => 'Kanji',
    WeaknessKind.reading => 'Đọc hiểu',
    WeaknessKind.other => 'Khác',
  };
}

class NotebookData {
  const NotebookData({
    required this.id,
    required this.title,
    required this.type,
    required this.pages,
    required this.color,
    this.folderId,
    this.tags = const [],
    this.isPinned = false,
    this.isTrashed = false,
    this.paperStyle = PaperStyle.grid,
    this.paperLineOpacity = .09,
    this.paperLineColor = defaultPaperLineColor,
    this.lastOpened = 'Vừa xong',
  });

  final String id;
  final String title;
  final String type;
  final int pages;
  final Color color;
  final String? folderId;

  /// Content classification is independent from the notebook's folder path.
  /// A notebook has one folder but can carry any number of tags.
  final List<String> tags;
  final bool isPinned;
  final bool isTrashed;
  final PaperStyle paperStyle;
  final double paperLineOpacity;
  final Color paperLineColor;
  final String lastOpened;

  bool get isPdf => type == 'PDF';

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'pages': pages,
    'color': color.toARGB32(),
    'folderId': folderId,
    'tags': tags,
    'isPinned': isPinned,
    'isTrashed': isTrashed,
    'paperStyle': paperStyle.name,
    'paperLineOpacity': paperLineOpacity,
    'paperLineColor': paperLineColor.toARGB32(),
    'lastOpened': lastOpened,
  };

  factory NotebookData.fromJson(Map<String, dynamic> json) => NotebookData(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Notebook',
    type: json['type'] as String? ?? 'Notebook',
    pages: ((json['pages'] as num?)?.toInt() ?? 1).clamp(1, 10000).toInt(),
    color: Color((json['color'] as num?)?.toInt() ?? 0xffdce1ff),
    folderId: json['folderId'] as String?,
    tags: List<String>.from(json['tags'] as List? ?? const []),
    isPinned: json['isPinned'] as bool? ?? false,
    isTrashed: json['isTrashed'] as bool? ?? false,
    paperStyle: PaperStyle.values.firstWhere(
      (value) => value.name == json['paperStyle'],
      orElse: () => PaperStyle.grid,
    ),
    paperLineOpacity: (json['paperLineOpacity'] as num?)?.toDouble() ?? .09,
    paperLineColor: Color(
      (json['paperLineColor'] as num?)?.toInt() ??
          defaultPaperLineColor.toARGB32(),
    ),
    lastOpened: json['lastOpened'] as String? ?? 'Vừa xong',
  );

  NotebookData copyWith({
    String? title,
    String? type,
    int? pages,
    Color? color,
    String? folderId,
    bool clearFolder = false,
    List<String>? tags,
    bool? isPinned,
    bool? isTrashed,
    PaperStyle? paperStyle,
    double? paperLineOpacity,
    Color? paperLineColor,
    String? lastOpened,
  }) => NotebookData(
    id: id,
    title: title ?? this.title,
    type: type ?? this.type,
    pages: pages ?? this.pages,
    color: color ?? this.color,
    folderId: clearFolder ? null : (folderId ?? this.folderId),
    tags: tags ?? this.tags,
    isPinned: isPinned ?? this.isPinned,
    isTrashed: isTrashed ?? this.isTrashed,
    paperStyle: paperStyle ?? this.paperStyle,
    paperLineOpacity: paperLineOpacity ?? this.paperLineOpacity,
    paperLineColor: paperLineColor ?? this.paperLineColor,
    lastOpened: lastOpened ?? this.lastOpened,
  );
}

class FolderData {
  const FolderData({
    required this.id,
    required this.name,
    this.parentId,
    this.color = 0xff6b7280,
    this.iconCodePoint = 0xe2c7,
    this.isPinned = false,
    this.isExpanded = true,
    this.isTrashed = false,
  });

  final String id;
  final String name;
  final String? parentId;
  final int color;
  final int iconCodePoint;
  final bool isPinned;
  final bool isExpanded;
  final bool isTrashed;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'color': color,
    'iconCodePoint': iconCodePoint,
    'isPinned': isPinned,
    'isExpanded': isExpanded,
    'isTrashed': isTrashed,
  };

  factory FolderData.fromJson(Map<String, dynamic> json) => FolderData(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Folder',
    parentId: json['parentId'] as String?,
    color: (json['color'] as num?)?.toInt() ?? 0xff6b7280,
    iconCodePoint: (json['iconCodePoint'] as num?)?.toInt() ?? 0xe2c7,
    isPinned: json['isPinned'] as bool? ?? false,
    isExpanded: json['isExpanded'] as bool? ?? true,
    isTrashed: json['isTrashed'] as bool? ?? false,
  );

  FolderData copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
    int? color,
    int? iconCodePoint,
    bool? isPinned,
    bool? isExpanded,
    bool? isTrashed,
  }) => FolderData(
    id: id,
    name: name ?? this.name,
    parentId: clearParent ? null : (parentId ?? this.parentId),
    color: color ?? this.color,
    iconCodePoint: iconCodePoint ?? this.iconCodePoint,
    isPinned: isPinned ?? this.isPinned,
    isExpanded: isExpanded ?? this.isExpanded,
    isTrashed: isTrashed ?? this.isTrashed,
  );
}

class StrokePoint {
  const StrokePoint(this.offset, this.pressure, [this.timeMicros = 0]);
  final Offset offset;
  final double pressure;
  final int timeMicros;

  Map<String, Object?> toJson() => {
    'x': offset.dx,
    'y': offset.dy,
    'pressure': pressure,
    'timeMicros': timeMicros,
  };

  factory StrokePoint.fromJson(Map<String, dynamic> json) => StrokePoint(
    Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble()),
    (json['pressure'] as num?)?.toDouble() ?? 1,
    (json['timeMicros'] as num?)?.toInt() ?? 0,
  );
}

class InkStroke {
  InkStroke({
    required this.points,
    required this.color,
    required this.width,
    required this.tool,
    required this.createdAt,
    this.penStyle = PenStyle.calligraphy,
  });

  final List<StrokePoint> points;
  final Color color;
  final double width;
  final EditorTool tool;
  final DateTime createdAt;
  final PenStyle penStyle;

  Map<String, Object> toJson() => {
    'points': points.map((point) => point.toJson()).toList(),
    'color': color.toARGB32(),
    'width': width,
    'tool': tool.name,
    'createdAt': createdAt.toIso8601String(),
    if (penStyle != PenStyle.calligraphy) 'penStyle': penStyle.name,
  };

  factory InkStroke.fromJson(Map<String, dynamic> json) => InkStroke(
    points: (json['points'] as List)
        .map((item) => StrokePoint.fromJson(item as Map<String, dynamic>))
        .toList(),
    color: Color(json['color'] as int),
    width: (json['width'] as num).toDouble(),
    tool: EditorTool.values.byName(json['tool'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    penStyle: PenStyle.values.firstWhere(
      (style) => style.name == json['penStyle'],
      orElse: () => PenStyle.calligraphy,
    ),
  );
}

class PinnedNote {
  const PinnedNote({
    required this.title,
    required this.body,
    required this.color,
  });
  final String title;
  final String body;
  final Color color;

  Map<String, Object?> toJson() => {
    'title': title,
    'body': body,
    'color': color.toARGB32(),
  };

  factory PinnedNote.fromJson(Map<String, dynamic> json) => PinnedNote(
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    color: Color((json['color'] as num?)?.toInt() ?? 0xfffff1b8),
  );
}

class WeakPoint {
  WeakPoint({
    required this.id,
    required this.title,
    required this.kind,
    required this.content,
    required this.reminder,
    required this.note,
    required this.tags,
    required this.notebookId,
    required this.notebookTitle,
    required this.page,
    required this.ocrText,
    required this.createdAt,
    this.sourceImagePath,
    this.reading = '',
    this.hanViet = '',
    this.conjugation = '',
    this.examples = const [],
    this.sourceSentence = '',
    this.correctAnswer = '',
    this.mistake = '',
    this.warning = '',
    this.dueAt,
    this.intervalDays = 0,
    this.ease = 2.5,
    this.reps = 0,
    this.lapses = 0,
    this.lastReviewedAt,
    this.needsRevisit = false,
    this.formatVersion = 0,
  });

  final String id;
  String title;
  WeaknessKind kind;

  /// Phiên bản quy tắc chuẩn hóa mà mục này đã đạt ([weakPointFormatVersion]).
  /// "Chuẩn hóa toàn bộ" bỏ qua mục đã ở phiên bản hiện tại để không tốn token.
  int formatVersion;

  bool get isNormalized => formatVersion >= weakPointFormatVersion;

  /// Nghĩa / nội dung chính cần học.
  String content;

  /// Mẹo ghi nhớ ngắn.
  String reminder;

  /// Ghi chú riêng của người học; AI không điền trường này.
  String note;
  List<String> tags;
  final String notebookId;
  final String notebookTitle;
  final int page;
  final String ocrText;
  final DateTime createdAt;
  final String? sourceImagePath;
  String reading;
  String hanViet;
  String conjugation;
  List<String> examples;
  String sourceSentence;

  /// Đáp án đúng khi điểm yếu đến từ một câu hỏi.
  String correctAnswer;

  /// Chỗ đã sai / dễ nhầm và vì sao.
  String mistake;

  /// Phần AI chưa chắc chắn (OCR phục dựng, Hán Việt không chắc...).
  String warning;

  // Lịch ôn lặp lại ngắt quãng. `dueAt == null` nghĩa là thẻ mới.
  DateTime? dueAt;
  double intervalDays;
  double ease;
  int reps;
  int lapses;
  DateTime? lastReviewedAt;
  bool needsRevisit;

  bool get isNewCard => lastReviewedAt == null;

  bool isDue(DateTime now) => dueAt == null || !dueAt!.isAfter(now);

  /// Khóa so trùng: cùng loại và cùng tiêu đề sau khi bỏ khoảng trắng/〜.
  String get dedupeKey => weakPointDedupeKey(kind, title);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'content': content,
    'reminder': reminder,
    'note': note,
    'tags': tags,
    'notebookId': notebookId,
    'notebookTitle': notebookTitle,
    'page': page,
    'ocrText': ocrText,
    'createdAt': createdAt.toIso8601String(),
    'sourceImagePath': sourceImagePath,
    'reading': reading,
    'hanViet': hanViet,
    'conjugation': conjugation,
    'examples': examples,
    'sourceSentence': sourceSentence,
    'correctAnswer': correctAnswer,
    'mistake': mistake,
    'warning': warning,
    'dueAt': dueAt?.toIso8601String(),
    'intervalDays': intervalDays,
    'ease': ease,
    'reps': reps,
    'lapses': lapses,
    'lastReviewedAt': lastReviewedAt?.toIso8601String(),
    'needsRevisit': needsRevisit,
    'formatVersion': formatVersion,
  };

  /// Đọc khoan dung: một trường cũ/hỏng không được làm mất cả danh sách.
  factory WeakPoint.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key]?.toString() ?? '';
    List<String> texts(String key) => (json[key] is List)
        ? (json[key] as List).map((value) => value.toString()).toList()
        : <String>[];
    DateTime? date(String key) =>
        json[key] is String ? DateTime.tryParse(json[key] as String) : null;
    final id = text('id');
    if (id.isEmpty) throw const FormatException('Điểm yếu thiếu id');
    return WeakPoint(
      id: id,
      title: text('title'),
      kind: WeaknessKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => WeaknessKind.other,
      ),
      content: text('content'),
      reminder: text('reminder'),
      note: text('note'),
      tags: texts('tags'),
      notebookId: text('notebookId'),
      notebookTitle: text('notebookTitle'),
      page: (json['page'] as num?)?.toInt() ?? 1,
      ocrText: text('ocrText'),
      createdAt: date('createdAt') ?? DateTime.now(),
      sourceImagePath: json['sourceImagePath'] as String?,
      reading: text('reading'),
      hanViet: text('hanViet'),
      conjugation: text('conjugation'),
      examples: texts('examples'),
      sourceSentence: text('sourceSentence'),
      correctAnswer: text('correctAnswer'),
      mistake: text('mistake'),
      warning: text('warning'),
      dueAt: date('dueAt'),
      intervalDays: (json['intervalDays'] as num?)?.toDouble() ?? 0,
      ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
      reps: (json['reps'] as num?)?.toInt() ?? 0,
      lapses: (json['lapses'] as num?)?.toInt() ?? 0,
      lastReviewedAt: date('lastReviewedAt'),
      needsRevisit: json['needsRevisit'] == true,
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Tăng khi quy tắc chuẩn hóa (schema hoặc dạng tiêu đề) thay đổi, để các mục
/// cũ được chuẩn hóa lại còn mục đã đạt chuẩn thì bỏ qua.
/// 2: động từ ở thể ます, từ loại khác ở dạng đứng đơn.
const weakPointFormatVersion = 2;

String weakPointDedupeKey(WeaknessKind kind, String title) {
  final normalized = title.toLowerCase().replaceAll(
    RegExp(r'[\s〜~～・。、「」『』（）()]'),
    '',
  );
  return '${kind.name}|$normalized';
}

WeaknessKind weaknessKindFromName(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  return switch (value) {
    'grammar' || 'ngữ pháp' => WeaknessKind.grammar,
    'vocabulary' || 'vocab' || 'từ vựng' => WeaknessKind.vocabulary,
    'kanji' => WeaknessKind.kanji,
    'reading' || 'đọc hiểu' => WeaknessKind.reading,
    _ => WeaknessKind.other,
  };
}

/// Bản nháp điểm yếu do AI tách ra từ một vùng câu hỏi/câu trả lời.
/// Một vùng OCR có thể tạo nhiều bản nháp độc lập.
class WeakPointDraft {
  const WeakPointDraft({
    required this.title,
    required this.kind,
    required this.content,
    this.reminder = '',
    this.note = '',
    this.tags = const [],
    this.reading = '',
    this.hanViet = '',
    this.conjugation = '',
    this.examples = const [],
    this.sourceSentence = '',
    this.correctAnswer = '',
    this.mistake = '',
    this.warning = '',
    this.questionLabel = '',
    this.questionType = JlptQuestionType.other,
  });

  final String title;
  final WeaknessKind kind;
  final String content;
  final String reminder;
  final String note;
  final List<String> tags;
  final String reading;
  final String hanViet;
  final String conjugation;
  final List<String> examples;
  final String sourceSentence;
  final String correctAnswer;
  final String mistake;
  final String warning;

  /// Câu hỏi nguồn khi vùng khoanh chứa nhiều câu, ví dụ "Câu 2".
  final String questionLabel;
  final JlptQuestionType questionType;

  WeakPointDraft copyWith({
    String? reading,
    String? hanViet,
    String? warning,
  }) => WeakPointDraft(
    title: title,
    kind: kind,
    content: content,
    reminder: reminder,
    note: note,
    tags: tags,
    reading: reading ?? this.reading,
    hanViet: hanViet ?? this.hanViet,
    conjugation: conjugation,
    examples: examples,
    sourceSentence: sourceSentence,
    correctAnswer: correctAnswer,
    mistake: mistake,
    warning: warning ?? this.warning,
    questionLabel: questionLabel,
    questionType: questionType,
  );

  factory WeakPointDraft.fromJson(Map<String, dynamic> json) {
    String stringValue(String key) => (json[key]?.toString() ?? '').trim();
    List<String> stringList(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((value) {
              // Ví dụ có cấu trúc {japanese, meaning} được gộp thành một dòng
              // để vẫn sửa được trong ô "mỗi dòng một ví dụ".
              if (value is Map) {
                final japanese = (value['japanese'] ?? '').toString().trim();
                final meaning = (value['meaning'] ?? '').toString().trim();
                return [
                  japanese,
                  meaning,
                ].where((part) => part.isNotEmpty).join(' — ');
              }
              return value.toString().trim();
            })
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
    return WeakPointDraft(
      title: stringValue('title'),
      kind: weaknessKindFromName(
        (json['kind'] ?? json['type'] ?? 'other').toString(),
      ),
      content: stringValue('meaning').isNotEmpty
          ? stringValue('meaning')
          : stringValue('content'),
      reminder: stringValue('memoryTip').isNotEmpty
          ? stringValue('memoryTip')
          : stringValue('reminder'),
      note: stringValue('note'),
      tags: stringList('tags'),
      reading: stringValue('reading'),
      hanViet: stringValue('hanViet'),
      conjugation: stringValue('conjugation'),
      examples: stringList('examples'),
      sourceSentence: stringValue('sourceSentence'),
      correctAnswer: stringValue('correctAnswer'),
      mistake: stringValue('mistake'),
      warning: stringValue('uncertain'),
      questionLabel: stringValue('questionLabel'),
      questionType: jlptQuestionTypeFrom(stringValue('questionType')),
    );
  }
}

/// Một lựa chọn trong câu hỏi trắc nghiệm của Kiểm tra nhanh.
class QuickCheckChoice {
  const QuickCheckChoice({
    required this.label,
    required this.text,
    required this.correct,
    required this.reason,
  });

  final String label;
  final String text;
  final bool correct;
  final String reason;

  factory QuickCheckChoice.fromJson(Map<String, dynamic> json) =>
      QuickCheckChoice(
        label: (json['label'] ?? '').toString().trim(),
        text: (json['text'] ?? '').toString().trim(),
        correct: json['correct'] == true,
        reason: (json['reason'] ?? '').toString().trim(),
      );
}

/// Một câu hỏi AI đã giải. Người học chọn đáp án, app chấm tại chỗ.
class QuickCheckQuestion {
  const QuickCheckQuestion({
    required this.label,
    required this.stem,
    required this.choices,
    required this.answer,
    required this.explanation,
    required this.point,
    required this.kind,
    this.questionType = JlptQuestionType.other,
  });

  final String label;
  final String stem;
  final List<QuickCheckChoice> choices;

  /// Đáp án đúng dạng chữ (dùng cho câu tự luận/điền từ không có lựa chọn).
  final String answer;
  final String explanation;

  /// Điểm kiến thức câu hỏi kiểm tra, ví dụ 〜わけではない.
  final String point;
  final WeaknessKind kind;
  final JlptQuestionType questionType;

  int get correctIndex => choices.indexWhere((choice) => choice.correct);

  String get correctText {
    final index = correctIndex;
    if (index < 0) return answer;
    final choice = choices[index];
    return [
      choice.label,
      choice.text,
    ].where((part) => part.isNotEmpty).join('. ');
  }

  factory QuickCheckQuestion.fromJson(Map<String, dynamic> json) {
    final choices = (json['choices'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => QuickCheckChoice.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
    // Model đôi khi đánh dấu nhiều đáp án đúng; chỉ giữ lựa chọn đầu tiên để
    // việc chấm luôn xác định.
    var seenCorrect = false;
    final normalized = choices
        .map((choice) {
          if (!choice.correct) return choice;
          if (seenCorrect) {
            return QuickCheckChoice(
              label: choice.label,
              text: choice.text,
              correct: false,
              reason: choice.reason,
            );
          }
          seenCorrect = true;
          return choice;
        })
        .toList(growable: false);
    return QuickCheckQuestion(
      label: (json['label'] ?? '').toString().trim(),
      stem: (json['stem'] ?? '').toString().trim(),
      choices: normalized,
      answer: (json['answer'] ?? '').toString().trim(),
      explanation: (json['explanation'] ?? '').toString().trim(),
      point: (json['point'] ?? '').toString().trim(),
      kind: weaknessKindFromName(json['kind']?.toString()),
      questionType: jlptQuestionTypeFrom(json['questionType']?.toString()),
    );
  }
}

class QuickCheckResult {
  const QuickCheckResult({required this.questions, this.warning = ''});
  final List<QuickCheckQuestion> questions;
  final String warning;
}

class DictionaryEntry {
  const DictionaryEntry({
    required this.word,
    required this.reading,
    required this.meaning,
    required this.level,
    this.hanViet = '',
    this.partOfSpeech = '',
    this.example = '',
    this.exampleMeaning = '',
    this.similarEntries = const [],
  });
  final String word;
  final String reading;
  final String partOfSpeech;
  final String hanViet;
  final String meaning;
  final String level;
  final String example;
  final String exampleMeaning;
  final List<DictionaryEntry> similarEntries;
}

/// Một chữ kanji trong bảng `japanese_kanji` của từ điển ngoại tuyến.
class KanjiEntry {
  const KanjiEntry({
    required this.character,
    this.hanViet = '',
    this.onReading = '',
    this.kunReading = '',
    this.meaning = '',
    this.strokes,
    this.level = '',
  });

  final String character;

  /// Các âm Hán Việt viết hoa, âm chính đứng đầu: "HÀNH, HẠNH".
  final String hanViet;
  final String onReading;
  final String kunReading;
  final String meaning;
  final int? strokes;
  final String level;

  /// Âm Hán Việt chính (đầu tiên), dùng để ghép Hán Việt cho từ.
  String get primaryHanViet => hanViet.split(',').first.trim();
}

/// Các chữ kanji khác nhau trong [text], theo thứ tự xuất hiện.
List<String> kanjiCharacters(String text) => [
  ...{
    for (final rune in text.runes)
      if ((rune >= 0x4e00 && rune <= 0x9fff) ||
          (rune >= 0x3400 && rune <= 0x4dbf) ||
          rune == 0x3005)
        String.fromCharCode(rune),
  },
];

class OpenRouterModel {
  const OpenRouterModel({
    required this.id,
    required this.name,
    required this.contextLength,
    required this.vision,
    required this.free,
  });
  final String id;
  final String name;
  final int contextLength;
  final bool vision;
  final bool free;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'contextLength': contextLength,
    'vision': vision,
    'free': free,
  };

  factory OpenRouterModel.fromJson(Map<String, dynamic> json) =>
      OpenRouterModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? json['id'] as String? ?? 'Model',
        contextLength: (json['contextLength'] as num?)?.toInt() ?? 0,
        vision: json['vision'] as bool? ?? false,
        free: json['free'] as bool? ?? false,
      );
}
