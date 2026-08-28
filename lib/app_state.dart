import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services.dart';
import 'widgets/common.dart';

class AppState extends ChangeNotifier {
  static const _keyStorageName = 'openrouter_api_key';
  static const _modelIdsStorageName = 'ai_model_ids';
  static const _modelNamesStorageName = 'ai_model_names';
  static const _savedModelsStorageName = 'ai_saved_models';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final OpenRouterService aiService = OpenRouterService();
  final DictionaryRepository dictionary = LocalDictionaryRepository();
  final OcrService ocr = MlKitJapaneseOcrService();

  AppDestination destination = AppDestination.library;
  NotebookData? openNotebook;
  int openPage = 12;
  bool focusSource = false;
  ThemeMode themeMode = ThemeMode.light;
  bool autoSave = true;
  bool showSnackbars = true;
  bool pressureEnabled = true;
  bool palmRejection = true;
  bool doubleTapEraser = true;
  double paperLineOpacity = .09;
  String studentName = 'Eryk';
  String jlpt = 'N3';
  String explanationLanguage = 'Tiếng Việt';
  String selectedModelId = '';
  String selectedModelName = '';

  /// Per-feature model assignments. The same API key can use different models.
  final Map<AiModelSlot, String> modelIds = {};
  final Map<AiModelSlot, String> modelNames = {};
  List<OpenRouterModel> savedModels = [];
  bool useAiVision = false;
  bool aiConnected = false;
  List<OpenRouterModel> availableModels = [];
  String _apiKey = '';

  AppState() {
    configureAppSnackbars(showSnackbars);
  }

  @override
  void dispose() {
    aiService.dispose();
    super.dispose();
  }

  /// User-created notebooks only. The library starts empty on a fresh install.
  final List<NotebookData> notebooks = [];

  final Map<String, List<InkStroke>> strokes = {};
  final Map<String, List<PinnedNote>> pinnedNotes = {};

  /// Local images attached to a notebook page (page number -> file paths).
  final Map<String, Map<int, List<String>>> pageImages = {};
  final Map<String, PageImagePlacement> imagePlacements = {};
  int _imagePlacementSequence = 0;
  final Set<String> blankPages = {};
  final Map<String, String> sourceDocuments = {};
  List<WeakPoint> weakPoints = [];

  bool get hasApiKey => _apiKey.isNotEmpty;
  String get apiKey => _apiKey;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? 1];
    autoSave = prefs.getBool('autoSave') ?? true;
    showSnackbars = prefs.getBool('showSnackbars') ?? true;
    configureAppSnackbars(showSnackbars);
    pressureEnabled = prefs.getBool('pressureEnabled') ?? true;
    palmRejection = prefs.getBool('palmRejection') ?? true;
    doubleTapEraser = prefs.getBool('doubleTapEraser') ?? true;
    paperLineOpacity = (prefs.getDouble('paperLineOpacity') ?? .09).clamp(
      .03,
      .35,
    );
    studentName = prefs.getString('studentName') ?? 'Eryk';
    jlpt = prefs.getString('jlpt') ?? 'N3';
    explanationLanguage =
        prefs.getString('explanationLanguage') ?? 'Tiếng Việt';
    selectedModelId = prefs.getString('selectedModelId') ?? '';
    selectedModelName = prefs.getString('selectedModelName') ?? '';
    useAiVision = prefs.getBool('useAiVision') ?? false;
    _loadModelAssignments(prefs);
    try {
      _apiKey = await _secureStorage.read(key: _keyStorageName) ?? '';
    } catch (_) {
      _apiKey = '';
    }
    aiConnected = _apiKey.isNotEmpty && _hasTextAiModel;
    final savedWeakPoints = prefs.getString('weakPoints');
    if (savedWeakPoints != null) {
      try {
        weakPoints = (jsonDecode(savedWeakPoints) as List)
            .map((item) => WeakPoint.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {
        weakPoints = _seedWeakPoints();
      }
    } else {
      weakPoints = _seedWeakPoints();
    }
    final storedStrokes = prefs.getString('strokes');
    if (storedStrokes != null) {
      try {
        final decoded = jsonDecode(storedStrokes) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          // Older builds stored one stroke list per notebook. Preserve those
          // notes on the first page while using page-scoped keys from now on.
          final key = entry.key.contains(':') ? entry.key : '${entry.key}:1';
          strokes[key] = (entry.value as List)
              .map((item) => InkStroke.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }
    notifyListeners();
    debugPrint(
      '[NoteEryk][AppState] initialized destination=$destination '
      'openNotebook=${openNotebook?.id} hasKey=$hasApiKey '
      'configuredModels=${modelIds.length}',
    );
  }

  List<WeakPoint> _seedWeakPoints() => [
    WeakPoint(
      id: 'w1',
      title: 'わけではない / わけがない',
      kind: WeaknessKind.grammar,
      content: 'Phân biệt hai mẫu phủ định dễ nhầm.',
      reminder: 'Hay nhầm nghĩa hai mẫu này.',
      note: 'Ôn lại ví dụ vào cuối tuần.',
      tags: ['N3', 'dễ nhầm'],
      notebookId: 'n3',
      notebookTitle: 'N3 Grammar',
      page: 12,
      ocrText: '〜わけではない = không hẳn là / không có nghĩa là',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    WeakPoint(
      id: 'w2',
      title: '使役受身',
      kind: WeaknessKind.grammar,
      content: 'Cách chia thể sai khiến bị động.',
      reminder: 'Hay quên cách chia động từ nhóm I.',
      note: '',
      tags: ['N3'],
      notebookId: 'n3',
      notebookTitle: 'N3 Grammar',
      page: 18,
      ocrText: '使役受身',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    WeakPoint(
      id: 'w3',
      title: '認識【にんしき】',
      kind: WeaknessKind.vocabulary,
      content: 'Nhận thức, nhận biết.',
      reminder: 'Hay quên cách đọc にんしき.',
      note: '',
      tags: ['N2'],
      notebookId: 'soumatome',
      notebookTitle: 'Từ vựng Soumatome',
      page: 34,
      ocrText: '認識',
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
    WeakPoint(
      id: 'w4',
      title: '尊重【そんちょう】',
      kind: WeaknessKind.vocabulary,
      content: 'Tôn trọng, coi trọng.',
      reminder: 'Dễ nhầm với 重視.',
      note: '',
      tags: ['N3'],
      notebookId: 'shinkanzen',
      notebookTitle: 'Shinkanzen PDF',
      page: 12,
      ocrText: '彼の意見を尊重しながら、もう一度検討する必要がある。',
      createdAt: DateTime.now().subtract(const Duration(days: 8)),
    ),
  ];

  void goTo(AppDestination value) {
    debugPrint('[NoteEryk][Navigation] goTo $destination -> $value');
    destination = value;
    openNotebook = null;
    focusSource = false;
    notifyListeners();
  }

  void open(NotebookData notebook, {int page = 12, bool source = false}) {
    debugPrint(
      '[NoteEryk][Navigation] open notebook=${notebook.id} page=$page source=$source',
    );
    openNotebook = notebook;
    // A newly created notebook has one blank page. Clamp the requested page
    // so it can never open on a non-existent page (the old default of 12
    // made a one-page notebook appear to start at page 12).
    openPage = page.clamp(1, notebook.pages);
    focusSource = source;
    notifyListeners();
  }

  void goToPage(int page) {
    if (openNotebook == null) return;
    openPage = page.clamp(1, openNotebook!.pages);
    focusSource = false;
    debugPrint('[NoteEryk][Pages] goToPage $openPage');
    notifyListeners();
  }

  void closeEditor() {
    debugPrint('[NoteEryk][Navigation] closeEditor');
    openNotebook = null;
    focusSource = false;
    notifyListeners();
  }

  void addNotebook(NotebookData notebook) {
    notebooks.add(notebook);
    notifyListeners();
  }

  void updateNotebook(NotebookData notebook) {
    final index = notebooks.indexWhere((item) => item.id == notebook.id);
    if (index < 0) return;
    notebooks[index] = notebook;
    if (openNotebook?.id == notebook.id) openNotebook = notebook;
    notifyListeners();
  }

  void removeNotebook(String notebookId) {
    notebooks.removeWhere((item) => item.id == notebookId);
    strokes.removeWhere(
      (key, _) => key == notebookId || key.startsWith('$notebookId:'),
    );
    pinnedNotes.remove(notebookId);
    pageImages.remove(notebookId);
    imagePlacements.removeWhere(
      (_, value) => value.id.startsWith('$notebookId:'),
    );
    sourceDocuments.remove(notebookId);
    debugPrint('[NoteEryk][Library] removeNotebook $notebookId');
    notifyListeners();
  }

  void addPage(String notebookId, {bool blank = false}) {
    final index = notebooks.indexWhere((item) => item.id == notebookId);
    if (index < 0) return;
    final updated = notebooks[index].copyWith(
      pages: notebooks[index].pages + 1,
    );
    notebooks[index] = updated;
    if (openNotebook?.id == notebookId) {
      openNotebook = updated;
      openPage = updated.pages;
    }
    if (blank) blankPages.add('$notebookId:${updated.pages}');
    debugPrint(
      '[NoteEryk][Pages] addPage notebook=$notebookId page=${updated.pages} blank=$blank',
    );
    notifyListeners();
  }

  List<String> imagesForPage(String notebookId, int page) =>
      pageImages[notebookId]?[page] ?? const [];

  void attachImages(
    String notebookId,
    int page,
    List<String> paths, {
    bool asPageBackground = true,
  }) {
    if (paths.isEmpty) return;
    final pagePaths = pageImages
        .putIfAbsent(notebookId, () => {})
        .putIfAbsent(page, () => []);
    for (var index = 0; index < paths.length; index++) {
      final path = paths[index];
      if (!pagePaths.contains(path)) pagePaths.add(path);
      final id =
          '$notebookId:$page:${DateTime.now().microsecondsSinceEpoch}:${_imagePlacementSequence++}:$index';
      final rect = asPageBackground
          ? paths.length == 1
                ? const Rect.fromLTWH(0, 0, 1, 1)
                : Rect.fromLTWH(
                    .02,
                    index / paths.length + .01,
                    .96,
                    1 / paths.length - .02,
                  )
          : Rect.fromLTWH(
              (.14 + index * .04).clamp(.02, .5),
              (.16 + index * .04).clamp(.02, .5),
              .68,
              .46,
            );
      imagePlacements[id] = PageImagePlacement(
        id: id,
        path: path,
        rect: rect,
        isBackground: asPageBackground,
      );
    }
    notifyListeners();
  }

  List<PageImagePlacement> imagePlacementsForPage(String notebookId, int page) {
    final paths = imagesForPage(notebookId, page);
    return imagePlacements.values
        .where((item) => item.id.startsWith('$notebookId:$page:'))
        .where((item) => paths.contains(item.path))
        .toList();
  }

  void updateImagePlacement(PageImagePlacement placement) {
    if (!imagePlacements.containsKey(placement.id)) return;
    imagePlacements[placement.id] = placement;
    notifyListeners();
  }

  void replacePageImage(
    String notebookId,
    int page,
    PageImagePlacement placement,
    String newPath,
  ) {
    final paths = pageImages[notebookId]?[page];
    if (paths == null || !imagePlacements.containsKey(placement.id)) return;
    final pathIndex = paths.indexOf(placement.path);
    if (pathIndex >= 0) paths[pathIndex] = newPath;
    imagePlacements[placement.id] = placement.copyWith(path: newPath);
    notifyListeners();
  }

  void removePageImage(String notebookId, int page, String placementId) {
    final placement = imagePlacements.remove(placementId);
    if (placement == null) return;
    pageImages[notebookId]?[page]?.remove(placement.path);
    notifyListeners();
  }

  void attachSourceDocument(String notebookId, String path) {
    sourceDocuments[notebookId] = path;
    notifyListeners();
  }

  String _strokeKey(String notebookId, int page) => '$notebookId:$page';

  List<InkStroke> strokesFor(String notebookId, [int? page]) {
    final resolvedPage =
        page ?? (openNotebook?.id == notebookId ? openPage : 1);
    return strokes.putIfAbsent(_strokeKey(notebookId, resolvedPage), () => []);
  }

  void saveStrokes(String notebookId, List<InkStroke> value, [int? page]) {
    final resolvedPage =
        page ?? (openNotebook?.id == notebookId ? openPage : 1);
    strokes[_strokeKey(notebookId, resolvedPage)] = List.of(value);
    notifyListeners();
    if (autoSave) _persistStrokes();
  }

  Future<void> _persistStrokes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'strokes',
      jsonEncode(
        strokes.map(
          (key, value) =>
              MapEntry(key, value.map((stroke) => stroke.toJson()).toList()),
        ),
      ),
    );
  }

  void pinNote(String notebookId, PinnedNote note) {
    pinnedNotes.putIfAbsent(notebookId, () => []).add(note);
    notifyListeners();
  }

  void addWeakPoint(WeakPoint weakPoint) {
    weakPoints.insert(0, weakPoint);
    notifyListeners();
    _persistWeakPoints();
  }

  void updateWeakPoint(WeakPoint weakPoint) {
    final index = weakPoints.indexWhere((item) => item.id == weakPoint.id);
    if (index >= 0) weakPoints[index] = weakPoint;
    notifyListeners();
    _persistWeakPoints();
  }

  void deleteWeakPoint(String id) {
    final sourcePath = weakPoints
        .where((item) => item.id == id)
        .map((item) => item.sourceImagePath)
        .firstOrNull;
    weakPoints.removeWhere((item) => item.id == id);
    if (sourcePath != null && sourcePath.isNotEmpty) {
      File(sourcePath).delete().catchError((_) => File(sourcePath));
    }
    notifyListeners();
    _persistWeakPoints();
  }

  Future<void> _persistWeakPoints() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'weakPoints',
      jsonEncode(weakPoints.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> saveGeneralSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', themeMode.index);
    await prefs.setBool('autoSave', autoSave);
    await prefs.setBool('showSnackbars', showSnackbars);
    await prefs.setBool('pressureEnabled', pressureEnabled);
    await prefs.setBool('palmRejection', palmRejection);
    await prefs.setBool('doubleTapEraser', doubleTapEraser);
    await prefs.setDouble('paperLineOpacity', paperLineOpacity);
    await prefs.setString(
      'studentName',
      studentName.trim().isEmpty ? 'Eryk' : studentName.trim(),
    );
    await prefs.setString('jlpt', jlpt);
    notifyListeners();
  }

  Future<void> saveAiSettings({required String key}) async {
    if (key.isNotEmpty && key != _apiKey) {
      await _secureStorage.write(key: _keyStorageName, value: key);
      _apiKey = key;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jlpt', jlpt);
    await prefs.setString('explanationLanguage', explanationLanguage);
    await prefs.setString('selectedModelId', selectedModelId);
    await prefs.setString('selectedModelName', selectedModelName);
    await prefs.setBool('useAiVision', useAiVision);
    await prefs.setString(
      _modelIdsStorageName,
      jsonEncode(modelIds.map((slot, value) => MapEntry(slot.name, value))),
    );
    await prefs.setString(
      _modelNamesStorageName,
      jsonEncode(modelNames.map((slot, value) => MapEntry(slot.name, value))),
    );
    await prefs.setString(
      _savedModelsStorageName,
      jsonEncode(savedModels.map((model) => model.toJson()).toList()),
    );
    aiConnected = _apiKey.isNotEmpty && _hasTextAiModel;
    notifyListeners();
  }

  void _loadModelAssignments(SharedPreferences prefs) {
    modelIds.clear();
    modelNames.clear();
    final ids = _decodeStringMap(prefs.getString(_modelIdsStorageName));
    final names = _decodeStringMap(prefs.getString(_modelNamesStorageName));
    for (final slot in AiModelSlot.values) {
      final id = ids[slot.name] ?? '';
      if (id.isNotEmpty) modelIds[slot] = id;
      final name = names[slot.name] ?? '';
      if (name.isNotEmpty) modelNames[slot] = name;
    }
    // Migrate the old single-model setting to every compatible slot.
    if (modelIds.isEmpty && selectedModelId.isNotEmpty) {
      for (final slot in AiModelSlot.values) {
        modelIds[slot] = selectedModelId;
        modelNames[slot] = selectedModelName;
      }
    }
    final rawSaved = prefs.getString(_savedModelsStorageName);
    if (rawSaved != null) {
      try {
        savedModels = (jsonDecode(rawSaved) as List)
            .map(
              (item) => OpenRouterModel.fromJson(item as Map<String, dynamic>),
            )
            .where((model) => model.id.isNotEmpty)
            .toList();
      } catch (_) {
        savedModels = [];
      }
    }
  }

  Map<String, String> _decodeStringMap(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return {};
    }
  }

  AiModelSlot slotForTask(AiTask task) => switch (task) {
    AiTask.translate => AiModelSlot.translate,
    AiTask.explain => AiModelSlot.explain,
    AiTask.solve => AiModelSlot.solve,
    AiTask.createWeakPoint => AiModelSlot.weakness,
    AiTask.dictionary => AiModelSlot.dictionary,
  };

  bool get _hasTextAiModel =>
      [
        AiModelSlot.translate,
        AiModelSlot.explain,
        AiModelSlot.solve,
        AiModelSlot.weakness,
        AiModelSlot.dictionary,
      ].any((slot) => (modelIds[slot] ?? '').isNotEmpty) ||
      selectedModelId.isNotEmpty;

  String modelIdFor(AiTask task) =>
      modelIds[slotForTask(task)] ?? selectedModelId;

  String modelNameFor(AiModelSlot slot) =>
      modelNames[slot] ??
      (slot == AiModelSlot.translate ? selectedModelName : '');

  void setModelFor(AiModelSlot slot, OpenRouterModel model) {
    modelIds[slot] = model.id;
    modelNames[slot] = model.name;
    if (slot == AiModelSlot.translate) {
      selectedModelId = model.id;
      selectedModelName = model.name;
    }
    if (!savedModels.any((item) => item.id == model.id)) {
      savedModels = [model, ...savedModels].take(40).toList();
    }
  }

  void setModelForSlots(Iterable<AiModelSlot> slots, OpenRouterModel model) {
    for (final slot in slots) {
      setModelFor(slot, model);
    }
    notifyListeners();
  }

  Future<void> rememberManualModel(
    String id, {
    String? name,
    bool vision = false,
  }) async {
    final normalized = id.trim();
    if (normalized.isEmpty) return;
    final model = OpenRouterModel(
      id: normalized,
      name: name?.trim().isNotEmpty == true ? name!.trim() : normalized,
      contextLength: 0,
      vision: vision,
      free: normalized.endsWith(':free'),
    );
    if (!savedModels.any((item) => item.id == normalized)) {
      savedModels = [model, ...savedModels].take(40).toList();
    }
    await saveAiSettings(key: '');
  }

  Future<void> deleteApiKey() async {
    await _secureStorage.delete(key: _keyStorageName);
    _apiKey = '';
    aiConnected = false;
    selectedModelId = '';
    selectedModelName = '';
    modelIds.clear();
    modelNames.clear();
    availableModels = [];
    await saveAiSettings(key: '');
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    saveGeneralSettings();
  }

  void setPaperLineOpacity(double value) {
    paperLineOpacity = value.clamp(.03, .35);
    notifyListeners();
    saveGeneralSettings();
  }

  void setShowSnackbars(bool value) {
    showSnackbars = value;
    configureAppSnackbars(value);
    notifyListeners();
    saveGeneralSettings();
  }
}
