import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.state,
    this.sharedFiles = const [],
    this.onSharedFilesHandled,
    this.onSharedFilesDeferred,
  });
  final AppState state;
  final List<String> sharedFiles;
  final ValueChanged<List<String>>? onSharedFilesHandled;
  final VoidCallback? onSharedFilesDeferred;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String filter = 'Tất cả';
  String search = '';
  bool gridView = true;
  bool _handlingSharedFiles = false;
  final Set<String> _selectedNotebookIds = {};
  bool _selectionMode = false;

  void _toggleNotebookSelection(String id) {
    setState(() {
      _selectionMode = true;
      if (!_selectedNotebookIds.add(id)) _selectedNotebookIds.remove(id);
    });
  }

  void _clearNotebookSelection() {
    if (_selectedNotebookIds.isEmpty && !_selectionMode) return;
    setState(() {
      _selectedNotebookIds.clear();
      _selectionMode = false;
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedNotebookIds.clear();
    });
  }

  Future<void> _moveSelectedNotebooks() async {
    final target = await showModalBottomSheet<String?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Tất cả ghi chú (bỏ folder)'),
              onTap: () => Navigator.pop(sheetContext, 'root'),
            ),
            for (final folder in widget.state.folders.where(
              (item) => !item.isTrashed,
            ))
              ListTile(
                leading: Icon(Icons.folder, color: Color(folder.color)),
                title: Text(folder.name),
                onTap: () => Navigator.pop(sheetContext, folder.id),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    final moved = widget.state.moveNotebooksToFolder(
      _selectedNotebookIds,
      target == 'root' ? null : target,
    );
    if (moved && mounted) {
      _clearNotebookSelection();
      showAppSnack(
        context,
        'Đã di chuyển các vở đã chọn',
        actionLabel: 'Hoàn tác',
        onAction: widget.state.undoFolderAction,
      );
    }
  }

  Future<void> _deleteSelectedNotebooks() async {
    final selectedIds = Set<String>.of(_selectedNotebookIds);
    if (selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Xóa ${selectedIds.length} vở đã chọn?'),
        content: const Text(
          'Các vở sẽ được chuyển vào Thùng rác và có thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Chuyển vào Thùng rác'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (widget.state.moveNotebooksToTrash(selectedIds)) {
      _clearNotebookSelection();
      showAppSnack(
        context,
        'Đã chuyển ${selectedIds.length} vở vào Thùng rác',
        actionLabel: 'Hoàn tác',
        onAction: widget.state.undoFolderAction,
      );
    }
  }

  void _restoreSelectedNotebooks() {
    final selectedIds = Set<String>.of(_selectedNotebookIds);
    if (widget.state.restoreNotebooksFromTrash(selectedIds)) {
      _clearNotebookSelection();
      showAppSnack(
        context,
        'Đã khôi phục ${selectedIds.length} vở',
        actionLabel: 'Hoàn tác',
        onAction: widget.state.undoFolderAction,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleSharedImport();
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sharedFiles != widget.sharedFiles) _scheduleSharedImport();
  }

  void _scheduleSharedImport() {
    if (_handlingSharedFiles || widget.sharedFiles.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _importSharedFiles());
  }

  Future<void> _importSharedFiles() async {
    if (!mounted || _handlingSharedFiles || widget.sharedFiles.isEmpty) return;
    _handlingSharedFiles = true;
    final paths = List<String>.of(widget.sharedFiles);
    var imported = false;
    try {
      imported = await _showImportPreview(paths);
    } catch (exception) {
      if (mounted) {
        showAppSnack(context, 'Không thể nhập tệp: $exception');
      }
    } finally {
      _handlingSharedFiles = false;
      // Keep staged files until a notebook is actually created. Previously a
      // dismissed preview or a failed PDF render acknowledged (and deleted)
      // the files, making the share action look like it did nothing.
      if (imported) {
        widget.onSharedFilesHandled?.call(paths);
      } else {
        // Release the in-memory guard without deleting staged files. The app
        // can discover and offer them again on the next foreground pass.
        widget.onSharedFilesDeferred?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scoped = switch (widget.state.librarySection) {
      'favorites' => widget.state.favoriteNotes(),
      'trash' => widget.state.notebooks.where((item) => item.isTrashed),
      _ => widget.state.notesInFolder(widget.state.selectedFolderId),
    };
    final notebooks = scoped.where((item) {
      final matchesSearch = item.title.toLowerCase().contains(
        (search.isEmpty ? widget.state.folderSearchQuery : search)
            .toLowerCase(),
      );
      final matchesFilter =
          filter == 'Tất cả' ||
          filter == 'Gần đây' ||
          (filter == 'PDF' && item.isPdf) ||
          (filter == 'Vở trắng' && !item.isPdf);
      return matchesSearch && matchesFilter;
    }).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      child: Column(
        children: [
          PageHeader(
            title: 'Vở của tôi',
            subtitle: 'Mọi trang học tiếng Nhật, ngay trong tầm bút.',
            trailing: _selectedNotebookIds.isNotEmpty
                ? Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${_selectedNotebookIds.length} vở đã chọn',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (widget.state.librarySection == 'trash')
                        IconButton.filledTonal(
                          tooltip: 'Khôi phục các vở đã chọn',
                          onPressed: _restoreSelectedNotebooks,
                          icon: const Icon(Icons.restore_from_trash_outlined),
                        )
                      else ...[
                        IconButton.filledTonal(
                          tooltip: 'Di chuyển vào folder khác',
                          onPressed: _moveSelectedNotebooks,
                          icon: const Icon(Icons.drive_file_move_outline),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Chuyển các vở đã chọn vào Thùng rác',
                          onPressed: _deleteSelectedNotebooks,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                        ),
                      ],
                      IconButton(
                        tooltip: 'Bỏ chọn',
                        onPressed: _clearNotebookSelection,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      IconButton(
                        tooltip: 'Chọn nhiều ghi chú',
                        onPressed: _toggleSelectionMode,
                        icon: Icon(
                          _selectionMode
                              ? Icons.checklist_rounded
                              : Icons.playlist_add_check_rounded,
                        ),
                      ),
                      SearchBox(
                        hint: 'Tìm vở...',
                        width: 220,
                        onChanged: (value) => setState(() => search = value),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'T\u1ea1o folder',
                        onPressed: _showCreateFolderDialog,
                        icon: const Icon(Icons.create_new_folder_outlined),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => setState(() => gridView = !gridView),
                        icon: Icon(
                          gridView
                              ? Icons.grid_view_rounded
                              : Icons.view_list_rounded,
                        ),
                        tooltip: gridView ? 'Dạng lưới' : 'Dạng danh sách',
                      ),
                      FilledButton.icon(
                        onPressed: () => _showCreateSheet(context),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Tạo mới'),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 26),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: ['Tất cả', 'Gần đây', 'Vở trắng', 'PDF']
                  .map(
                    (label) => ChoiceChip(
                      label: Text(label),
                      selected: filter == label,
                      onSelected: (_) => setState(() => filter = label),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth >= 1050
                    ? 4
                    : constraints.maxWidth >= 720
                    ? 3
                    : constraints.maxWidth >= 470
                    ? 2
                    : 1;
                if (!gridView) {
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: notebooks.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) => SizedBox(
                      height: 245,
                      child: index == notebooks.length
                          ? _CreateCard(onTap: () => _showCreateSheet(context))
                          : _draggableNotebook(
                              notebooks[index],
                              _NotebookCard(
                                notebook: notebooks[index],
                                coverPath: _coverPath(notebooks[index]),
                                onTap: () => _selectionMode
                                    ? _toggleNotebookSelection(
                                        notebooks[index].id,
                                      )
                                    : widget.state.open(notebooks[index]),
                                onMenu: () =>
                                    _showNotebookMenu(notebooks[index]),
                                selected: _selectedNotebookIds.contains(
                                  notebooks[index].id,
                                ),
                                onLongPress: () => _toggleNotebookSelection(
                                  notebooks[index].id,
                                ),
                              ),
                            ),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.only(bottom: 32),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    childAspectRatio: .75,
                  ),
                  itemCount: notebooks.length + 1,
                  itemBuilder: (context, index) => index == notebooks.length
                      ? _CreateCard(onTap: () => _showCreateSheet(context))
                      : _draggableNotebook(
                          notebooks[index],
                          _NotebookCard(
                            notebook: notebooks[index],
                            coverPath: _coverPath(notebooks[index]),
                            onTap: () => _selectionMode
                                ? _toggleNotebookSelection(notebooks[index].id)
                                : widget.state.open(notebooks[index]),
                            onMenu: () => _showNotebookMenu(notebooks[index]),
                            selected: _selectedNotebookIds.contains(
                              notebooks[index].id,
                            ),
                            onLongPress: () =>
                                _toggleNotebookSelection(notebooks[index].id),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String? _coverPath(NotebookData notebook) =>
      widget.state.imagesForPage(notebook.id, 1).firstOrNull;

  Widget _draggableNotebook(NotebookData notebook, Widget child) =>
      LongPressDraggable<String>(
        data:
            _selectedNotebookIds.contains(notebook.id) &&
                _selectedNotebookIds.length > 1
            ? 'notes:${_selectedNotebookIds.join(',')}'
            : 'note:${notebook.id}',
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 250, height: 190, child: child),
        ),
        child: child,
      );

  Future<void> _showCreateSheet(BuildContext context) async {
    final titleController = TextEditingController();
    NotebookData? createdNotebook;
    var importPdf = false;
    var paperStyle = PaperStyle.grid;
    var paperLineOpacity = widget.state.paperLineOpacity;
    var cover = AppColors.primary;
    final openImporter = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 720,
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tạo vở mới',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Nhập PDF · Word · nhiều ảnh'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.note_add_outlined),
                        label: Text('Tạo vở'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.picture_as_pdf_outlined),
                        label: Text('Nhập PDF'),
                      ),
                    ],
                    selected: {importPdf},
                    onSelectionChanged: (value) =>
                        setDialogState(() => importPdf = value.first),
                  ),
                  const SizedBox(height: 24),
                  if (importPdf)
                    SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.upload_file_rounded,
                              size: 42,
                              color: AppColors.primary,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Chọn PDF từ Files',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'PDF gốc luôn được giữ nguyên',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    TextField(
                      controller: titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Tên vở',
                        hintText: 'Ví dụ: Ngữ pháp N3',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Kiểu giấy',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: PaperStyle.values
                          .map(
                            (style) => ChoiceChip(
                              label: Text(_paperName(style)),
                              selected: paperStyle == style,
                              onSelected: (_) =>
                                  setDialogState(() => paperStyle = style),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    _NotebookPreview(
                      paperStyle: paperStyle,
                      cover: cover,
                      lineOpacity: paperLineOpacity,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Độ đậm đường kẻ',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text('${(paperLineOpacity * 100).round()}%'),
                      ],
                    ),
                    Slider(
                      value: paperLineOpacity,
                      min: .03,
                      max: .35,
                      divisions: 32,
                      label: '${(paperLineOpacity * 100).round()}%',
                      onChanged: (value) =>
                          setDialogState(() => paperLineOpacity = value),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Màu bìa',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children:
                          [
                                AppColors.primary,
                                AppColors.dictionary,
                                AppColors.explain,
                                AppColors.weakness,
                                const Color(0xff9b5d48),
                              ]
                              .map(
                                (color) => InkWell(
                                  onTap: () =>
                                      setDialogState(() => cover = color),
                                  borderRadius: BorderRadius.circular(30),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: cover == color ? 4 : 1,
                                      ),
                                      boxShadow: cover == color
                                          ? [
                                              BoxShadow(
                                                color: color.withValues(
                                                  alpha: .35,
                                                ),
                                                blurRadius: 0,
                                                spreadRadius: 3,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ],
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          if (importPdf) {
                            // Create the PDF notebook only after a real file is chosen.
                            Navigator.pop(context, true);
                            return;
                          }
                          final title = titleController.text.trim().isEmpty
                              ? 'Vở học mới'
                              : titleController.text.trim();
                          createdNotebook = NotebookData(
                            id: DateTime.now().millisecondsSinceEpoch
                                .toString(),
                            title: title,
                            type: 'Vở ghi',
                            pages: 1,
                            color: cover,
                            paperStyle: paperStyle,
                            paperLineOpacity: paperLineOpacity,
                          );
                          widget.state.addNotebook(createdNotebook!);
                          // Let the parent finish the dialog transition before
                          // opening the editor; this avoids replacing the route
                          // while the create dialog is still being dismissed.
                          Navigator.pop(context, false);
                        },
                        child: Text(importPdf ? 'Nhập PDF' : 'Tạo vở'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // showDialog completes when pop starts, before the reverse animation has
    // finished. Keep the controller alive until that route is fully gone.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    titleController.dispose();
    if (!mounted) return;
    if (openImporter != true) {
      final notebook = createdNotebook;
      if (notebook == null) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      widget.state.open(notebook, page: 1);
      if (!context.mounted) return;
      showAppSnack(context, 'Đã tạo vở mới · Trang trắng');
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await _showImportFilesDialog();
  }

  Future<void> _showImportFilesDialog() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'doc',
        'docx',
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'heic',
        'heif',
      ],
    );
    if (!mounted || result.isEmpty) return;
    final paths = result
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => File(path).existsSync())
        .toList();
    if (paths.isEmpty) {
      showAppSnack(context, 'Không đọc được file đã chọn');
      return;
    }
    await _showImportPreview(paths);
  }

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final parentId = widget.state.selectedFolderId;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(parentId == null ? 'Folder mới' : 'Folder con mới'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên folder'),
          onSubmitted: (_) => Navigator.pop(dialogContext, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
    final name = controller.text;
    controller.dispose();
    if (accepted == true) {
      widget.state.createFolder(name, parentId: parentId);
      if (mounted) showAppSnack(context, 'Đã tạo folder');
    }
  }

  Future<bool> _showImportPreview(List<String> inputPaths) async {
    final paths = inputPaths
        .where((path) => File(path).existsSync())
        .where(
          (path) => const {
            'pdf',
            'doc',
            'docx',
            'jpg',
            'jpeg',
            'png',
            'webp',
            'gif',
            'heic',
            'heif',
          }.contains(_extension(path)),
        )
        .toList();
    if (!mounted) return false;
    if (paths.isEmpty) {
      showAppSnack(context, 'Không có PDF hoặc ảnh hợp lệ để nhập');
      return false;
    }
    var imageMode = 'pages';
    var cropImages = false;
    final titleController = TextEditingController(
      text: paths.length > 1 ? 'Bộ ảnh nhập mới' : _fileTitle(paths.first),
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final imagePaths = paths.where((path) => _isImagePath(path)).toList();
          final documentPaths = paths
              .where((path) => !_isImagePath(path))
              .toList();
          return AlertDialog(
            title: const Text('Xem trước file nhập'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Tên vở'),
                    ),
                    const SizedBox(height: 14),
                    if (imagePaths.isNotEmpty) ...[
                      Text(
                        '${imagePaths.length} ảnh đã chọn',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 150,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: imagePaths.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (_, index) => ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(imagePaths[index]),
                              width: 112,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'pages',
                            icon: Icon(Icons.view_agenda_outlined),
                            label: Text('Mỗi ảnh = một trang'),
                          ),
                          ButtonSegment(
                            value: 'one',
                            icon: Icon(Icons.collections_outlined),
                            label: Text('Gộp vào một trang'),
                          ),
                        ],
                        selected: {imageMode},
                        onSelectionChanged: (value) =>
                            setDialogState(() => imageMode = value.first),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: cropImages,
                        onChanged: (value) =>
                            setDialogState(() => cropImages = value),
                        title: const Text('Mở trình cắt ảnh trước khi nhập'),
                        subtitle: const Text(
                          'Cắt từng ảnh rồi mới đưa vào trang.',
                        ),
                      ),
                    ],
                    if (documentPaths.isNotEmpty) ...[
                      const Divider(height: 28),
                      Text(
                        documentPaths.map(_fileName).join(', '),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Mỗi trang PDF sẽ trở thành đúng một trang giấy để ghi chú.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.download_done_outlined),
                label: const Text('Nhập vào thư viện'),
              ),
            ],
          );
        },
      ),
    );
    final importedTitle = titleController.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    titleController.dispose();
    if (!mounted || accepted != true) return false;
    final documents = paths.where((path) => !_isImagePath(path)).toList();
    if (documents.length > 1) {
      showAppSnack(context, 'Hãy nhập từng tệp PDF hoặc Word riêng');
      return false;
    }
    final firstDocument = documents.firstOrNull;
    final isPdf = firstDocument != null && _extension(firstDocument) == 'pdf';
    String? copiedDocument;
    var pdfPages = <String>[];
    try {
      if (firstDocument != null) {
        copiedDocument = await _copyImportedFile(firstDocument);
        if (isPdf) {
          if (!mounted) return false;
          final progress = ValueNotifier('Đang mở PDF…');
          BuildContext? progressContext;
          unawaited(
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) {
                progressContext = dialogContext;
                return PopScope(
                  canPop: false,
                  child: AlertDialog(
                    content: Row(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(width: 18),
                        Expanded(
                          child: ValueListenableBuilder<String>(
                            valueListenable: progress,
                            builder: (_, value, _) => Text(value),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
          await WidgetsBinding.instance.endOfFrame;
          try {
            pdfPages = await _renderPdfPages(
              copiedDocument,
              onProgress: (current, total) =>
                  progress.value = 'Đang xử lý trang $current/$total…',
            );
          } finally {
            final dialogContext = progressContext;
            if (dialogContext != null && dialogContext.mounted) {
              Navigator.pop(dialogContext);
            }
            progress.dispose();
          }
          if (pdfPages.isEmpty) {
            throw const FormatException('PDF không có trang nào');
          }
        }
      }
    } catch (exception) {
      if (mounted) {
        showAppSnack(context, 'Không thể đọc PDF: $exception');
      }
      return false;
    }
    var importedImages = paths.where(_isImagePath).toList();
    if (cropImages) {
      final cropped = <String>[];
      for (final path in importedImages) {
        final resultPath = await _cropImage(path);
        if (resultPath != null) cropped.add(resultPath);
      }
      importedImages = cropped;
    } else {
      importedImages = await Future.wait(importedImages.map(_copyImportedFile));
    }
    if (!mounted) return false;
    final type = firstDocument == null ? 'Vở ghi' : (isPdf ? 'PDF' : 'Word');
    final pageCount = isPdf
        ? pdfPages.length + importedImages.length
        : importedImages.isEmpty
        ? 1
        : (imageMode == 'pages' ? importedImages.length : 1);
    final notebook = NotebookData(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: importedTitle.isEmpty ? 'Tài liệu nhập mới' : importedTitle,
      type: type,
      pages: pageCount,
      color: AppColors.primary,
      // Import into the folder currently being viewed, just like dropping a
      // file onto that folder in the sidebar.
      folderId: widget.state.selectedFolderId,
      paperStyle: PaperStyle.blank,
    );
    widget.state.addNotebook(notebook);
    if (copiedDocument != null && mounted) {
      widget.state.attachSourceDocument(notebook.id, copiedDocument);
    }
    if (isPdf) {
      for (var index = 0; index < pdfPages.length; index++) {
        widget.state.attachImages(notebook.id, index + 1, [pdfPages[index]]);
      }
      for (var index = 0; index < importedImages.length; index++) {
        widget.state.attachImages(notebook.id, pdfPages.length + index + 1, [
          importedImages[index],
        ]);
      }
    } else if (importedImages.isNotEmpty) {
      widget.state.attachImages(
        notebook.id,
        1,
        imageMode == 'pages' ? [importedImages.first] : importedImages,
      );
      if (imageMode == 'pages') {
        for (var index = 1; index < importedImages.length; index++) {
          widget.state.attachImages(notebook.id, index + 1, [
            importedImages[index],
          ]);
        }
      }
    }
    if (!mounted) return false;
    showAppSnack(
      context,
      isPdf
          ? 'Đã nhập ${notebook.title} · ${pdfPages.length} trang PDF'
          : 'Đã nhập ${notebook.title}',
    );
    return true;
  }

  Future<List<String>> _renderPdfPages(
    String sourcePath, {
    void Function(int current, int total)? onProgress,
  }) async {
    final document = await pdfx.PdfDocument.openFile(sourcePath);
    final directory = await getApplicationDocumentsDirectory();
    final targetDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}imports${Platform.pathSeparator}pdf_${DateTime.now().microsecondsSinceEpoch}',
    );
    await targetDirectory.create(recursive: true);
    final renderedPaths = List<String?>.filled(document.pagesCount, null);
    var completed = 0;
    try {
      // iPad can render several PDF pages concurrently. A group of three is
      // fast on iPad Gen 11 without creating a large memory spike on long PDFs.
      const batchSize = 3;
      for (var start = 1; start <= document.pagesCount; start += batchSize) {
        final end = math.min(start + batchSize - 1, document.pagesCount);
        await Future.wait([
          for (var pageNumber = start; pageNumber <= end; pageNumber++)
            () async {
              final page = await document.getPage(pageNumber);
              try {
                const targetWidth = 1200.0;
                final image = await page.render(
                  width: targetWidth,
                  height: targetWidth * page.height / page.width,
                  format: pdfx.PdfPageImageFormat.jpeg,
                  quality: 90,
                  backgroundColor: '#FFFFFF',
                );
                if (image == null) {
                  throw FormatException('Không render được trang $pageNumber');
                }
                final target =
                    '${targetDirectory.path}${Platform.pathSeparator}page_${pageNumber.toString().padLeft(4, '0')}.jpg';
                await File(target).writeAsBytes(image.bytes);
                renderedPaths[pageNumber - 1] = target;
                completed++;
                onProgress?.call(completed, document.pagesCount);
              } finally {
                await page.close();
              }
            }(),
        ]);
      }
    } catch (_) {
      if (await targetDirectory.exists()) {
        await targetDirectory.delete(recursive: true);
      }
      rethrow;
    } finally {
      await document.close();
    }
    return renderedPaths.whereType<String>().toList();
  }

  Future<String> _copyImportedFile(String source) async {
    final directory = await getApplicationDocumentsDirectory();
    final targetDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}imports',
    );
    await targetDirectory.create(recursive: true);
    final target =
        '${targetDirectory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_${_fileName(source)}';
    return (await File(source).copy(target)).path;
  }

  Future<String?> _cropImage(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (!mounted) return null;
    // Native iPad photos may arrive as HEIC/HEIF. The editor can display
    // those files even when the pure-Dart crop decoder cannot decode them.
    if (decoded == null) return _copyImportedFile(sourcePath);
    var left = .04;
    var top = .04;
    var right = .04;
    var bottom = .04;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cắt ảnh'),
          content: SizedBox(
            width: 640,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
                _CropSlider(
                  label: 'Trái',
                  value: left,
                  onChanged: (v) => setDialogState(() => left = v),
                ),
                _CropSlider(
                  label: 'Trên',
                  value: top,
                  onChanged: (v) => setDialogState(() => top = v),
                ),
                _CropSlider(
                  label: 'Phải',
                  value: right,
                  onChanged: (v) => setDialogState(() => right = v),
                ),
                _CropSlider(
                  label: 'Dưới',
                  value: bottom,
                  onChanged: (v) => setDialogState(() => bottom = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Bỏ qua'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cắt và dùng'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return _copyImportedFile(sourcePath);
    final x = (decoded.width * left).round();
    final y = (decoded.height * top).round();
    final width = (decoded.width * (1 - left - right)).round().clamp(
      1,
      decoded.width - x,
    );
    final height = (decoded.height * (1 - top - bottom)).round().clamp(
      1,
      decoded.height - y,
    );
    final cropped = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    final directory = await getApplicationDocumentsDirectory();
    final targetDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}imports',
    );
    await targetDirectory.create(recursive: true);
    final target =
        '${targetDirectory.path}${Platform.pathSeparator}crop_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(target).writeAsBytes(img.encodePng(cropped), flush: true);
    return target;
  }

  String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;
  String _fileTitle(String path) => _fileName(path).split('.').first;
  String _extension(String path) =>
      _fileName(path).split('.').last.toLowerCase();
  bool _isImagePath(String path) => const {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'heic',
    'heif',
  }.contains(_extension(path));

  String _paperName(PaperStyle style) => switch (style) {
    PaperStyle.blank => 'Trắng',
    PaperStyle.lined => 'Kẻ ngang',
    PaperStyle.grid => 'Ô vuông',
    PaperStyle.dotted => 'Chấm',
    PaperStyle.genkou => 'Genkō',
  };

  Future<void> _showNotebookMenu(NotebookData notebook) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Mở vở'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Di chuy\u1ec3n v\u00e0o folder'),
              onTap: () => Navigator.pop(context, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Cài đặt giấy'),
              subtitle: const Text('Kiểu giấy và độ đậm đường kẻ'),
              onTap: () => Navigator.pop(context, 'paper'),
            ),
            ListTile(
              leading: Icon(
                notebook.isPinned ? Icons.star : Icons.star_border,
                color: Colors.amber,
              ),
              title: Text(notebook.isPinned ? 'Bỏ yêu thích' : 'Yêu thích'),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Xóa vở'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'open') {
      widget.state.open(notebook);
    } else if (action == 'move') {
      await _moveNotebookToFolder(notebook);
    } else if (action == 'paper') {
      await _showNotebookPaperSettings(notebook);
    } else if (action == 'pin') {
      widget.state.pinNotebook(notebook.id);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Xóa vở này?'),
          content: Text(
            'Toàn bộ nội dung “${notebook.title}” sẽ bị gỡ khỏi thư viện.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xóa'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      widget.state.removeNotebook(notebook.id);
      showAppSnack(context, 'Đã xóa ${notebook.title}');
    }
  }

  Future<void> _moveNotebookToFolder(NotebookData notebook) async {
    final target = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text(
                'T\u1ea5t c\u1ea3 ghi ch\u00fa (b\u1ecf folder)',
              ),
              onTap: () => Navigator.pop(sheetContext, 'root'),
            ),
            for (final folder in widget.state.folders.where(
              (item) => !item.isTrashed,
            ))
              ListTile(
                leading: Icon(Icons.folder, color: Color(folder.color)),
                title: Text(folder.name),
                selected: folder.id == notebook.folderId,
                onTap: () => Navigator.pop(sheetContext, folder.id),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    final folderId = target == 'root' ? null : target;
    if (folderId == notebook.folderId) return;
    if (widget.state.moveNotebookToFolder(notebook.id, folderId) && mounted) {
      showAppSnack(
        context,
        '\u0110\u00e3 di chuy\u1ec3n ghi ch\u00fa v\u00e0o folder',
      );
    }
  }

  Future<void> _showNotebookPaperSettings(NotebookData notebook) async {
    var style = notebook.paperStyle;
    var opacity = notebook.paperLineOpacity;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Cài đặt giấy · ${notebook.title}'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kiểu giấy',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: PaperStyle.values
                      .map(
                        (value) => ChoiceChip(
                          label: Text(_paperName(value)),
                          selected: style == value,
                          onSelected: (_) =>
                              setDialogState(() => style = value),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Độ đậm đường kẻ',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text('${(opacity * 100).round()}%'),
                  ],
                ),
                Slider(
                  value: opacity,
                  min: .03,
                  max: .35,
                  divisions: 32,
                  label: '${(opacity * 100).round()}%',
                  onChanged: (value) => setDialogState(() => opacity = value),
                ),
                _NotebookPreview(
                  paperStyle: style,
                  cover: notebook.color,
                  lineOpacity: opacity,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || accepted != true) return;
    widget.state.updateNotebook(
      notebook.copyWith(paperStyle: style, paperLineOpacity: opacity),
    );
    showAppSnack(context, 'Đã cập nhật giấy của ${notebook.title}');
  }
}

class _NotebookPreview extends StatelessWidget {
  const _NotebookPreview({
    required this.paperStyle,
    required this.cover,
    required this.lineOpacity,
  });
  final PaperStyle paperStyle;
  final Color cover;
  final double lineOpacity;

  @override
  Widget build(BuildContext context) => Container(
    height: 86,
    decoration: BoxDecoration(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Container(
          width: 12,
          decoration: BoxDecoration(
            color: cover,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(11),
            ),
          ),
        ),
        Expanded(
          child: CustomPaint(
            painter: _PreviewPaperPainter(paperStyle, lineOpacity),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Xem trước trang giấy\n日本語のノート',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PreviewPaperPainter extends CustomPainter {
  const _PreviewPaperPainter(this.style, this.lineOpacity);
  final PaperStyle style;
  final double lineOpacity;
  @override
  void paint(Canvas canvas, Size size) {
    if (style == PaperStyle.blank) return;
    final paint = Paint()
      ..color = const Color(0xff758ab4).withValues(alpha: lineOpacity)
      ..strokeWidth = .6;
    final step = style == PaperStyle.lined ? 24.0 : 18.0;
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    if (style == PaperStyle.grid) {
      for (double x = step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPaperPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.lineOpacity != lineOpacity;
}

class _CropSlider extends StatelessWidget {
  const _CropSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 52, child: Text(label)),
      Expanded(
        child: Slider(value: value, min: 0, max: .4, onChanged: onChanged),
      ),
      SizedBox(width: 42, child: Text('${(value * 100).round()}%')),
    ],
  );
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({
    required this.notebook,
    this.coverPath,
    required this.onTap,
    required this.onMenu,
    this.selected = false,
    this.onLongPress,
  });
  final NotebookData notebook;
  final String? coverPath;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final bool selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: notebook.color,
                    borderRadius: BorderRadius.circular(16),
                    border: selected
                        ? Border.all(color: AppColors.primary, width: 3)
                        : null,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (coverPath != null)
                        Image.file(
                          File(coverPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      if (coverPath != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                notebook.color.withValues(alpha: .2),
                                notebook.color.withValues(alpha: .82),
                              ],
                            ),
                          ),
                        ),
                      if (selected)
                        const Positioned(
                          right: 10,
                          top: 10,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.check,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ),
                        ),
                      Positioned(
                        right: -14,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              notebook.type,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            notebook.isPdf ? '日本語\n総まとめ' : '日本語\nノート',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 2,
                            width: 50,
                            color: Colors.white.withValues(alpha: .7),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      notebook.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: onMenu,
                    tooltip: 'Tùy chọn vở',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
              Text(
                '${notebook.pages} trang · ${notebook.lastOpened}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateCard extends StatelessWidget {
  const _CreateCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xffdce1ff),
            child: Icon(Icons.add_rounded, color: AppColors.primary, size: 30),
          ),
          SizedBox(height: 14),
          Text(
            'Tạo vở mới',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          SizedBox(height: 5),
          Text('Vở trắng hoặc PDF', style: TextStyle(color: Colors.grey)),
        ],
      ),
    ),
  );
}
