import 'dart:ui';

enum AppDestination { library, weaknesses, dictionary, settings }

enum EditorTool {
  pen,
  highlighter,
  eraser,
  ruler,
  image,
  dictionary,
  quickDictionary,
  aiDictionary,
  translate,
  explain,
  weakness,
}

enum PaperStyle { blank, lined, grid, dotted, genkou }

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

/// Các ngăn model độc lập. Một OpenRouter API key có thể dùng nhiều model.
enum AiModelSlot { vision, translate, explain, solve, weakness, dictionary }

extension AiModelSlotLabel on AiModelSlot {
  String get label => switch (this) {
    AiModelSlot.vision => 'Nhận diện ảnh',
    AiModelSlot.translate => 'AI Dịch',
    AiModelSlot.explain => 'AI Giải thích',
    AiModelSlot.solve => 'AI Giải bài',
    AiModelSlot.weakness => 'Tạo điểm yếu',
    AiModelSlot.dictionary => 'AI Tra từ',
  };

  String get helper => switch (this) {
    AiModelSlot.vision => 'OCR bằng model Vision (tùy chọn, có thể tính phí)',
    AiModelSlot.translate => 'Dịch vùng chữ bạn đã khoanh',
    AiModelSlot.explain => 'Phân tích ngữ pháp và tách câu',
    AiModelSlot.solve => 'Giải câu hỏi trắc nghiệm',
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
  });

  final List<StrokePoint> points;
  final Color color;
  final double width;
  final EditorTool tool;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'points': points.map((point) => point.toJson()).toList(),
    'color': color.toARGB32(),
    'width': width,
    'tool': tool.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory InkStroke.fromJson(Map<String, dynamic> json) => InkStroke(
    points: (json['points'] as List)
        .map((item) => StrokePoint.fromJson(item as Map<String, dynamic>))
        .toList(),
    color: Color(json['color'] as int),
    width: (json['width'] as num).toDouble(),
    tool: EditorTool.values.byName(json['tool'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
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
  });

  final String id;
  String title;
  WeaknessKind kind;
  String content;
  String reminder;
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
  };

  factory WeakPoint.fromJson(Map<String, dynamic> json) => WeakPoint(
    id: json['id'] as String,
    title: json['title'] as String,
    kind: WeaknessKind.values.byName(json['kind'] as String),
    content: json['content'] as String,
    reminder: json['reminder'] as String,
    note: json['note'] as String,
    tags: List<String>.from(json['tags'] as List),
    notebookId: json['notebookId'] as String,
    notebookTitle: json['notebookTitle'] as String,
    page: json['page'] as int,
    ocrText: json['ocrText'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    sourceImagePath: json['sourceImagePath'] as String?,
    reading: json['reading'] as String? ?? '',
    hanViet: json['hanViet'] as String? ?? '',
    conjugation: json['conjugation'] as String? ?? '',
    examples: List<String>.from(json['examples'] as List? ?? const []),
    sourceSentence: json['sourceSentence'] as String? ?? '',
  );
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

  factory WeakPointDraft.fromJson(Map<String, dynamic> json) {
    final rawKind = (json['kind'] ?? json['type'] ?? 'other')
        .toString()
        .trim()
        .toLowerCase();
    final kind = switch (rawKind) {
      'grammar' || 'ngữ pháp' => WeaknessKind.grammar,
      'vocabulary' || 'vocab' || 'từ vựng' => WeaknessKind.vocabulary,
      'kanji' => WeaknessKind.kanji,
      'reading' || 'đọc hiểu' => WeaknessKind.reading,
      _ => WeaknessKind.other,
    };
    String stringValue(String key) => (json[key] as String? ?? '').trim();
    List<String> stringList(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
    return WeakPointDraft(
      title: stringValue('title'),
      kind: kind,
      content: stringValue('meaning').isNotEmpty
          ? stringValue('meaning')
          : stringValue('content'),
      reminder: stringValue('reminder'),
      note: stringValue('note'),
      tags: stringList('tags'),
      reading: stringValue('reading'),
      hanViet: stringValue('hanViet'),
      conjugation: stringValue('conjugation'),
      examples: stringList('examples'),
      sourceSentence: stringValue('sourceSentence'),
    );
  }
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
