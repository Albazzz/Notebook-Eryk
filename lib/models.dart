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
    this.paperStyle = PaperStyle.grid,
    this.paperLineOpacity = .09,
    this.lastOpened = 'Vừa xong',
  });

  final String id;
  final String title;
  final String type;
  final int pages;
  final Color color;
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
    PaperStyle? paperStyle,
    double? paperLineOpacity,
    String? lastOpened,
  }) => NotebookData(
    id: id,
    title: title ?? this.title,
    type: type ?? this.type,
    pages: pages ?? this.pages,
    color: color ?? this.color,
    paperStyle: paperStyle ?? this.paperStyle,
    paperLineOpacity: paperLineOpacity ?? this.paperLineOpacity,
    lastOpened: lastOpened ?? this.lastOpened,
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
  );
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
