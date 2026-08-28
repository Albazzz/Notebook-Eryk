import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.state});
  final AppState state;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String filter = 'Tất cả';
  String search = '';

  @override
  Widget build(BuildContext context) {
    final notebooks = widget.state.notebooks.where((item) {
      final matchesSearch = item.title.toLowerCase().contains(
        search.toLowerCase(),
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
            trailing: Wrap(
              spacing: 10,
              children: [
                SearchBox(
                  hint: 'Tìm vở...',
                  width: 220,
                  onChanged: (value) => setState(() => search = value),
                ),
                IconButton.filledTonal(
                  onPressed: () {},
                  icon: const Icon(Icons.grid_view_rounded),
                  tooltip: 'Dạng lưới',
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
                      : _NotebookCard(
                          notebook: notebooks[index],
                          onTap: () => widget.state.open(notebooks[index]),
                          onMenu: () => _showNotebookMenu(notebooks[index]),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context) async {
    final titleController = TextEditingController();
    NotebookData? createdNotebook;
    var importPdf = false;
    var paperStyle = PaperStyle.grid;
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
                    _NotebookPreview(paperStyle: paperStyle, cover: cover),
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
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'webp'],
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
                        'PDF và Word được giữ nguyên làm tài liệu để ghi chú.',
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
    if (!mounted || accepted != true) return;
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
    if (!mounted) return;
    final documents = paths.where((path) => !_isImagePath(path)).toList();
    final firstDocument = documents.firstOrNull;
    final type = firstDocument == null
        ? 'Vở ghi'
        : (_extension(firstDocument) == 'pdf' ? 'PDF' : 'Word');
    final notebook = NotebookData(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: importedTitle.isEmpty ? 'Tài liệu nhập mới' : importedTitle,
      type: type,
      pages: importedImages.isEmpty
          ? (type == 'PDF' ? 24 : 12)
          : (imageMode == 'pages' ? importedImages.length : 1),
      color: AppColors.primary,
      paperStyle: PaperStyle.blank,
    );
    widget.state.addNotebook(notebook);
    if (firstDocument != null) {
      final copiedDocument = await _copyImportedFile(firstDocument);
      if (mounted) {
        widget.state.attachSourceDocument(notebook.id, copiedDocument);
      }
    }
    if (importedImages.isNotEmpty) {
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
    if (!mounted) return;
    showAppSnack(context, 'Đã nhập ${notebook.title}');
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
    if (decoded == null || !mounted) return null;
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
  bool _isImagePath(String path) =>
      const {'jpg', 'jpeg', 'png', 'webp'}.contains(_extension(path));

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
}

class _NotebookPreview extends StatelessWidget {
  const _NotebookPreview({required this.paperStyle, required this.cover});
  final PaperStyle paperStyle;
  final Color cover;

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
            painter: _PreviewPaperPainter(paperStyle),
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
  const _PreviewPaperPainter(this.style);
  final PaperStyle style;
  @override
  void paint(Canvas canvas, Size size) {
    if (style == PaperStyle.blank) return;
    final paint = Paint()
      ..color = const Color(0x22758ab4)
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
      oldDelegate.style != style;
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
    required this.onTap,
    required this.onMenu,
  });
  final NotebookData notebook;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                  ),
                  child: Stack(
                    children: [
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
