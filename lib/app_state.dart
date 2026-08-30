import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services.dart';
import 'widgets/common.dart';

class AppState extends ChangeNotifier {
  static const _keyStorageName = 'openrouter_api_key';
  static const _modelIdsStorageName = 'ai_model_ids';
  static const _modelNamesStorageName = 'ai_model_names';
  static const _savedModelsStorageName = 'ai_saved_models';
  static const _libraryStorageName = 'notebook_library_v2';
  static const _backupDirectoryName = 'Backups';
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
  bool drawWithFinger = false;
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
  final List<FolderData> folders = [];
  String? selectedFolderId;
  String librarySection = 'all';
  String folderSearchQuery = '';
  VoidCallback? _folderUndo;

  final Map<String, List<InkStroke>> strokes = {};
  final Map<String, List<PinnedNote>> pinnedNotes = {};

  /// Local images attached to a notebook page (page number -> file paths).
  final Map<String, Map<int, List<String>>> pageImages = {};
  final Map<String, PageImagePlacement> imagePlacements = {};
  int _imagePlacementSequence = 0;
  final Set<String> blankPages = {};
  final Map<String, String> sourceDocuments = {};
  List<WeakPoint> weakPoints = [];
  Future<void>? _persistenceInFlight;
  bool _persistenceScheduled = false;
  bool _storageReady = false;

  bool get hasApiKey => _apiKey.isNotEmpty;
  String get apiKey => _apiKey;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? 1];
    autoSave = prefs.getBool('autoSave') ?? true;
    showSnackbars = prefs.getBool('showSnackbars') ?? true;
    configureAppSnackbars(showSnackbars);
    pressureEnabled = prefs.getBool('pressureEnabled') ?? true;
    drawWithFinger = prefs.getBool('drawWithFinger') ?? false;
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
    await _loadLibrary(prefs);
    _storageReady = true;
    notifyListeners();
    debugPrint(
      '[NoteEryk][AppState] initialized destination=$destination '
      'openNotebook=${openNotebook?.id} hasKey=$hasApiKey '
      'configuredModels=${modelIds.length}',
    );
  }

  Future<void> _loadLibrary(SharedPreferences prefs) async {
    String? fileRaw;
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/notebook_library_v2.json');
      if (await file.exists()) fileRaw = await file.readAsString();
    } catch (error) {
      debugPrint('[NoteEryk][Storage] library file read failed: $error');
    }
    final preferenceRaw = prefs.getString(_libraryStorageName);
    final candidates = <(String, String?)>[
      ('file', fileRaw),
      if (preferenceRaw != fileRaw) ('preferences', preferenceRaw),
    ];
    for (final (source, raw) in candidates) {
      if (raw == null || raw.isEmpty) continue;
      try {
        _applyLibrarySnapshot(jsonDecode(raw) as Map<String, dynamic>);
        return;
      } catch (error) {
        debugPrint('[NoteEryk][Storage] $source library load failed: $error');
      }
    }
  }

  void _applyLibrarySnapshot(Map<String, dynamic> data) {
    // Decode into temporary values first. A corrupt attachment/page entry must
    // not leave half of the in-memory library replaced before we try the
    // SharedPreferences mirror.
    final parsedNotebooks = (data['notebooks'] as List?)
        ?.map((item) => NotebookData.fromJson(item as Map<String, dynamic>))
        .toList();
    final parsedFolders = (data['folders'] as List?)
        ?.map((item) => FolderData.fromJson(item as Map<String, dynamic>))
        .toList();
    final parsedPinned = (data['pinnedNotes'] as Map<String, dynamic>?)?.map(
      (key, value) => MapEntry(
        key,
        (value as List)
            .map((item) => PinnedNote.fromJson(item as Map<String, dynamic>))
            .toList(),
      ),
    );
    final parsedImages = (data['pageImages'] as Map<String, dynamic>?)?.map(
      (notebookId, pages) => MapEntry(
        notebookId,
        (pages as Map<String, dynamic>).map(
          (page, paths) =>
              MapEntry(int.parse(page), List<String>.from(paths as List)),
        ),
      ),
    );
    final parsedPlacements = (data['imagePlacements'] as Map<String, dynamic>?)
        ?.map(
          (key, value) => MapEntry(
            key,
            PageImagePlacement.fromJson(value as Map<String, dynamic>),
          ),
        );
    final parsedBlankPages = List<String>.from(
      data['blankPages'] as List? ?? const [],
    );
    final parsedDocuments = Map<String, String>.from(
      data['sourceDocuments'] as Map? ?? {},
    );
    final parsedWeakPoints = (data['weakPoints'] as List?)
        ?.map((item) => WeakPoint.fromJson(item as Map<String, dynamic>))
        .toList();
    final parsedStrokes = (data['strokes'] as Map<String, dynamic>?)?.map(
      (key, value) => MapEntry(
        key,
        (value as List)
            .map((item) => InkStroke.fromJson(item as Map<String, dynamic>))
            .toList(),
      ),
    );

    if (parsedNotebooks != null) {
      notebooks
        ..clear()
        ..addAll(parsedNotebooks);
    }
    if (parsedFolders != null) {
      folders
        ..clear()
        ..addAll(parsedFolders);
    }
    if (parsedPinned != null) {
      pinnedNotes
        ..clear()
        ..addAll(parsedPinned);
    }
    if (parsedImages != null) {
      pageImages
        ..clear()
        ..addAll(parsedImages);
    }
    if (parsedPlacements != null) {
      imagePlacements
        ..clear()
        ..addAll(parsedPlacements);
    }
    blankPages
      ..clear()
      ..addAll(parsedBlankPages);
    sourceDocuments
      ..clear()
      ..addAll(parsedDocuments);
    if (parsedWeakPoints != null) {
      weakPoints = parsedWeakPoints;
    }
    if (parsedStrokes != null) {
      strokes
        ..clear()
        ..addAll(parsedStrokes);
    }
  }

  Map<String, Object?> _librarySnapshot() => {
    'version': 2,
    'updatedAt': DateTime.now().toIso8601String(),
    'notebooks': notebooks.map((item) => item.toJson()).toList(),
    'folders': folders.map((item) => item.toJson()).toList(),
    'strokes': strokes.map(
      (key, value) =>
          MapEntry(key, value.map((stroke) => stroke.toJson()).toList()),
    ),
    'pinnedNotes': pinnedNotes.map(
      (key, value) =>
          MapEntry(key, value.map((note) => note.toJson()).toList()),
    ),
    'pageImages': pageImages.map(
      (notebookId, pages) => MapEntry(
        notebookId,
        pages.map((page, paths) => MapEntry(page.toString(), paths)),
      ),
    ),
    'imagePlacements': imagePlacements.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'blankPages': blankPages.toList(),
    'sourceDocuments': sourceDocuments,
    'weakPoints': weakPoints.map((item) => item.toJson()).toList(),
  };

  void schedulePersistence() {
    if (!autoSave || !_storageReady) return;
    if (_persistenceScheduled) return;
    _persistenceScheduled = true;
    scheduleMicrotask(() {
      _persistenceScheduled = false;
      unawaited(_flushScheduledPersistence());
    });
  }

  Future<void> _flushScheduledPersistence() async {
    try {
      await flushPersistence();
    } catch (error, stackTrace) {
      debugPrint('[NoteEryk][Storage] autosave failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> flushPersistence({bool snapshot = false}) async {
    if (!_storageReady) return;
    final running = _persistenceInFlight;
    if (running != null) {
      try {
        await running;
      } catch (_) {
        // Retry below with the newest in-memory snapshot. The earlier caller
        // already reports its own failure.
      }
    }
    final operation = _persistLibrary();
    _persistenceInFlight = operation;
    try {
      await operation;
      if (snapshot) await exportBackupSnapshot();
    } finally {
      if (identical(_persistenceInFlight, operation)) {
        _persistenceInFlight = null;
      }
      if (_persistenceScheduled) schedulePersistence();
    }
  }

  Future<void> _persistLibrary() async {
    final encoded = jsonEncode(_librarySnapshot());
    final directory = await getApplicationSupportDirectory();
    final target = File('${directory.path}/notebook_library_v2.json');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_libraryStorageName, encoded);
    } catch (error) {
      debugPrint('[NoteEryk][Storage] preferences mirror failed: $error');
    }
  }

  Future<File> exportBackupSnapshot() async {
    final documents = await getApplicationDocumentsDirectory();
    final backups = Directory('${documents.path}/$_backupDirectoryName');
    await backups.create(recursive: true);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final target = File('${backups.path}/NoteEryk-$stamp.noteeryk');
    final temporaryTarget = File('${target.path}.tmp');
    final snapshot = _librarySnapshot();
    final attachments = <String, String>{};
    final attachmentFiles = <({String source, String archiveName})>[];
    var attachmentIndex = 0;
    for (final sourcePath in _attachmentPaths().toSet()) {
      final source = File(sourcePath);
      if (!await source.exists()) continue;
      final filename = source.uri.pathSegments.last;
      final targetName = '${attachmentIndex++}_$filename';
      final archiveName = 'Files/$targetName';
      attachments[sourcePath] = archiveName;
      attachmentFiles.add((source: sourcePath, archiveName: archiveName));
    }
    snapshot['attachments'] = attachments;
    final manifest = File('${backups.path}/.NoteEryk-$stamp.manifest.tmp');
    await manifest.writeAsString(
      jsonEncode({
        'format': 'note-eryk-backup',
        'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
        ...snapshot,
      }),
      flush: true,
    );
    if (await temporaryTarget.exists()) await temporaryTarget.delete();
    final encoder = ZipFileEncoder();
    encoder.create(temporaryTarget.path);
    await encoder.addFile(manifest, 'manifest.json');
    for (final entry in attachmentFiles) {
      await encoder.addFile(File(entry.source), entry.archiveName);
    }
    await encoder.close();
    await manifest.delete();
    await temporaryTarget.rename(target.path);
    final snapshots =
        backups
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.noteeryk'))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
    for (final old in snapshots.skip(5)) {
      await old.delete();
    }
    return target;
  }

  Iterable<String> _attachmentPaths() sync* {
    for (final pages in pageImages.values) {
      for (final paths in pages.values) {
        yield* paths;
      }
    }
    yield* sourceDocuments.values;
    for (final point in weakPoints) {
      final path = point.sourceImagePath;
      if (path != null && path.isNotEmpty) yield path;
    }
  }

  Future<bool> importBackupFile(String path) async {
    try {
      final input = File(path);
      final isArchive = path.toLowerCase().endsWith('.noteeryk');
      Archive? archive;
      Map<String, dynamic> data;
      if (isArchive) {
        archive = ZipDecoder().decodeBytes(await input.readAsBytes());
        final manifest = archive.findFile('manifest.json');
        if (manifest == null) return false;
        data =
            jsonDecode(utf8.decode(manifest.readBytes() ?? const []))
                as Map<String, dynamic>;
      } else {
        data = jsonDecode(await input.readAsString()) as Map<String, dynamic>;
      }
      if (data['format'] != 'note-eryk-backup' || data['version'] != 1) {
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      final library = Map<String, dynamic>.from(data)
        ..remove('format')
        ..remove('createdAt')
        ..remove('attachments');
      final attachments = Map<String, dynamic>.from(
        data['attachments'] as Map? ?? const {},
      );
      if (attachments.isNotEmpty) {
        final restoreDirectory = Directory(
          '${(await getApplicationSupportDirectory()).path}/imports/restored_${DateTime.now().microsecondsSinceEpoch}',
        );
        await restoreDirectory.create(recursive: true);
        final restoredPaths = <String, String>{};
        for (final entry in attachments.entries) {
          final relative = entry.value as String;
          if (archive != null) {
            final archived = archive.findFile(relative);
            final bytes = archived?.readBytes();
            if (bytes == null) continue;
            final destination = File(
              '${restoreDirectory.path}/${relative.split('/').last}',
            );
            await destination.writeAsBytes(bytes, flush: true);
            restoredPaths[entry.key] = destination.path;
          } else {
            final source = File('${input.parent.path}/$relative');
            if (!await source.exists()) continue;
            final destination = await source.copy(
              '${restoreDirectory.path}/${source.uri.pathSegments.last}',
            );
            restoredPaths[entry.key] = destination.path;
          }
        }
        _replaceBackupPaths(library, restoredPaths);
      }
      await prefs.setString(_libraryStorageName, jsonEncode(library));
      try {
        final directory = await getApplicationSupportDirectory();
        final existing = File('${directory.path}/notebook_library_v2.json');
        if (await existing.exists()) await existing.delete();
      } catch (_) {}
      await _loadLibrary(prefs);
      await flushPersistence();
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('[NoteEryk][Storage] backup import failed: $error');
      return false;
    }
  }

  void _replaceBackupPaths(
    Map<String, dynamic> library,
    Map<String, String> replacements,
  ) {
    final images = library['pageImages'] as Map<String, dynamic>?;
    images?.forEach((_, pages) {
      (pages as Map<String, dynamic>).forEach((_, paths) {
        final list = paths as List;
        for (var index = 0; index < list.length; index++) {
          list[index] = replacements[list[index]] ?? list[index];
        }
      });
    });
    final placements = library['imagePlacements'] as Map<String, dynamic>?;
    placements?.forEach((_, value) {
      final placement = value as Map<String, dynamic>;
      final path = placement['path'];
      if (path is String && replacements.containsKey(path)) {
        placement['path'] = replacements[path];
      }
    });
    final documents = library['sourceDocuments'] as Map<String, dynamic>?;
    documents?.forEach((key, value) {
      if (value is String && replacements.containsKey(value)) {
        documents[key] = replacements[value];
      }
    });
    final points = library['weakPoints'] as List?;
    points?.forEach((item) {
      final point = item as Map<String, dynamic>;
      final path = point['sourceImagePath'];
      if (path is String && replacements.containsKey(path)) {
        point['sourceImagePath'] = replacements[path];
      }
    });
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
    schedulePersistence();
  }

  bool get canUndoFolderAction => _folderUndo != null;

  void undoFolderAction() {
    final undo = _folderUndo;
    _folderUndo = null;
    undo?.call();
    if (undo != null) {
      notifyListeners();
      schedulePersistence();
    }
  }

  void _captureFolderUndo() {
    final oldFolders = List<FolderData>.of(folders);
    final oldNotebooks = List<NotebookData>.of(notebooks);
    _folderUndo = () {
      folders
        ..clear()
        ..addAll(oldFolders);
      notebooks
        ..clear()
        ..addAll(oldNotebooks);
    };
  }

  FolderData? folderById(String? id) => id == null
      ? null
      : folders
            .where((folder) => folder.id == id && !folder.isTrashed)
            .firstOrNull;

  List<FolderData> childFolders(String? parentId) {
    final children = folders
        .where((folder) => folder.parentId == parentId && !folder.isTrashed)
        .toList();
    children.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return children;
  }

  Set<String> folderTreeIds(String folderId) {
    final ids = <String>{folderId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final folder in folders) {
        if (folder.parentId != null &&
            ids.contains(folder.parentId) &&
            ids.add(folder.id)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  int folderNoteCount(String? folderId) {
    if (folderId == null) {
      return notebooks.where((note) => !note.isTrashed).length;
    }
    final ids = folderTreeIds(folderId);
    return notebooks
        .where((note) => !note.isTrashed && ids.contains(note.folderId))
        .length;
  }

  List<NotebookData> notesInFolder(String? folderId) {
    final ids = folderId == null ? null : folderTreeIds(folderId);
    return notebooks
        .where(
          (note) =>
              !note.isTrashed && (ids == null || ids.contains(note.folderId)),
        )
        .toList();
  }

  List<NotebookData> favoriteNotes() {
    final pinnedFolders = folders
        .where((folder) => folder.isPinned && !folder.isTrashed)
        .map((folder) => folder.id)
        .toSet();
    return notebooks
        .where(
          (note) =>
              !note.isTrashed &&
              (note.isPinned ||
                  (note.folderId != null &&
                      pinnedFolders.any(
                        (folderId) =>
                            folderTreeIds(folderId).contains(note.folderId),
                      ))),
        )
        .toList();
  }

  void selectFolder(String? folderId) {
    selectedFolderId = folderId;
    librarySection = 'all';
    if (openNotebook != null) openNotebook = null;
    destination = AppDestination.library;
    notifyListeners();
  }

  void selectLibrarySection(String section) {
    librarySection = section;
    selectedFolderId = null;
    if (openNotebook != null) openNotebook = null;
    destination = AppDestination.library;
    notifyListeners();
  }

  void setFolderSearchQuery(String value) {
    folderSearchQuery = value;
    notifyListeners();
  }

  void createFolder(String name, {String? parentId}) {
    final clean = name.trim();
    if (clean.isEmpty || (parentId != null && folderById(parentId) == null)) {
      return;
    }
    _captureFolderUndo();
    folders.add(
      FolderData(id: _nextFolderId(), name: clean, parentId: parentId),
    );
    notifyListeners();
    schedulePersistence();
  }

  String _nextFolderId() {
    final base = 'folder_${DateTime.now().microsecondsSinceEpoch}';
    var candidate = base;
    var suffix = 1;
    while (folders.any((folder) => folder.id == candidate)) {
      candidate = '${base}_${suffix++}';
    }
    return candidate;
  }

  void renameFolder(String id, String name) {
    final clean = name.trim();
    final index = folders.indexWhere((folder) => folder.id == id);
    if (index < 0 || clean.isEmpty) return;
    _captureFolderUndo();
    folders[index] = folders[index].copyWith(name: clean);
    notifyListeners();
    schedulePersistence();
  }

  void updateFolderAppearance(String id, {int? color, int? iconCodePoint}) {
    final index = folders.indexWhere((folder) => folder.id == id);
    if (index < 0) return;
    _captureFolderUndo();
    folders[index] = folders[index].copyWith(
      color: color,
      iconCodePoint: iconCodePoint,
    );
    notifyListeners();
    schedulePersistence();
  }

  void toggleFolderExpanded(String id) {
    final index = folders.indexWhere((folder) => folder.id == id);
    if (index < 0) return;
    folders[index] = folders[index].copyWith(
      isExpanded: !folders[index].isExpanded,
    );
    notifyListeners();
    schedulePersistence();
  }

  void pinFolder(String id) {
    final index = folders.indexWhere((folder) => folder.id == id);
    if (index < 0) return;
    _captureFolderUndo();
    folders[index] = folders[index].copyWith(
      isPinned: !folders[index].isPinned,
    );
    notifyListeners();
    schedulePersistence();
  }

  bool moveFolder(String id, String? parentId) {
    final index = folders.indexWhere((folder) => folder.id == id);
    if (index < 0 || id == parentId) return false;
    if (folders[index].isTrashed || folders[index].parentId == parentId) {
      return false;
    }
    if (parentId != null && folderById(parentId) == null) {
      return false;
    }
    if (parentId != null && folderTreeIds(id).contains(parentId)) return false;
    _captureFolderUndo();
    folders[index] = parentId == null
        ? folders[index].copyWith(clearParent: true)
        : folders[index].copyWith(parentId: parentId);
    notifyListeners();
    schedulePersistence();
    return true;
  }

  bool moveNotebookToFolder(String notebookId, String? folderId) {
    final index = notebooks.indexWhere((note) => note.id == notebookId);
    if (index < 0 || (folderId != null && folderById(folderId) == null)) {
      return false;
    }
    if (notebooks[index].isTrashed || notebooks[index].folderId == folderId) {
      return false;
    }
    _captureFolderUndo();
    notebooks[index] = folderId == null
        ? notebooks[index].copyWith(clearFolder: true)
        : notebooks[index].copyWith(folderId: folderId);
    if (openNotebook?.id == notebookId) openNotebook = notebooks[index];
    notifyListeners();
    schedulePersistence();
    return true;
  }

  bool moveNotebooksToFolder(Iterable<String> notebookIds, String? folderId) {
    final ids = notebookIds.toSet();
    if (ids.isEmpty ||
        (folderId != null && folderById(folderId) == null) ||
        !notebooks.any(
          (note) =>
              ids.contains(note.id) &&
              !note.isTrashed &&
              note.folderId != folderId,
        )) {
      return false;
    }
    _captureFolderUndo();
    for (var index = 0; index < notebooks.length; index++) {
      if (!ids.contains(notebooks[index].id) ||
          notebooks[index].isTrashed ||
          notebooks[index].folderId == folderId) {
        continue;
      }
      notebooks[index] = folderId == null
          ? notebooks[index].copyWith(clearFolder: true)
          : notebooks[index].copyWith(folderId: folderId);
    }
    final openId = openNotebook?.id;
    if (openId != null && ids.contains(openId)) {
      openNotebook = notebooks.where((note) => note.id == openId).firstOrNull;
    }
    notifyListeners();
    schedulePersistence();
    return true;
  }

  void pinNotebook(String notebookId) {
    final index = notebooks.indexWhere((note) => note.id == notebookId);
    if (index < 0) return;
    _captureFolderUndo();
    notebooks[index] = notebooks[index].copyWith(
      isPinned: !notebooks[index].isPinned,
    );
    if (openNotebook?.id == notebookId) openNotebook = notebooks[index];
    notifyListeners();
    schedulePersistence();
  }

  /// Updates content tags without changing the notebook's single folder
  /// location. Tags are kept as a de-duplicated, trimmed list.
  void setNotebookTags(String notebookId, Iterable<String> values) {
    final index = notebooks.indexWhere((note) => note.id == notebookId);
    if (index < 0) return;
    final tags = <String>{
      for (final value in values)
        if (value.trim().isNotEmpty) value.trim(),
    }.toList();
    _captureFolderUndo();
    notebooks[index] = notebooks[index].copyWith(tags: tags);
    if (openNotebook?.id == notebookId) openNotebook = notebooks[index];
    notifyListeners();
    schedulePersistence();
  }

  void deleteFolder(String id, {required bool moveToTrash}) {
    final folder = folderById(id);
    if (folder == null) return;
    _captureFolderUndo();
    final ids = folderTreeIds(id);
    if (moveToTrash) {
      for (var index = 0; index < notebooks.length; index++) {
        if (ids.contains(notebooks[index].folderId)) {
          notebooks[index] = notebooks[index].copyWith(isTrashed: true);
        }
      }
      for (var index = 0; index < folders.length; index++) {
        if (ids.contains(folders[index].id)) {
          folders[index] = folders[index].copyWith(isTrashed: true);
        }
      }
    } else {
      final parentId = folder.parentId;
      for (var index = 0; index < notebooks.length; index++) {
        if (ids.contains(notebooks[index].folderId)) {
          notebooks[index] = parentId == null
              ? notebooks[index].copyWith(clearFolder: true)
              : notebooks[index].copyWith(folderId: parentId);
        }
      }
      folders.removeWhere((item) => ids.contains(item.id));
    }
    if (selectedFolderId != null && ids.contains(selectedFolderId)) {
      selectedFolderId = folder.parentId;
    }
    final openId = openNotebook?.id;
    if (openId != null) {
      openNotebook = notebooks.where((note) => note.id == openId).firstOrNull;
    }
    notifyListeners();
    schedulePersistence();
  }

  void updateNotebook(NotebookData notebook) {
    final index = notebooks.indexWhere((item) => item.id == notebook.id);
    if (index < 0) return;
    notebooks[index] = notebook;
    if (openNotebook?.id == notebook.id) openNotebook = notebook;
    notifyListeners();
    schedulePersistence();
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
    schedulePersistence();
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
    schedulePersistence();
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
    schedulePersistence();
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
    schedulePersistence();
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
    schedulePersistence();
  }

  void removePageImage(String notebookId, int page, String placementId) {
    final placement = imagePlacements.remove(placementId);
    if (placement == null) return;
    pageImages[notebookId]?[page]?.remove(placement.path);
    notifyListeners();
    schedulePersistence();
  }

  void attachSourceDocument(String notebookId, String path) {
    sourceDocuments[notebookId] = path;
    notifyListeners();
    schedulePersistence();
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
    if (autoSave) {
      _persistStrokes();
      schedulePersistence();
    }
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
    schedulePersistence();
  }

  void addWeakPoint(WeakPoint weakPoint) {
    weakPoints.insert(0, weakPoint);
    notifyListeners();
    _persistWeakPoints();
    schedulePersistence();
  }

  void updateWeakPoint(WeakPoint weakPoint) {
    final index = weakPoints.indexWhere((item) => item.id == weakPoint.id);
    if (index >= 0) weakPoints[index] = weakPoint;
    notifyListeners();
    _persistWeakPoints();
    schedulePersistence();
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
    schedulePersistence();
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
    await prefs.setBool('drawWithFinger', drawWithFinger);
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
