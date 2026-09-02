import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:noteeryk/app_state.dart';
import 'package:noteeryk/models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

      final support = Directory('${root.path}/support');
      final currentImage = File(
        '${support.path}${Platform.pathSeparator}imports${Platform.pathSeparator}page_images${Platform.pathSeparator}page-1.jpg',
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
      await support.create(recursive: true);
      await File(
        '${support.path}/notebook_library_v2.json',
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

  test('mỗi vở nhớ trang cuối và model mặc định là Luna', () {
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
