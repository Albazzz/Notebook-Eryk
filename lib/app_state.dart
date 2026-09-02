import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services.dart';
import 'widgets/common.dart';

class AppState extends ChangeNotifier {
  static const defaultAiModelId = 'openai/gpt-5.6-luna';
  static const defaultAiModelName = 'GPT-5.6 Luna';
  static const defaultToolbarTools = <EditorTool>[
    EditorTool.pen,
    EditorTool.highlighter,
    EditorTool.eraser,
    EditorTool.ruler,
    EditorTool.image,
    EditorTool.dictionary,
    EditorTool.quickDictionary,
    EditorTool.aiDictionary,
    EditorTool.translate,
    EditorTool.explain,
    EditorTool.weakness,
  ];
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
  int openPage = 1;
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
  String selectedModelId = defaultAiModelId;
  String selectedModelName = defaultAiModelName;

  /// Per-feature model assignments. The same API key can use different models.
  final Map<AiModelSlot, String> modelIds = {};
  final Map<AiModelSlot, String> modelNames = {};
  List<OpenRouterModel> savedModels = [];
  bool useAiVision = false;
  bool aiConnected = false;
  List<OpenRouterModel> availableModels = [];
  List<EditorTool> toolbarTools = List.of(defaultToolbarTools);
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
  final Map<String, int> lastPages = {};

  /// Local images attached to a notebook page (page number -> file paths).
  final Map<String, Map<int, List<String>>> pageImages = {};
  final Map<String, PageImagePlacement> imagePlacements = {};
  int _imagePlacementSequence = 0;
  final Set<String> blankPages = {};
  final Map<String, String> sourceDocuments = {};
  List<WeakPoint> weakPoints = [];
  Future<void>? _persistenceInFlight;
  Future<File>? _backupInFlight;
  bool _persistenceScheduled = false;
  bool _storageReady = false;
  bool _libraryNeedsRecoveryPersistence = false;
  String? lastBackupError;

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
    final storedModelId = prefs.getString('selectedModelId');
    final storedModelName = prefs.getString('selectedModelName');
    selectedModelId = storedModelId?.trim().isNotEmpty == true
        ? storedModelId!
        : defaultAiModelId;
    selectedModelName = storedModelName?.trim().isNotEmpty == true
        ? storedModelName!
        : defaultAiModelName;
    useAiVision = prefs.getBool('useAiVision') ?? false;
    final savedToolbarTools = prefs.getStringList('editorToolbarTools');
    if (savedToolbarTools != null) {
      toolbarTools = savedToolbarTools
          .map((name) => EditorTool.values.where((tool) => tool.name == name))
          .expand((matches) => matches)
          .toSet()
          .toList();
      if (!toolbarTools.contains(EditorTool.pen)) {
        toolbarTools.insert(0, EditorTool.pen);
      }
      toolbarTools.sort(
        (a, b) => defaultToolbarTools
            .indexOf(a)
            .compareTo(defaultToolbarTools.indexOf(b)),
      );
    }
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
    final relocatedAttachments = await _repairRelocatedAttachmentPaths();
    final repairedAttachments = _ensureLegacyImagePlacements();
    final regeneratedPdfPages = await _repairMissingPdfBackgrounds();
    _storageReady = true;
    if (_libraryNeedsRecoveryPersistence) {
      try {
        await flushPersistence();
        _libraryNeedsRecoveryPersistence = false;
      } catch (error) {
        debugPrint('[NoteEryk][Storage] recovery persistence failed: $error');
      }
    } else if (relocatedAttachments ||
        repairedAttachments ||
        regeneratedPdfPages) {
      schedulePersistence();
    }
    notifyListeners();
    debugPrint(
      '[NoteEryk][AppState] initialized destination=$destination '
      'openNotebook=${openNotebook?.id} hasKey=$hasApiKey '
      'configuredModels=${modelIds.length}',
    );
  }

  Future<void> _loadLibrary(SharedPreferences prefs) async {
    String? fileRaw;
    String? previousRaw;
    String? temporaryRaw;
    // These files only remain after an interrupted atomic replacement. Read
    // each one independently: one corrupt temporary file must not hide a
    // complete previous file.
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/notebook_library_v2.json');
      fileRaw = await _readStorageCandidate(file, 'library file');
      previousRaw = await _readStorageCandidate(
        File('${file.path}.previous'),
        'previous recovery file',
      );
      temporaryRaw = await _readStorageCandidate(
        File('${file.path}.tmp'),
        'temporary recovery file',
      );
    } catch (error) {
      debugPrint('[NoteEryk][Storage] storage directory unavailable: $error');
    }
    final preferenceRaw = prefs.getString(_libraryStorageName);
    final committedMirrorMatches = fileRaw != null && fileRaw == preferenceRaw;
    final candidates = <(String, String?)>[
      ('file', fileRaw),
      if (preferenceRaw != fileRaw) ('preferences', preferenceRaw),
      if (!committedMirrorMatches &&
          previousRaw != fileRaw &&
          previousRaw != preferenceRaw)
        ('previous recovery file', previousRaw),
      if (temporaryRaw != fileRaw &&
          temporaryRaw != preferenceRaw &&
          temporaryRaw != previousRaw)
        ('temporary recovery file', temporaryRaw),
    ];
    final decodedCandidates = <({String source, Map<String, dynamic> data})>[];
    for (final (source, raw) in candidates) {
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decodedCandidates.add((source: source, data: decoded));
        }
      } catch (error) {
        debugPrint('[NoteEryk][Storage] $source library load failed: $error');
      }
    }
    if (decodedCandidates.isEmpty) return;
    // The file and SharedPreferences mirror can be one write apart when an
    // update or forced close interrupts persistence. Prefer the snapshot that
    // still contains the most actual notebook content, then use its timestamp
    // as a tie-breaker. This prevents a sparse file (cover only) replacing a
    // complete mirror containing page backgrounds and strokes.
    decodedCandidates.sort((a, b) {
      final score = _safeSnapshotContentScore(
        b.data,
      ).compareTo(_safeSnapshotContentScore(a.data));
      if (score != 0) return score;
      return _snapshotTimestamp(b.data).compareTo(_snapshotTimestamp(a.data));
    });
    for (final selected in decodedCandidates) {
      try {
        _applyLibrarySnapshot(selected.data);
        _libraryNeedsRecoveryPersistence =
            selected.source != 'file' || decodedCandidates.length > 1;
        debugPrint('[NoteEryk][Storage] loaded ${selected.source} snapshot');
        return;
      } catch (error) {
        debugPrint(
          '[NoteEryk][Storage] ${selected.source} snapshot is invalid: $error',
        );
      }
    }
  }

  Future<String?> _readStorageCandidate(File file, String label) async {
    try {
      return await file.exists() ? await file.readAsString() : null;
    } catch (error) {
      debugPrint('[NoteEryk][Storage] $label read failed: $error');
      return null;
    }
  }

  int _safeSnapshotContentScore(Map<String, dynamic> data) {
    try {
      return _snapshotContentScore(data);
    } catch (_) {
      return -1;
    }
  }

  int _snapshotContentScore(Map<String, dynamic> data) {
    int listLength(String key) => (data[key] as List?)?.length ?? 0;
    var score = listLength('notebooks') * 100000;
    score += listLength('weakPoints') * 100;
    score += listLength('blankPages') * 10;
    final strokes = data['strokes'] as Map?;
    if (strokes != null) {
      score += strokes.values.fold<int>(
        0,
        (sum, value) => sum + (value as List).length * 10,
      );
    }
    final images = data['pageImages'] as Map?;
    if (images != null) {
      for (final pages in images.values) {
        if (pages is Map) {
          score += pages.values.fold<int>(
            0,
            (sum, value) => sum + (value as List).length * 20,
          );
        }
      }
    }
    score += ((data['imagePlacements'] as Map?)?.length ?? 0) * 20;
    score += ((data['sourceDocuments'] as Map?)?.length ?? 0) * 20;
    score += ((data['pinnedNotes'] as Map?)?.length ?? 0) * 10;
    return score;
  }

  String _snapshotTimestamp(Map<String, dynamic> data) =>
      data['updatedAt']?.toString() ?? '';

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
    final parsedLastPages = (data['lastPages'] as Map?)?.map(
      (key, value) => MapEntry(key.toString(), (value as num).toInt()),
    );
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
    if (parsedLastPages != null) {
      lastPages
        ..clear()
        ..addAll(parsedLastPages);
    }
    if (parsedStrokes != null) {
      strokes
        ..clear()
        ..addAll(parsedStrokes);
    }
  }

  /// App/container updates can change the absolute prefix of Application
  /// Support while preserving its contents. Older snapshots stored absolute
  /// paths, so recover those references from their stable in-app suffix before
  /// treating the page images as missing.
  Future<bool> _repairRelocatedAttachmentPaths() async {
    try {
      final support = await getApplicationSupportDirectory();
      final replacements = <String, String>{};
      for (final oldPath in _attachmentPaths().toSet()) {
        if (oldPath.isEmpty || await File(oldPath).exists()) continue;
        final normalized = oldPath.replaceAll('\\', '/');
        String? relative;
        for (final marker in const ['/imports/', '/pdf_backgrounds/']) {
          final index = normalized.indexOf(marker);
          if (index >= 0) {
            relative = normalized.substring(index + 1);
            break;
          }
        }
        if (relative == null) continue;
        final candidate = File(
          '${support.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
        );
        if (await _isUsableBackupFile(candidate)) {
          replacements[oldPath] = candidate.path;
        }
      }
      if (replacements.isEmpty) return false;

      for (final pages in pageImages.values) {
        for (final paths in pages.values) {
          for (var index = 0; index < paths.length; index++) {
            paths[index] = replacements[paths[index]] ?? paths[index];
          }
        }
      }
      for (final entry in imagePlacements.entries.toList()) {
        final replacement = replacements[entry.value.path];
        if (replacement != null) {
          imagePlacements[entry.key] = entry.value.copyWith(path: replacement);
        }
      }
      for (final entry in sourceDocuments.entries.toList()) {
        sourceDocuments[entry.key] = replacements[entry.value] ?? entry.value;
      }
      weakPoints = weakPoints.map((point) {
        final replacement = replacements[point.sourceImagePath];
        if (replacement == null) return point;
        final json = point.toJson()..['sourceImagePath'] = replacement;
        return WeakPoint.fromJson(json);
      }).toList();
      debugPrint(
        '[NoteEryk][Storage] repaired ${replacements.length} relocated attachment paths',
      );
      return true;
    } catch (error) {
      debugPrint('[NoteEryk][Storage] attachment relocation failed: $error');
      return false;
    }
  }

  /// Older snapshots can contain page image paths without the placement
  /// records introduced later. In that case the files are present after a
  /// restore, but the editor has nothing to paint and the PDF looks white.
  bool _ensureLegacyImagePlacements() {
    var changed = false;
    pageImages.forEach((notebookId, pages) {
      pages.forEach((page, paths) {
        for (var index = 0; index < paths.length; index++) {
          final imagePath = paths[index];
          final prefix = '$notebookId:$page:';
          final alreadyPlaced = imagePlacements.values.any(
            (placement) =>
                placement.id.startsWith(prefix) && placement.path == imagePath,
          );
          if (alreadyPlaced) continue;
          final rect = paths.length == 1
              ? const Rect.fromLTWH(0, 0, 1, 1)
              : Rect.fromLTWH(
                  .02,
                  index / paths.length + .01,
                  .96,
                  1 / paths.length - .02,
                );
          final id =
              '$notebookId:$page:restored:${DateTime.now().microsecondsSinceEpoch}:${_imagePlacementSequence++}:$index';
          imagePlacements[id] = PageImagePlacement(
            id: id,
            path: imagePath,
            rect: rect,
            isBackground: true,
          );
          changed = true;
        }
      });
    });
    return changed;
  }

  /// Rebuild missing raster page backgrounds from the original PDF. The
  /// source PDF is part of modern .noteeryk backups, so this also repairs
  /// snapshots made by builds that forgot to include rendered page images.
  Future<bool> _repairMissingPdfBackgrounds() async {
    var changed = false;
    for (final notebook in notebooks.where((item) => item.isPdf)) {
      final sourcePath = sourceDocuments[notebook.id];
      if (sourcePath == null || !await File(sourcePath).exists()) continue;
      final pagesNeedingRepair = <int>[];
      for (var pageNumber = 1; pageNumber <= notebook.pages; pageNumber++) {
        if (blankPages.contains('${notebook.id}:$pageNumber')) continue;
        final prefix = '${notebook.id}:$pageNumber:';
        final hasUsableBackground = imagePlacements.values.any(
          (placement) =>
              placement.id.startsWith(prefix) &&
              placement.isBackground &&
              File(placement.path).existsSync(),
        );
        if (!hasUsableBackground) pagesNeedingRepair.add(pageNumber);
      }
      if (pagesNeedingRepair.isEmpty) continue;
      pdfx.PdfDocument? document;
      try {
        document = await pdfx.PdfDocument.openFile(sourcePath);
        final repairDirectory = Directory(
          '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}pdf_backgrounds${Platform.pathSeparator}${notebook.id}',
        );
        await repairDirectory.create(recursive: true);
        for (final pageNumber in pagesNeedingRepair) {
          if (pageNumber > document.pagesCount) continue;
          final prefix = '${notebook.id}:$pageNumber:';
          final pagePaths = pageImages
              .putIfAbsent(notebook.id, () => {})
              .putIfAbsent(pageNumber, () => []);

          final page = await document.getPage(pageNumber);
          try {
            const width = 1200.0;
            final rendered = await page.render(
              width: width,
              height: width * page.height / page.width,
              format: pdfx.PdfPageImageFormat.jpeg,
              quality: 90,
              backgroundColor: '#FFFFFF',
            );
            if (rendered == null) continue;
            final target = File(
              '${repairDirectory.path}${Platform.pathSeparator}page_${pageNumber.toString().padLeft(4, '0')}.jpg',
            );
            await target.writeAsBytes(rendered.bytes, flush: true);
            final missingPaths = pagePaths
                .where((path) => !File(path).existsSync())
                .toSet();
            pagePaths.removeWhere(missingPaths.contains);
            imagePlacements.removeWhere(
              (_, placement) =>
                  placement.id.startsWith(prefix) &&
                  missingPaths.contains(placement.path),
            );
            if (!pagePaths.contains(target.path)) {
              pagePaths.insert(0, target.path);
            }
            final id =
                '${prefix}repaired:${DateTime.now().microsecondsSinceEpoch}:${_imagePlacementSequence++}';
            imagePlacements[id] = PageImagePlacement(
              id: id,
              path: target.path,
              rect: const Rect.fromLTWH(0, 0, 1, 1),
              isBackground: true,
            );
            changed = true;
          } finally {
            await page.close();
          }
        }
      } catch (error) {
        debugPrint(
          '[NoteEryk][Storage] PDF background repair failed for ${notebook.id}: $error',
        );
      } finally {
        await document?.close();
      }
    }
    return changed;
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
        pages.map(
          (page, paths) => MapEntry(page.toString(), List<String>.of(paths)),
        ),
      ),
    ),
    'imagePlacements': imagePlacements.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'blankPages': blankPages.toList(),
    'sourceDocuments': Map<String, String>.of(sourceDocuments),
    'lastPages': Map<String, int>.of(lastPages),
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
    final previous = File('${target.path}.previous');
    await temporary.writeAsString(encoded, flush: true);
    if (await temporary.length() != utf8.encode(encoded).length ||
        await temporary.readAsString() != encoded) {
      throw const FileSystemException(
        'Temporary library file verification failed',
      );
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final mirrored = await prefs.setString(_libraryStorageName, encoded);
      if (!mirrored) {
        debugPrint('[NoteEryk][Storage] preferences mirror was not accepted');
      }
    } catch (error) {
      debugPrint('[NoteEryk][Storage] preferences mirror failed: $error');
    }
    try {
      if (await previous.exists()) await previous.delete();
      if (await target.exists()) await target.rename(previous.path);
      await temporary.rename(target.path);
      if (await previous.exists()) await previous.delete();
    } catch (error) {
      // Never leave the app without a readable file if replacement is
      // interrupted by an update or process termination.
      if (!await target.exists() && await previous.exists()) {
        try {
          await previous.rename(target.path);
        } catch (_) {}
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
    }
  }

  Future<File> exportBackupSnapshot() async {
    final running = _backupInFlight;
    if (running != null) return running;
    lastBackupError = null;
    final operation = _exportBackupSnapshot();
    _backupInFlight = operation;
    try {
      return await operation;
    } catch (error) {
      lastBackupError = _readableBackupError(error);
      rethrow;
    } finally {
      if (identical(_backupInFlight, operation)) _backupInFlight = null;
    }
  }

  Future<File> _exportBackupSnapshot() async {
    _ensureLegacyImagePlacements();
    await _repairMissingPdfBackgrounds();
    await _validateCurrentPageFilesForBackup();
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
    final optionalMissingPaths = <String>{};
    for (final sourcePath in _attachmentPaths().toSet()) {
      final source = File(sourcePath);
      if (!await _isUsableBackupFile(source)) {
        optionalMissingPaths.add(sourcePath);
        continue;
      }
      final filename = source.uri.pathSegments.last;
      final targetName = '${attachmentIndex++}_$filename';
      final archiveName = 'Files/$targetName';
      attachments[sourcePath] = archiveName;
      attachmentFiles.add((source: sourcePath, archiveName: archiveName));
    }
    _removeMissingOptionalPaths(snapshot, optionalMissingPaths);
    snapshot['attachments'] = attachments;
    final manifest = File('${backups.path}/.NoteEryk-$stamp.manifest.tmp');
    ZipFileEncoder? encoder;
    var completed = false;
    try {
      await manifest.writeAsString(
        jsonEncode({
          ...snapshot,
          'format': 'note-eryk-backup',
          'backupVersion': 1,
          'createdAt': DateTime.now().toIso8601String(),
        }),
        flush: true,
      );
      if (await temporaryTarget.exists()) await temporaryTarget.delete();
      encoder = ZipFileEncoder()..create(temporaryTarget.path);
      await encoder.addFile(manifest, 'manifest.json');
      for (final entry in attachmentFiles) {
        await encoder.addFile(File(entry.source), entry.archiveName);
      }
      await encoder.close();
      encoder = null;
      await _validateCreatedBackup(temporaryTarget, attachmentFiles);
      await temporaryTarget.rename(target.path);
      completed = true;
    } finally {
      if (encoder != null) {
        try {
          await encoder.close();
        } catch (_) {}
      }
      if (await manifest.exists()) {
        try {
          await manifest.delete();
        } catch (_) {}
      }
      if (!completed && await temporaryTarget.exists()) {
        try {
          await temporaryTarget.delete();
        } catch (_) {}
      }
    }
    try {
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
        try {
          await old.delete();
        } catch (error) {
          debugPrint('[NoteEryk][Storage] old backup cleanup failed: $error');
        }
      }
    } catch (error) {
      // The new backup is already verified and safely renamed. Failure to
      // prune an older copy must not turn a successful backup into a failure.
      debugPrint('[NoteEryk][Storage] backup list cleanup failed: $error');
    }
    return target;
  }

  Future<bool> _isUsableBackupFile(File file) async =>
      await file.exists() && await file.length() > 0;

  Future<void> _validateCurrentPageFilesForBackup() async {
    final missing = <String>[];
    final requiredPaths = <String>{
      for (final pages in pageImages.values)
        for (final paths in pages.values) ...paths,
      for (final placement in imagePlacements.values) placement.path,
    };
    for (final path in requiredPaths) {
      if (path.isEmpty || !await _isUsableBackupFile(File(path))) {
        missing.add(path);
      }
    }
    if (missing.isNotEmpty) {
      throw StateError(
        'Thiếu ${missing.length} tệp ảnh/trang. Backup đã dừng để tránh tạo bản sao lưu có trang trắng.',
      );
    }

    for (final notebook in notebooks.where((item) => item.isPdf)) {
      final sourcePath = sourceDocuments[notebook.id];
      final hasSource =
          sourcePath != null && await _isUsableBackupFile(File(sourcePath));
      for (var page = 1; page <= notebook.pages; page++) {
        if (blankPages.contains('${notebook.id}:$page')) continue;
        final prefix = '${notebook.id}:$page:';
        final hasBackground = imagePlacements.values.any(
          (placement) =>
              placement.id.startsWith(prefix) &&
              placement.isBackground &&
              File(placement.path).existsSync(),
        );
        if (!hasBackground && !hasSource) {
          throw StateError(
            'Vở "${notebook.title}" thiếu dữ liệu trang $page. Backup đã dừng để không lưu một bản bị trắng trang.',
          );
        }
      }
    }
  }

  void _removeMissingOptionalPaths(
    Map<String, Object?> snapshot,
    Set<String> missingPaths,
  ) {
    final documents = snapshot['sourceDocuments'] as Map<String, String>;
    documents.removeWhere((_, path) => missingPaths.contains(path));
    final points = snapshot['weakPoints'] as List;
    for (final item in points) {
      final point = item as Map<String, dynamic>;
      if (missingPaths.contains(point['sourceImagePath'])) {
        point['sourceImagePath'] = null;
      }
    }
  }

  Future<void> _validateCreatedBackup(
    File backup,
    List<({String source, String archiveName})> attachments,
  ) async {
    if (!await _isUsableBackupFile(backup)) {
      throw StateError('Tệp backup tạo ra bị rỗng.');
    }
    final input = InputFileStream(backup.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final manifest = archive.findFile('manifest.json');
      if (manifest == null || manifest.size == 0) {
        throw StateError('Backup thiếu danh mục dữ liệu.');
      }
      final manifestData = jsonDecode(
        utf8.decode(manifest.readBytes() ?? const []),
      );
      if (manifestData is! Map<String, dynamic> ||
          manifestData['format'] != 'note-eryk-backup' ||
          manifestData['backupVersion'] != 1 ||
          (manifestData['attachments'] as Map?)?.length != attachments.length) {
        throw StateError('Danh mục dữ liệu trong backup không hợp lệ.');
      }
      for (final attachment in attachments) {
        final archived = archive.findFile(attachment.archiveName);
        final sourceLength = await File(attachment.source).length();
        final sourceCrc = await _fileCrc32(File(attachment.source));
        if (archived == null ||
            archived.size != sourceLength ||
            archived.crc32 != sourceCrc) {
          throw StateError(
            'Backup thiếu hoặc cắt dở tệp ${attachment.archiveName}.',
          );
        }
      }
    } finally {
      await input.close();
    }
  }

  Future<int> _fileCrc32(File file) async {
    var crc = 0;
    await for (final chunk in file.openRead()) {
      crc = getCrc32(chunk, crc);
    }
    return crc;
  }

  Iterable<String> _attachmentPaths() sync* {
    for (final pages in pageImages.values) {
      for (final paths in pages.values) {
        yield* paths;
      }
    }
    // A placement can survive a legacy migration even when its pageImages
    // index was incomplete. Package it independently so no visible layer is
    // silently omitted from the backup.
    for (final placement in imagePlacements.values) {
      yield placement.path;
    }
    yield* sourceDocuments.values;
    for (final point in weakPoints) {
      final path = point.sourceImagePath;
      if (path != null && path.isNotEmpty) yield path;
    }
  }

  Future<bool> importBackupFile(String path) async {
    lastBackupError = null;
    Directory? restoreDirectory;
    InputFileStream? archiveInput;
    try {
      final input = File(path);
      final isArchive = path.toLowerCase().endsWith('.noteeryk');
      Archive? archive;
      Map<String, dynamic> data;
      if (isArchive) {
        archiveInput = InputFileStream(input.path);
        archive = ZipDecoder().decodeStream(archiveInput);
        final manifest = archive.findFile('manifest.json');
        if (manifest == null || manifest.size == 0) {
          throw const FormatException('Backup thiếu danh mục dữ liệu.');
        }
        data =
            jsonDecode(utf8.decode(manifest.readBytes() ?? const []))
                as Map<String, dynamic>;
      } else {
        data = jsonDecode(await input.readAsString()) as Map<String, dynamic>;
      }
      final backupVersion = data['backupVersion'];
      final libraryVersion = data['version'];
      final supportedLegacyEnvelope =
          backupVersion == null && (libraryVersion == 1 || libraryVersion == 2);
      if (data['format'] != 'note-eryk-backup' ||
          (backupVersion != 1 && !supportedLegacyEnvelope)) {
        throw const FormatException(
          'Định dạng hoặc phiên bản backup không hợp lệ.',
        );
      }
      final library = Map<String, dynamic>.from(data)
        ..remove('format')
        ..remove('backupVersion')
        ..remove('createdAt')
        ..remove('attachments');
      _normalizeAndValidateImportedLibrary(library);
      final attachments = Map<String, dynamic>.from(
        data['attachments'] as Map? ?? const {},
      );
      final requiredPaths = _requiredImportedPagePaths(library);
      final packagedPaths = attachments.keys
          .map((key) => key.toString())
          .toSet();
      final unpackaged = requiredPaths.difference(packagedPaths);
      if (unpackaged.isNotEmpty) {
        throw FormatException(
          'Backup thiếu ${unpackaged.length} ảnh/trang được ghi trong danh mục.',
        );
      }
      _removeUnrestoredOptionalImportedPaths(library, packagedPaths);
      _validateImportedPdfPages(library, packagedPaths);
      if (attachments.isNotEmpty) {
        final support = await getApplicationSupportDirectory();
        final imports = Directory(
          '${support.path}${Platform.pathSeparator}imports',
        );
        restoreDirectory = Directory(
          '${imports.path}${Platform.pathSeparator}restored_${DateTime.now().microsecondsSinceEpoch}',
        );
        await restoreDirectory.create(recursive: true);
        final restoredPaths = <String, String>{};
        var attachmentIndex = 0;
        for (final entry in attachments.entries) {
          if (entry.value is! String) {
            throw const FormatException('Danh mục tệp trong backup bị lỗi.');
          }
          final relative = entry.value as String;
          if (!_isSafeBackupArchivePath(relative)) {
            throw const FormatException(
              'Backup chứa đường dẫn tệp không an toàn.',
            );
          }
          final filename = relative.split('/').last;
          final destination = File(
            '${restoreDirectory.path}${Platform.pathSeparator}${attachmentIndex++}_$filename',
          );
          int expectedLength;
          int? expectedCrc;
          if (archive != null) {
            final archived = archive.findFile(relative);
            if (archived == null || archived.size == 0) {
              throw FormatException('Backup thiếu tệp $relative.');
            }
            expectedLength = archived.size;
            expectedCrc = archived.crc32;
            final output = OutputFileStream(destination.path);
            try {
              archived.writeContent(output);
            } finally {
              await output.close();
            }
          } else {
            final source = File('${input.parent.path}/$relative');
            if (!await _isUsableBackupFile(source)) {
              throw FormatException('Backup thiếu tệp $relative.');
            }
            expectedLength = await source.length();
            await source.copy(destination.path);
          }
          if (!await destination.exists() ||
              await destination.length() != expectedLength) {
            throw FormatException('Tệp $relative bị cắt dở khi khôi phục.');
          }
          if (expectedCrc != null &&
              await _fileCrc32(destination) != expectedCrc) {
            throw FormatException('Tệp $relative bị hỏng trong backup.');
          }
          restoredPaths[entry.key] = destination.path;
        }
        if (restoredPaths.length != attachments.length) {
          throw const FormatException(
            'Backup chưa khôi phục đủ các tệp đính kèm.',
          );
        }
        _replaceBackupPaths(library, restoredPaths);
      }

      // Persist and create a portable rescue copy of the current library
      // before replacing anything. A bad restore can therefore be rolled back
      // without relying on the selected import file.
      await flushPersistence();
      await exportBackupSnapshot();
      final currentSnapshot = _librarySnapshot();
      try {
        _applyLibrarySnapshot(library);
        _ensureLegacyImagePlacements();
        await _repairMissingPdfBackgrounds();
        await flushPersistence();
      } catch (_) {
        _applyLibrarySnapshot(currentSnapshot);
        try {
          await flushPersistence();
        } catch (_) {}
        rethrow;
      }
      restoreDirectory = null;
      notifyListeners();
      return true;
    } catch (error) {
      lastBackupError = _readableBackupError(error);
      debugPrint('[NoteEryk][Storage] backup import failed: $error');
      return false;
    } finally {
      await archiveInput?.close();
      final failedRestore = restoreDirectory;
      if (failedRestore != null && await failedRestore.exists()) {
        final parent = failedRestore.parent.absolute.path;
        final expectedParent = Directory(
          '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}imports',
        ).absolute.path;
        if (parent == expectedParent &&
            failedRestore.uri.pathSegments
                .where((segment) => segment.isNotEmpty)
                .last
                .startsWith('restored_')) {
          try {
            await failedRestore.delete(recursive: true);
          } catch (_) {}
        }
      }
    }
  }

  String _readableBackupError(Object error) {
    if (error is FormatException) return error.message.toString();
    if (error is StateError) return error.message.toString();
    return 'Không thể hoàn tất backup. Dữ liệu hiện tại vẫn được giữ nguyên.';
  }

  void _normalizeAndValidateImportedLibrary(Map<String, dynamic> library) {
    if (library['notebooks'] is! List ||
        library['strokes'] is! Map ||
        library['pageImages'] is! Map) {
      throw const FormatException('Backup thiếu dữ liệu thư viện bắt buộc.');
    }
    library.putIfAbsent('folders', () => <dynamic>[]);
    library.putIfAbsent('pinnedNotes', () => <String, dynamic>{});
    library.putIfAbsent('imagePlacements', () => <String, dynamic>{});
    library.putIfAbsent('blankPages', () => <dynamic>[]);
    library.putIfAbsent('sourceDocuments', () => <String, dynamic>{});
    library.putIfAbsent('lastPages', () => <String, dynamic>{});
    library.putIfAbsent('weakPoints', () => <dynamic>[]);
  }

  Set<String> _requiredImportedPagePaths(Map<String, dynamic> library) {
    final result = <String>{};
    final images = library['pageImages'] as Map;
    for (final pages in images.values) {
      if (pages is! Map) {
        throw const FormatException('Danh mục ảnh trang trong backup bị lỗi.');
      }
      for (final paths in pages.values) {
        if (paths is! List || paths.any((path) => path is! String)) {
          throw const FormatException(
            'Danh mục ảnh trang trong backup bị lỗi.',
          );
        }
        result.addAll(paths.cast<String>());
      }
    }
    final placements = library['imagePlacements'] as Map;
    for (final value in placements.values) {
      if (value is! Map || value['path'] is! String) {
        throw const FormatException('Vị trí ảnh trong backup bị lỗi.');
      }
      result.add(value['path'] as String);
    }
    result.removeWhere((path) => path.isEmpty);
    return result;
  }

  bool _isSafeBackupArchivePath(String relative) {
    final segments = relative.split('/');
    return relative.startsWith('Files/') &&
        !relative.contains('\\') &&
        segments.length == 2 &&
        segments.every((segment) => segment.isNotEmpty && segment != '..');
  }

  void _removeUnrestoredOptionalImportedPaths(
    Map<String, dynamic> library,
    Set<String> restoredOriginalPaths,
  ) {
    final documents = library['sourceDocuments'] as Map;
    documents.removeWhere(
      (_, path) => path is! String || !restoredOriginalPaths.contains(path),
    );
    final points = library['weakPoints'] as List;
    for (final item in points) {
      if (item is! Map<String, dynamic>) continue;
      final path = item['sourceImagePath'];
      if (path is String && !restoredOriginalPaths.contains(path)) {
        item['sourceImagePath'] = null;
      }
    }
  }

  void _validateImportedPdfPages(
    Map<String, dynamic> library,
    Set<String> packagedPaths,
  ) {
    final importedNotebooks = (library['notebooks'] as List).map(
      (item) => NotebookData.fromJson(item as Map<String, dynamic>),
    );
    final blanks = Set<String>.from(library['blankPages'] as List);
    final documents = library['sourceDocuments'] as Map;
    final placements = library['imagePlacements'] as Map;
    final images = library['pageImages'] as Map;
    for (final notebook in importedNotebooks.where((item) => item.isPdf)) {
      final source = documents[notebook.id];
      final hasSource = source is String && packagedPaths.contains(source);
      final notebookPages = images[notebook.id] as Map?;
      for (var page = 1; page <= notebook.pages; page++) {
        if (blanks.contains('${notebook.id}:$page')) continue;
        final prefix = '${notebook.id}:$page:';
        final hasPlacement = placements.entries.any((entry) {
          final value = entry.value;
          return entry.key.toString().startsWith(prefix) &&
              value is Map &&
              value['isBackground'] == true &&
              packagedPaths.contains(value['path']);
        });
        final legacyPaths = notebookPages?[page.toString()] as List?;
        final hasLegacyPage = legacyPaths?.any(packagedPaths.contains) ?? false;
        if (!hasPlacement && !hasLegacyPage && !hasSource) {
          throw FormatException(
            'Backup thiếu dữ liệu trang $page của vở "${notebook.title}".',
          );
        }
      }
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

  void open(NotebookData notebook, {int? page, bool source = false}) {
    debugPrint(
      '[NoteEryk][Navigation] open notebook=${notebook.id} page=$page source=$source',
    );
    openNotebook = notebook;
    // A newly created notebook has one blank page. Clamp the requested page
    // so it can never open on a non-existent page (the old default of 12
    // made a one-page notebook appear to start at page 12).
    final remembered = lastPages[notebook.id] ?? 1;
    openPage = (page ?? remembered).clamp(1, notebook.pages);
    lastPages[notebook.id] = openPage;
    focusSource = source;
    notifyListeners();
    schedulePersistence();
  }

  void goToPage(int page) {
    if (openNotebook == null) return;
    openPage = page.clamp(1, openNotebook!.pages);
    lastPages[openNotebook!.id] = openPage;
    focusSource = false;
    debugPrint('[NoteEryk][Pages] goToPage $openPage');
    notifyListeners();
    schedulePersistence();
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

  bool moveNotebooksToTrash(Iterable<String> notebookIds) {
    final ids = notebookIds.toSet();
    if (ids.isEmpty ||
        !notebooks.any((note) => ids.contains(note.id) && !note.isTrashed)) {
      return false;
    }
    _captureFolderUndo();
    for (var index = 0; index < notebooks.length; index++) {
      if (ids.contains(notebooks[index].id) && !notebooks[index].isTrashed) {
        notebooks[index] = notebooks[index].copyWith(isTrashed: true);
      }
    }
    final openId = openNotebook?.id;
    if (openId != null && ids.contains(openId)) openNotebook = null;
    notifyListeners();
    schedulePersistence();
    return true;
  }

  bool restoreNotebooksFromTrash(Iterable<String> notebookIds) {
    final ids = notebookIds.toSet();
    if (ids.isEmpty ||
        !notebooks.any((note) => ids.contains(note.id) && note.isTrashed)) {
      return false;
    }
    _captureFolderUndo();
    for (var index = 0; index < notebooks.length; index++) {
      if (ids.contains(notebooks[index].id) && notebooks[index].isTrashed) {
        notebooks[index] = notebooks[index].copyWith(isTrashed: false);
      }
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
    await prefs.setStringList(
      'editorToolbarTools',
      toolbarTools.map((tool) => tool.name).toList(),
    );
    await prefs.setString(
      'studentName',
      studentName.trim().isEmpty ? 'Eryk' : studentName.trim(),
    );
    await prefs.setString('jlpt', jlpt);
    notifyListeners();
  }

  void setToolbarTools(Set<EditorTool> tools) {
    final selected = Set<EditorTool>.of(tools)..add(EditorTool.pen);
    toolbarTools = defaultToolbarTools
        .where(selected.contains)
        .toList(growable: false);
    notifyListeners();
    unawaited(saveGeneralSettings());
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
    // New installs (and older installs without a per-feature assignment) use
    // Luna consistently in every AI function while still allowing overrides.
    for (final slot in AiModelSlot.values) {
      modelIds.putIfAbsent(slot, () => selectedModelId);
      modelNames.putIfAbsent(slot, () => selectedModelName);
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
