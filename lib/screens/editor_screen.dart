import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/common.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.state, required this.notebook});
  final AppState state;
  final NotebookData notebook;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EditorTool tool = EditorTool.pen;
  Color penColor = AppColors.ink;
  Color highlightColor = const Color(0x88f4c542);
  double penWidth = 3;
  double penOpacity = 1;
  double highlightWidth = 22;
  double highlightOpacity = .64;
  bool railOpen = true;
  bool rulerVisible = false;
  bool pageLocked = false;
  bool annotationsVisible = true;
  int pageRotation = 0;
  double zoom = 1;
  late List<InkStroke> strokes;
  final List<InkStroke> redo = [];
  List<StrokePoint>? activePoints;
  Offset? selectionStart;
  Offset? selectionEnd;
  bool processing = false;
  _SmartResult? result;
  String? error;
  final GlobalKey _pageBoundaryKey = GlobalKey();
  final Map<int, Offset> _touchStarts = {};
  DateTime? _firstTouchAt;
  bool _twoFingerCandidate = false;
  double _resultRight = 24;
  double _resultTop = 24;
  String? _latestOcrText;
  String? _latestCropPath;
  int _aiRequestSerial = 0;
  bool _resultEditing = false;
  double _resultWidth = 410;
  double _resultHeight = 530;
  double _resultOpacity = 1;
  double _resultEditRight = 24;
  double _resultEditTop = 24;
  double _resultEditWidth = 410;
  double _resultEditHeight = 530;
  double _resultEditOpacity = 1;
  final TextEditingController _quickDictionaryController =
      TextEditingController();
  final FocusNode _quickDictionaryFocus = FocusNode();
  Timer? _quickDictionaryDebounce;
  List<DictionaryEntry> _quickDictionaryResults = const [];
  bool _quickDictionaryOpen = false;
  bool _quickDictionaryLoading = false;
  int _quickDictionaryRequestSerial = 0;
  bool _quickDictionaryEditing = false;
  double _quickRight = 24;
  double _quickTop = 24;
  double _quickWidth = 390;
  double _quickHeight = 520;
  double _quickOpacity = 1;
  double _quickEditRight = 24;
  double _quickEditTop = 24;
  double _quickEditWidth = 390;
  double _quickEditHeight = 520;
  double _quickEditOpacity = 1;

  @override
  void initState() {
    super.initState();
    strokes = List.of(widget.state.strokesFor(widget.notebook.id));
    if (widget.state.focusSource) {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          showAppSnack(
            context,
            'Đã mở đúng vùng nguồn · Trang ${widget.state.openPage}',
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _quickDictionaryDebounce?.cancel();
    _quickDictionaryController.dispose();
    _quickDictionaryFocus.dispose();
    super.dispose();
  }

  void _beginResultEdit() {
    setState(() {
      _resultEditing = true;
      _resultEditRight = _resultRight;
      _resultEditTop = _resultTop;
      _resultEditWidth = _resultWidth;
      _resultEditHeight = _resultHeight;
      _resultEditOpacity = _resultOpacity;
    });
  }

  void _cancelResultEdit() {
    setState(() {
      _resultRight = _resultEditRight;
      _resultTop = _resultEditTop;
      _resultWidth = _resultEditWidth;
      _resultHeight = _resultEditHeight;
      _resultOpacity = _resultEditOpacity;
      _resultEditing = false;
    });
  }

  void _confirmResultEdit() => setState(() => _resultEditing = false);

  void _moveResult(Offset delta) {
    if (!_resultEditing) return;
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _resultRight = (_resultRight - delta.dx).clamp(
        8.0,
        math.max(8.0, size.width - _resultWidth - 8),
      );
      _resultTop = (_resultTop + delta.dy).clamp(
        8.0,
        math.max(8.0, size.height - _resultHeight - 8),
      );
    });
  }

  void _resizeResult(Offset delta) {
    if (!_resultEditing) return;
    final size = MediaQuery.sizeOf(context);
    setState(() {
      final nextWidth = (_resultWidth + delta.dx)
          .clamp(280.0, math.max(280.0, size.width - _resultRight - 16))
          .toDouble();
      _resultWidth = nextWidth;
      _resultRight = (_resultRight - delta.dx).clamp(
        8.0,
        math.max(8.0, size.width - nextWidth - 8),
      );
      _resultHeight = (_resultHeight + delta.dy).clamp(
        220.0,
        math.max(220.0, size.height - _resultTop - 16),
      );
    });
  }

  void _beginQuickDictionaryEdit() {
    setState(() {
      _quickDictionaryEditing = true;
      _quickEditRight = _quickRight;
      _quickEditTop = _quickTop;
      _quickEditWidth = _quickWidth;
      _quickEditHeight = _quickHeight;
      _quickEditOpacity = _quickOpacity;
    });
  }

  void _cancelQuickDictionaryEdit() {
    setState(() {
      _quickRight = _quickEditRight;
      _quickTop = _quickEditTop;
      _quickWidth = _quickEditWidth;
      _quickHeight = _quickEditHeight;
      _quickOpacity = _quickEditOpacity;
      _quickDictionaryEditing = false;
    });
  }

  void _confirmQuickDictionaryEdit() =>
      setState(() => _quickDictionaryEditing = false);

  void _moveQuickDictionary(Offset delta) {
    if (!_quickDictionaryEditing) return;
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _quickRight = (_quickRight - delta.dx).clamp(
        8.0,
        math.max(8.0, size.width - _quickWidth - 8),
      );
      _quickTop = (_quickTop + delta.dy).clamp(
        8.0,
        math.max(8.0, size.height - _quickHeight - 8),
      );
    });
  }

  void _resizeQuickDictionary(Offset delta) {
    if (!_quickDictionaryEditing) return;
    final size = MediaQuery.sizeOf(context);
    setState(() {
      final nextWidth = (_quickWidth + delta.dx)
          .clamp(280.0, math.max(280.0, size.width - _quickRight - 16))
          .toDouble();
      _quickWidth = nextWidth;
      _quickRight = (_quickRight - delta.dx).clamp(
        8.0,
        math.max(8.0, size.width - nextWidth - 8),
      );
      _quickHeight = (_quickHeight + delta.dy).clamp(
        260.0,
        math.max(260.0, size.height - _quickTop - 16),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The software keyboard should float over the notebook instead of
      // shrinking the page, toolbar and floating lookup windows.
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  if (railOpen)
                    _PageRail(
                      currentPage: widget.state.openPage,
                      pageCount: widget.notebook.pages,
                      onPageSelected: widget.state.goToPage,
                      onAddPage: _askCreatePage,
                      onClose: () => setState(() => railOpen = false),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        _buildToolbar(),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onHorizontalDragEnd: pageLocked
                                      ? null
                                      : _onPageSwipe,
                                  child: _buildWorkspace(),
                                ),
                              ),
                              if (processing)
                                Positioned(
                                  right: 28,
                                  top: 28,
                                  child: _ProcessingChip(
                                    label: tool == EditorTool.dictionary
                                        ? 'Đang nhận dạng...'
                                        : tool == EditorTool.aiDictionary
                                        ? 'Đang tra từ bằng AI...'
                                        : tool == EditorTool.weakness
                                        ? 'Đang tạo bản nháp...'
                                        : 'Đang đọc vùng chọn...',
                                    onCancel: () {
                                      _cancelPendingAi();
                                      setState(() {
                                        selectionStart = null;
                                        selectionEnd = null;
                                      });
                                    },
                                  ),
                                ),
                              if (error != null)
                                Positioned(
                                  right: 24,
                                  top: 24,
                                  child: _ErrorCard(
                                    message: error!,
                                    onRetry: _processSelection,
                                    onClose: () => setState(() => error = null),
                                  ),
                                ),
                              if (result != null)
                                Positioned(
                                  right: _resultRight,
                                  top: _resultTop,
                                  child: _ResultCard(
                                    result: result!,
                                    width: _resultWidth,
                                    height: _resultHeight,
                                    opacity: _resultOpacity,
                                    editing: _resultEditing,
                                    onClose: () =>
                                        setState(() => result = null),
                                    onPin: _pinResult,
                                    onWeakness: _openWeaknessDraft,
                                    onEdit: _beginResultEdit,
                                    onCancelEdit: _cancelResultEdit,
                                    onConfirmEdit: _confirmResultEdit,
                                    onDrag: _moveResult,
                                    onResize: _resizeResult,
                                    onOpacityChanged: (value) =>
                                        setState(() => _resultOpacity = value),
                                  ),
                                ),
                              if (_quickDictionaryOpen)
                                Positioned(
                                  right: _quickRight,
                                  top: _quickTop,
                                  child: _QuickDictionaryCard(
                                    controller: _quickDictionaryController,
                                    focusNode: _quickDictionaryFocus,
                                    loading: _quickDictionaryLoading,
                                    results: _quickDictionaryResults,
                                    onChanged: _onQuickDictionaryChanged,
                                    onClear: _clearQuickDictionary,
                                    onSelect: _selectQuickDictionaryEntry,
                                    onClose: _toggleQuickDictionary,
                                    width: _quickWidth,
                                    height: _quickHeight,
                                    opacity: _quickOpacity,
                                    editing: _quickDictionaryEditing,
                                    onEdit: _beginQuickDictionaryEdit,
                                    onCancelEdit: _cancelQuickDictionaryEdit,
                                    onConfirmEdit: _confirmQuickDictionaryEdit,
                                    onDrag: _moveQuickDictionary,
                                    onResize: _resizeQuickDictionary,
                                    onOpacityChanged: (value) =>
                                        setState(() => _quickOpacity = value),
                                  ),
                                ),
                              Positioned(
                                right: 20,
                                bottom: 18,
                                child: _ZoomControl(
                                  zoom: zoom,
                                  enabled: !pageLocked,
                                  onChanged: (value) => setState(
                                    () => zoom = value.clamp(.7, 1.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            IconButton(
              onPressed: widget.state.closeEditor,
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              tooltip: 'Về thư viện',
            ),
            if (!railOpen)
              IconButton(
                onPressed: () => setState(() => railOpen = true),
                icon: const Icon(Icons.view_sidebar_outlined),
                tooltip: 'Hiện trang',
              ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      widget.notebook.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (widget.notebook.isPdf) ...[
                      const SizedBox(width: 8),
                      const _TinyBadge(label: 'PDF · Chỉ ghi chú'),
                    ],
                  ],
                ),
                Text(
                  'Trang ${widget.state.openPage} · Đã lưu',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              onPressed: _undo,
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'Hoàn tác',
            ),
            IconButton(
              onPressed: _redo,
              icon: const Icon(Icons.redo_rounded),
              tooltip: 'Làm lại',
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: _showNotebookSearch,
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Tìm trong vở',
            ),
            IconButton(
              onPressed: _shareNotebook,
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: 'Chia sẻ',
            ),
            PopupMenuButton<String>(
              tooltip: 'Tùy chọn trang',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) {
                switch (value) {
                  case 'hide':
                    setState(() => annotationsVisible = !annotationsVisible);
                    showAppSnack(
                      context,
                      annotationsVisible
                          ? 'Đã hiện annotations'
                          : 'Đã ẩn annotations',
                    );
                  case 'rotate':
                    setState(() => pageRotation = (pageRotation + 1) % 4);
                    showAppSnack(context, 'Đã xoay trang');
                  case 'export':
                    _exportCurrentPage();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'hide',
                  child: Text(
                    annotationsVisible ? 'Ẩn annotations' : 'Hiện annotations',
                  ),
                ),
                PopupMenuItem(value: 'rotate', child: Text('Xoay trang')),
                PopupMenuItem(
                  value: 'export',
                  child: Text('Xuất PDF có ghi chú'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          IconButton(
            tooltip: widget.state.touchWritingEnabled
                ? 'Viết bằng tay: Bật'
                : 'Bật viết tay',
            isSelected: widget.state.touchWritingEnabled,
            style: IconButton.styleFrom(
              backgroundColor: widget.state.touchWritingEnabled
                  ? AppColors.primary.withValues(alpha: .14)
                  : null,
              foregroundColor: widget.state.touchWritingEnabled
                  ? AppColors.primary
                  : null,
            ),
            onPressed: () {
              setState(
                () => widget.state.touchWritingEnabled =
                    !widget.state.touchWritingEnabled,
              );
              widget.state.saveGeneralSettings();
            },
            icon: const Icon(Icons.touch_app_rounded),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: pageLocked ? 'Mở khóa trang' : 'Khóa trang',
            isSelected: pageLocked,
            style: IconButton.styleFrom(
              backgroundColor: pageLocked
                  ? AppColors.primary.withValues(alpha: .14)
                  : null,
              foregroundColor: pageLocked ? AppColors.primary : null,
            ),
            onPressed: () => setState(() => pageLocked = !pageLocked),
            icon: Icon(
              pageLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            ),
          ),
          const SizedBox(width: 8),
          _ToolButton(
            tool: EditorTool.pen,
            selected: tool == EditorTool.pen,
            onTap: () => _selectTool(EditorTool.pen),
          ),
          _ToolButton(
            tool: EditorTool.highlighter,
            selected: tool == EditorTool.highlighter,
            onTap: () => _selectTool(EditorTool.highlighter),
          ),
          _ToolButton(
            tool: EditorTool.eraser,
            selected: tool == EditorTool.eraser,
            onTap: () => _selectTool(EditorTool.eraser),
          ),
          _ToolButton(
            tool: EditorTool.ruler,
            selected: rulerVisible,
            onTap: _toggleRuler,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: VerticalDivider(indent: 8, endIndent: 8),
          ),
          _ToolButton(
            tool: EditorTool.dictionary,
            selected: tool == EditorTool.dictionary,
            onTap: () => _selectTool(EditorTool.dictionary),
          ),
          _ToolButton(
            tool: EditorTool.quickDictionary,
            selected: _quickDictionaryOpen,
            onTap: _toggleQuickDictionary,
          ),
          _ToolButton(
            tool: EditorTool.aiDictionary,
            selected: tool == EditorTool.aiDictionary,
            onTap: () => _selectTool(EditorTool.aiDictionary),
          ),
          _ToolButton(
            tool: EditorTool.translate,
            selected: tool == EditorTool.translate,
            onTap: () => _selectTool(EditorTool.translate),
          ),
          _ToolButton(
            tool: EditorTool.explain,
            selected: tool == EditorTool.explain,
            onTap: () => _selectTool(EditorTool.explain),
          ),
          _ToolButton(
            tool: EditorTool.weakness,
            selected: tool == EditorTool.weakness,
            onTap: () => _selectTool(EditorTool.weakness),
          ),
        ],
      ),
    );
  }

  void _onPageSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 420) return;
    if (velocity < 0) {
      if (widget.state.openPage < widget.notebook.pages) {
        widget.state.goToPage(widget.state.openPage + 1);
      } else {
        _askCreatePage();
      }
    } else if (widget.state.openPage > 1) {
      widget.state.goToPage(widget.state.openPage - 1);
    } else {
      showAppSnack(context, 'Đây là trang đầu tiên');
    }
  }

  Future<void> _askCreatePage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bạn đang ở trang cuối'),
        content: const Text(
          'Vuốt tiếp để tạo trang mới. Chọn kiểu trang bạn muốn thêm vào vở.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Để sau'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'blank'),
            icon: const Icon(Icons.insert_drive_file_outlined),
            label: const Text('Tạo trang trắng'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'new'),
            icon: const Icon(Icons.add),
            label: const Text('Tạo trang mới'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    widget.state.addPage(widget.notebook.id, blank: choice == 'blank');
    showAppSnack(
      context,
      choice == 'blank' ? 'Đã tạo trang trắng' : 'Đã tạo trang mới',
    );
  }

  Future<void> _showNotebookSearch() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = controller.text.trim().toLowerCase();
          final pages = List<int>.generate(widget.notebook.pages, (i) => i + 1)
              .where(
                (page) =>
                    query.isEmpty ||
                    '$page'.contains(query) ||
                    widget.notebook.title.toLowerCase().contains(query),
              )
              .take(30)
              .toList();
          return AlertDialog(
            title: const Text('Tìm trong vở'),
            content: SizedBox(
              width: 420,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Nhập số trang hoặc tên vở',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: pages.isEmpty
                        ? const Center(child: Text('Không tìm thấy trang'))
                        : ListView.builder(
                            itemCount: pages.length,
                            itemBuilder: (_, index) => ListTile(
                              leading: const Icon(Icons.description_outlined),
                              title: Text('Trang ${pages[index]}'),
                              subtitle: Text(widget.notebook.title),
                              onTap: () {
                                widget.state.goToPage(pages[index]);
                                Navigator.pop(dialogContext);
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Đóng'),
              ),
            ],
          );
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  Future<void> _shareNotebook() async {
    final details =
        '${widget.notebook.title}\nTrang ${widget.state.openPage}/${widget.notebook.pages}';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Sao chép thông tin trang'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: details));
                Navigator.pop(context);
                showAppSnack(this.context, 'Đã sao chép thông tin trang');
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Xuất ảnh trang hiện tại'),
              onTap: () {
                Navigator.pop(context);
                _exportCurrentPage();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCurrentPage() async {
    try {
      final boundary =
          _pageBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw const FormatException('Không thể chụp trang');
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw const FormatException('Không thể tạo ảnh');
      final directory = await getApplicationDocumentsDirectory();
      final exportDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}exports',
      );
      await exportDirectory.create(recursive: true);
      final path =
          '${exportDirectory.path}${Platform.pathSeparator}${widget.notebook.id}_page_${widget.state.openPage}.png';
      await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      if (mounted) showAppSnack(context, 'Đã xuất ảnh trang hiện tại');
    } catch (exception) {
      if (mounted) showAppSnack(context, _friendlyError(exception));
    }
  }

  Widget _buildWorkspace() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetHeight = math.min(constraints.maxHeight - 26, 770.0) * zoom;
        final targetWidth = targetHeight * .72;
        return InteractiveViewer(
          panEnabled: !pageLocked,
          scaleEnabled: !pageLocked,
          minScale: .7,
          maxScale: 2.5,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Center(
              child: SizedBox(
                width: targetWidth,
                height: targetHeight,
                child: Transform.rotate(
                  angle: pageRotation * math.pi / 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x24000000),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRect(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _onPointerDown,
                        onPointerMove: _onPointerMove,
                        onPointerUp: _onPointerUp,
                        onPointerCancel: _onPointerCancel,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: RepaintBoundary(
                                key: _pageBoundaryKey,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CustomPaint(
                                      painter: _PaperPainter(
                                        style: widget.notebook.paperStyle,
                                        isPdf:
                                            widget.notebook.isPdf &&
                                            !widget.state.blankPages.contains(
                                              '${widget.notebook.id}:${widget.state.openPage}',
                                            ),
                                      ),
                                    ),
                                    if (widget.notebook.isPdf &&
                                        !widget.state.blankPages.contains(
                                          '${widget.notebook.id}:${widget.state.openPage}',
                                        ))
                                      _PrintedPage(isPdf: true),
                                    if (widget.state
                                        .imagesForPage(
                                          widget.notebook.id,
                                          widget.state.openPage,
                                        )
                                        .isNotEmpty)
                                      Positioned.fill(
                                        child: _PageImageLayer(
                                          paths: widget.state.imagesForPage(
                                            widget.notebook.id,
                                            widget.state.openPage,
                                          ),
                                        ),
                                      ),
                                    CustomPaint(
                                      painter: _InkPainter(
                                        strokes: strokes,
                                        activePoints: activePoints,
                                        activeColor:
                                            tool == EditorTool.highlighter
                                            ? highlightColor.withValues(
                                                alpha: highlightOpacity,
                                              )
                                            : penColor.withValues(
                                                alpha: penOpacity,
                                              ),
                                        activeWidth:
                                            tool == EditorTool.highlighter
                                            ? highlightWidth
                                            : penWidth,
                                        selectionStart: null,
                                        selectionEnd: null,
                                        selectionTool: tool,
                                        sourcePulse: false,
                                      ),
                                    ),
                                    if (rulerVisible)
                                      const Positioned(
                                        left: 70,
                                        right: 40,
                                        top: 350,
                                        child: _Ruler(),
                                      ),
                                    ...(annotationsVisible
                                        ? widget
                                                  .state
                                                  .pinnedNotes[widget
                                                      .notebook
                                                      .id]
                                                  ?.asMap()
                                                  .entries
                                                  .map(
                                                    (entry) => Positioned(
                                                      right: 22,
                                                      bottom:
                                                          30 + entry.key * 110,
                                                      child: _PinnedNoteCard(
                                                        note: entry.value,
                                                      ),
                                                    ),
                                                  ) ??
                                              const []
                                        : const []),
                                  ],
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _InkPainter(
                                    strokes: const [],
                                    activePoints: null,
                                    activeColor: Colors.transparent,
                                    activeWidth: 0,
                                    selectionStart: selectionStart,
                                    selectionEnd: selectionEnd,
                                    selectionTool: tool,
                                    sourcePulse: widget.state.focusSource,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _acceptPointer(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch &&
        widget.state.touchWritingEnabled) {
      return true;
    }
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse) {
      return true;
    }
    return !widget.state.palmRejection;
  }

  double _pressure(PointerEvent event) {
    if (!widget.state.pressureEnabled ||
        event.pressureMax <= event.pressureMin) {
      return 1;
    }
    return ((event.pressure - event.pressureMin) /
            (event.pressureMax - event.pressureMin))
        .clamp(.35, 1);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _trackTouchDown(event);
      if (!widget.state.touchWritingEnabled || _touchStarts.length > 1) {
        return;
      }
    }
    if (!_acceptPointer(event)) return;
    _cancelPendingAi();
    error = null;
    // Keep the lookup/AI window visible while the user switches to a writing
    // tool. Starting a new selection is the point where an old result should
    // be replaced, not the first pen stroke used to take notes.
    if (!{
      EditorTool.pen,
      EditorTool.highlighter,
      EditorTool.eraser,
    }.contains(tool)) {
      result = null;
    }
    if (tool == EditorTool.eraser) {
      _eraseNear(event.localPosition);
      return;
    }
    if (tool == EditorTool.pen || tool == EditorTool.highlighter) {
      activePoints = [
        StrokePoint(
          event.localPosition,
          _pressure(event),
          event.timeStamp.inMicroseconds,
        ),
      ];
    } else {
      selectionStart = event.localPosition;
      selectionEnd = event.localPosition;
    }
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      final start = _touchStarts[event.pointer];
      if (start != null && (event.localPosition - start).distance > 14) {
        _twoFingerCandidate = false;
      }
      if (!widget.state.touchWritingEnabled || _touchStarts.length > 1) {
        return;
      }
    }
    if (!_acceptPointer(event)) return;
    if (tool == EditorTool.eraser) {
      _eraseNear(event.localPosition);
    } else if (activePoints != null) {
      final previous = activePoints!.last.offset;
      final smoothed = Offset.lerp(previous, event.localPosition, .58)!;
      if ((smoothed - previous).distance < .45) return;
      activePoints!.add(
        StrokePoint(smoothed, _pressure(event), event.timeStamp.inMicroseconds),
      );
      setState(() {});
    } else if (selectionStart != null) {
      selectionEnd = event.localPosition;
      setState(() {});
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      final wasWriting =
          widget.state.touchWritingEnabled &&
          _touchStarts.length == 1 &&
          !_twoFingerCandidate;
      if (!wasWriting) {
        _trackTouchUp(event);
        return;
      }
      _touchStarts.remove(event.pointer);
      _firstTouchAt = null;
      _twoFingerCandidate = false;
    }
    if (!_acceptPointer(event)) return;
    if (activePoints != null && activePoints!.length > 1) {
      final drawingTool = tool;
      var points = List<StrokePoint>.of(activePoints!);
      if (rulerVisible && drawingTool == EditorTool.pen) {
        points = [
          points.first,
          StrokePoint(points.last.offset, points.last.pressure),
        ];
      }
      strokes.add(
        InkStroke(
          points: points,
          color: drawingTool == EditorTool.highlighter
              ? highlightColor.withValues(alpha: highlightOpacity)
              : penColor.withValues(alpha: penOpacity),
          width: drawingTool == EditorTool.highlighter
              ? highlightWidth
              : penWidth,
          tool: drawingTool,
          createdAt: DateTime.now(),
        ),
      );
      activePoints = null;
      redo.clear();
      widget.state.saveStrokes(widget.notebook.id, strokes);
      setState(() {});
    } else if (selectionStart != null && selectionEnd != null) {
      _processSelection();
    }
  }

  Future<void> _processSelection() async {
    if (selectionStart == null || selectionEnd == null) return;
    final requestSerial = ++_aiRequestSerial;
    setState(() {
      processing = true;
      error = null;
      result = null;
    });
    try {
      final crop = await _captureSelection();
      if (!mounted || requestSerial != _aiRequestSerial) return;
      final visionModelId = widget.state.modelIds[AiModelSlot.vision] ?? '';
      final recognized =
          widget.state.useAiVision &&
              visionModelId.isNotEmpty &&
              widget.state.hasApiKey
          ? await widget.state.aiService.recognizeImageWithAi(
              apiKey: widget.state.apiKey,
              modelId: visionModelId,
              imagePath: crop.path,
            )
          : await widget.state.ocr.recognizeImage(crop.path);
      if (!mounted || requestSerial != _aiRequestSerial) return;
      _latestCropPath = crop.path;
      _latestOcrText = recognized;
      if (tool == EditorTool.dictionary) {
        final entry = await widget.state.dictionary.lookupNormalized(
          recognized,
        );
        if (entry == null) {
          throw const FormatException(
            'Không tìm thấy từ trong từ điển ngoại tuyến',
          );
        }
        if (!mounted) return;
        setState(() => result = _SmartResult.dictionary(entry));
      } else if (tool == EditorTool.aiDictionary) {
        final response = await widget.state.aiService.complete(
          apiKey: widget.state.apiKey,
          modelId: widget.state.modelIdFor(AiTask.dictionary),
          task: AiTask.dictionary,
          text: recognized,
          jlpt: widget.state.jlpt,
          language: widget.state.explanationLanguage,
        );
        if (!mounted || requestSerial != _aiRequestSerial) return;
        setState(
          () => result = _SmartResult.ai(
            tool: tool,
            source: recognized,
            body: response,
          ),
        );
      } else if (tool == EditorTool.weakness) {
        if (!mounted) return;
        await _openWeaknessDraft(
          ocrText: recognized,
          sourceImagePath: crop.path,
          requestSerial: requestSerial,
        );
        return;
      } else {
        final task = tool == EditorTool.translate
            ? AiTask.translate
            : AiTask.explain;
        final response = await widget.state.aiService.complete(
          apiKey: widget.state.apiKey,
          modelId: widget.state.modelIdFor(task),
          task: task,
          text: recognized,
          jlpt: widget.state.jlpt,
          language: widget.state.explanationLanguage,
        );
        if (!mounted || requestSerial != _aiRequestSerial) return;
        setState(
          () => result = _SmartResult.ai(
            tool: tool,
            source: recognized,
            body: response,
          ),
        );
      }
    } catch (exception) {
      if (mounted && requestSerial == _aiRequestSerial) {
        setState(() => error = _friendlyError(exception));
      }
    } finally {
      if (mounted && requestSerial == _aiRequestSerial) {
        setState(() => processing = false);
      }
    }
  }

  void _cancelPendingAi() {
    _aiRequestSerial++;
    if (processing) processing = false;
  }

  Future<void> _finishProcessingAfterOverlay() async {
    if (!mounted || !processing) return;
    // Dialog routes finish their Future before overlay inherited elements are
    // fully removed. Rebuild the parent on the next frame instead.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && processing) setState(() => processing = false);
  }

  void _trackTouchDown(PointerDownEvent event) {
    if (_touchStarts.isEmpty) {
      _firstTouchAt = DateTime.now();
      _twoFingerCandidate = false;
    }
    _touchStarts[event.pointer] = event.localPosition;
    if (_touchStarts.length == 2 &&
        _firstTouchAt != null &&
        DateTime.now().difference(_firstTouchAt!).inMilliseconds <= 180) {
      _twoFingerCandidate = true;
      activePoints = null;
      selectionStart = null;
      selectionEnd = null;
    } else if (_touchStarts.length > 2) {
      _twoFingerCandidate = false;
    }
  }

  void _trackTouchUp(PointerUpEvent event) {
    final shouldUndo =
        _twoFingerCandidate &&
        _touchStarts.length == 2 &&
        _firstTouchAt != null &&
        DateTime.now().difference(_firstTouchAt!).inMilliseconds <= 300;
    _touchStarts.remove(event.pointer);
    if (shouldUndo) {
      _twoFingerCandidate = false;
      _touchStarts.clear();
      HapticFeedback.lightImpact();
      _undo();
      showAppSnack(context, 'Đã hoàn tác · chạm hai ngón');
    }
    if (_touchStarts.isEmpty) {
      _firstTouchAt = null;
      _twoFingerCandidate = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touchStarts.remove(event.pointer);
      if (_touchStarts.isEmpty) {
        _firstTouchAt = null;
        _twoFingerCandidate = false;
      }
      return;
    }
    setState(() {
      activePoints = null;
      selectionStart = null;
      selectionEnd = null;
    });
  }

  Future<_CapturedRegion> _captureSelection() async {
    final start = selectionStart;
    final end = selectionEnd;
    if (start == null || end == null) {
      throw const FormatException('Vùng chọn không hợp lệ');
    }
    final boundary =
        _pageBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw const FormatException('Không thể chụp vùng trang');
    }
    final logicalSize = boundary.size;
    var region = Rect.fromPoints(start, end);
    if (tool == EditorTool.dictionary || tool == EditorTool.aiDictionary) {
      region = region.inflate(18);
    }
    region = region.intersect(Offset.zero & logicalSize);
    if (region.width < 8 || region.height < 8) {
      throw const FormatException('Vùng chọn quá nhỏ. Hãy khoanh lại.');
    }
    const ratio = 2.0;
    final pageImage = await boundary.toImage(pixelRatio: ratio);
    final source = Rect.fromLTWH(
      region.left * ratio,
      region.top * ratio,
      region.width * ratio,
      region.height * ratio,
    );
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final destination = Rect.fromLTWH(0, 0, source.width, source.height);
    canvas.drawImageRect(pageImage, source, destination, Paint());
    final croppedImage = await recorder.endRecording().toImage(
      source.width.ceil(),
      source.height.ceil(),
    );
    final bytes = await croppedImage.toByteData(format: ImageByteFormat.png);
    pageImage.dispose();
    croppedImage.dispose();
    if (bytes == null) {
      throw const FormatException('Không thể tạo ảnh vùng chọn');
    }
    final directory = await getApplicationDocumentsDirectory();
    final cropDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}weakness_crops',
    );
    await cropDirectory.create(recursive: true);
    final path =
        '${cropDirectory.path}${Platform.pathSeparator}crop_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return _CapturedRegion(path);
  }

  String _friendlyError(Object exception) {
    final value = exception.toString();
    if (value.contains('401')) {
      return 'API key không hợp lệ. Hãy kiểm tra trong Cài đặt AI.';
    }
    if (value.contains('quota') || value.contains('402')) {
      return 'Tài khoản OpenRouter đã hết quota.';
    }
    if (value.contains('SocketException')) {
      return 'Mất kết nối mạng. Vùng chọn của bạn vẫn được giữ.';
    }
    return value
        .replaceFirst('Exception: ', '')
        .replaceFirst('FormatException: ', '');
  }

  void _selectTool(EditorTool value) {
    _cancelPendingAi();
    final returningFromQuickLookup =
        _quickDictionaryOpen && _quickDictionaryFocus.hasFocus;
    _quickDictionaryFocus.unfocus();
    if ({
          EditorTool.translate,
          EditorTool.explain,
          EditorTool.weakness,
          EditorTool.aiDictionary,
        }.contains(value) &&
        !widget.state.aiConnected) {
      _showAiRequired(value);
      return;
    }
    if (tool == value &&
        {
          EditorTool.pen,
          EditorTool.highlighter,
          EditorTool.eraser,
        }.contains(value) &&
        !returningFromQuickLookup &&
        result == null &&
        !_quickDictionaryOpen) {
      _showToolOptions(value);
    }
    setState(() {
      tool = value;
      error = null;
      selectionStart = null;
      selectionEnd = null;
    });
  }

  void _toggleRuler() {
    _cancelPendingAi();
    setState(() {
      rulerVisible = !rulerVisible;
      // The ruler is an overlay, while the pen remains the active drawing
      // tool, matching the interaction used by Apple Notes.
      tool = EditorTool.pen;
      error = null;
      selectionStart = null;
      selectionEnd = null;
    });
  }

  void _toggleQuickDictionary() {
    _cancelPendingAi();
    final willOpen = !_quickDictionaryOpen;
    setState(() {
      _quickDictionaryOpen = willOpen;
      // Quick lookup is a floating utility. Keep the pen active underneath so
      // the learner can immediately write while the lookup result stays open.
      tool = EditorTool.pen;
      error = null;
      selectionStart = null;
      selectionEnd = null;
    });
    if (willOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quickDictionaryFocus.requestFocus();
      });
    } else {
      _quickDictionaryFocus.unfocus();
    }
  }

  void _onQuickDictionaryChanged(String value) {
    _quickDictionaryDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      ++_quickDictionaryRequestSerial;
      setState(() {
        _quickDictionaryLoading = false;
        _quickDictionaryResults = const [];
      });
      return;
    }
    setState(() => _quickDictionaryLoading = true);
    _quickDictionaryDebounce = Timer(
      const Duration(milliseconds: 220),
      () => _searchQuickDictionary(query),
    );
  }

  Future<void> _searchQuickDictionary(String query) async {
    final serial = ++_quickDictionaryRequestSerial;
    try {
      final entries = await widget.state.dictionary.search(query, limit: 20);
      if (!mounted || serial != _quickDictionaryRequestSerial) return;
      setState(() {
        _quickDictionaryResults = entries;
        _quickDictionaryLoading = false;
      });
    } catch (exception) {
      if (!mounted || serial != _quickDictionaryRequestSerial) return;
      setState(() {
        _quickDictionaryResults = const [];
        _quickDictionaryLoading = false;
        error = _friendlyError(exception);
      });
    }
  }

  void _clearQuickDictionary() {
    _quickDictionaryController.clear();
    _onQuickDictionaryChanged('');
    _quickDictionaryFocus.requestFocus();
  }

  void _selectQuickDictionaryEntry(DictionaryEntry entry) {
    _quickDictionaryFocus.unfocus();
    setState(() {
      result = _SmartResult.dictionary(entry);
      _quickDictionaryOpen = false;
      tool = EditorTool.pen;
      error = null;
    });
  }

  Future<void> _showAiRequired(EditorTool requestedTool) async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded, color: AppColors.explain),
        title: const Text('Chưa thiết lập OpenRouter'),
        content: const Text(
          'Chỉ công cụ AI cần API key. Bút, Highlight, PDF và Tra từ ngoại tuyến vẫn dùng bình thường.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Thiết lập AI'),
          ),
        ],
      ),
    );
    if (!mounted || openSettings != true) return;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) widget.state.goTo(AppDestination.settings);
  }

  Future<void> _showToolOptions(EditorTool selectedTool) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedTool == EditorTool.pen
                    ? 'Bút thư pháp'
                    : selectedTool == EditorTool.highlighter
                    ? 'Highlight'
                    : 'Tẩy',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              if (selectedTool != EditorTool.eraser) ...[
                Wrap(
                  spacing: 12,
                  children:
                      (selectedTool == EditorTool.pen
                              ? [
                                  AppColors.ink,
                                  const Color(0xff244a98),
                                  const Color(0xffb53a3a),
                                  AppColors.dictionary,
                                  const Color(0xff8a5a44),
                                  AppColors.explain,
                                ]
                              : [
                                  const Color(0x88f4c542),
                                  const Color(0x8859ca89),
                                  const Color(0x886aa9e9),
                                  const Color(0x88ef83a7),
                                  const Color(0x88a98ade),
                                ])
                          .map(
                            (color) => InkWell(
                              onTap: () {
                                setSheetState(() {});
                                setState(() {
                                  if (selectedTool == EditorTool.pen) {
                                    penColor = color;
                                  } else {
                                    highlightColor = color;
                                  }
                                });
                              },
                              child: CircleAvatar(
                                backgroundColor: color,
                                radius: 18,
                                child:
                                    ((selectedTool == EditorTool.pen
                                            ? penColor
                                            : highlightColor) ==
                                        color)
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 18,
                                      )
                                    : null,
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _showColorPicker(selectedTool),
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('Chọn màu nâng cao'),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                'Độ dày: ${selectedTool == EditorTool.highlighter ? highlightWidth.round() : penWidth.toStringAsFixed(1)}',
              ),
              Slider(
                value: selectedTool == EditorTool.highlighter
                    ? highlightWidth
                    : penWidth,
                min: selectedTool == EditorTool.highlighter ? 10 : 1,
                max: selectedTool == EditorTool.highlighter ? 40 : 12,
                onChanged: (value) {
                  setSheetState(() {});
                  setState(() {
                    if (selectedTool == EditorTool.highlighter) {
                      highlightWidth = value;
                    } else {
                      penWidth = value;
                    }
                  });
                },
              ),
              if (selectedTool == EditorTool.pen) ...[
                const Text('Độ đậm'),
                Slider(
                  value: penOpacity,
                  min: .35,
                  max: 1,
                  divisions: 13,
                  label: '${(penOpacity * 100).round()}%',
                  onChanged: (value) {
                    setState(() => penOpacity = value);
                    setSheetState(() {});
                  },
                ),
                Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xffdedbd3)),
                  ),
                  child: CustomPaint(
                    painter: _PenPreviewPainter(
                      color: penColor.withValues(alpha: penOpacity),
                      width: penWidth,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Thư pháp hiện đại · nét theo lực bút'),
                  subtitle: const Text(
                    'Làm mượt nét và thay đổi độ rộng theo hướng viết',
                  ),
                  value: widget.state.pressureEnabled,
                  onChanged: (value) {
                    widget.state.pressureEnabled = value;
                    widget.state.saveGeneralSettings();
                    setSheetState(() {});
                  },
                ),
              ],
              if (selectedTool == EditorTool.highlighter) ...[
                const Text('Độ trong suốt · chồng nét sẽ đậm hơn'),
                Slider(
                  value: highlightOpacity,
                  min: .35,
                  max: .85,
                  divisions: 10,
                  label: '${(highlightOpacity * 100).round()}%',
                  onChanged: (value) {
                    setState(() => highlightOpacity = value);
                    setSheetState(() {});
                  },
                ),
                Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xffdedbd3)),
                  ),
                  child: CustomPaint(
                    painter: _HighlighterPreviewPainter(
                      color: highlightColor.withValues(alpha: highlightOpacity),
                      width: highlightWidth,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Đầu dẹt vát 45° · không đổi độ rộng theo lực bút',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
              if (selectedTool == EditorTool.eraser)
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'part', label: Text('Tẩy một phần')),
                    ButtonSegment(value: 'stroke', label: Text('Tẩy cả nét')),
                  ],
                  selected: const {'stroke'},
                  onSelectionChanged: (_) {},
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showColorPicker(EditorTool selectedTool) async {
    final initial = selectedTool == EditorTool.highlighter
        ? highlightColor
        : penColor;
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) {
        var hsv = HSVColor.fromColor(initial);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Chọn màu'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: hsv.toColor(),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ColorSlider(
                    label: 'Sắc độ',
                    value: hsv.hue,
                    min: 0,
                    max: 360,
                    color: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withHue(value)),
                  ),
                  _ColorSlider(
                    label: 'Độ bão hòa',
                    value: hsv.saturation,
                    min: 0,
                    max: 1,
                    color: hsv.toColor(),
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withSaturation(value)),
                  ),
                  _ColorSlider(
                    label: 'Độ sáng',
                    value: hsv.value,
                    min: 0,
                    max: 1,
                    color: hsv.toColor(),
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withValue(value)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, hsv.toColor()),
                child: const Text('Dùng màu này'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (selectedTool == EditorTool.highlighter) {
        highlightColor = picked.withValues(alpha: 1);
      } else {
        penColor = picked.withValues(alpha: 1);
      }
    });
  }

  void _eraseNear(Offset point) {
    final index = strokes.lastIndexWhere(
      (stroke) =>
          stroke.points.any((sample) => (sample.offset - point).distance < 22),
    );
    if (index >= 0) {
      redo.add(strokes.removeAt(index));
      widget.state.saveStrokes(widget.notebook.id, strokes);
      setState(() {});
    }
  }

  void _undo() {
    if (strokes.isEmpty) return;
    redo.add(strokes.removeLast());
    widget.state.saveStrokes(widget.notebook.id, strokes);
    setState(() {});
  }

  void _redo() {
    if (redo.isEmpty) return;
    strokes.add(redo.removeLast());
    widget.state.saveStrokes(widget.notebook.id, strokes);
    setState(() {});
  }

  void _pinResult() {
    final current = result;
    if (current == null) return;
    widget.state.pinNote(
      widget.notebook.id,
      PinnedNote(
        title: current.title,
        body: current.shortBody,
        color: _toolColor(tool),
      ),
    );
    setState(() {
      result = null;
      selectionStart = null;
      selectionEnd = null;
    });
    showAppSnack(context, 'Đã ghim vào trang');
  }

  String _draftSection(String? draft, String heading) {
    if (draft == null || draft.isEmpty) return '';
    final marker = '$heading\n';
    final start = draft.indexOf(marker);
    if (start < 0) return '';
    final contentStart = start + marker.length;
    final end = draft.indexOf('\n\n', contentStart);
    return draft.substring(contentStart, end < 0 ? draft.length : end).trim();
  }

  Future<WeaknessKind?> _chooseWeaknessKind(WeaknessKind initial) {
    var selected = initial;
    return showDialog<WeaknessKind>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bạn muốn ghi điểm yếu loại nào?'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<WeaknessKind>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Loại điểm yếu'),
                  items: WeaknessKind.values
                      .map(
                        (kind) => DropdownMenuItem(
                          value: kind,
                          child: Text(kind.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selected = value);
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(switch (selected) {
                    WeaknessKind.grammar =>
                      'AI sẽ tạo nghĩa, cách chia/cấu trúc và ví dụ.',
                    WeaknessKind.vocabulary =>
                      'AI sẽ tạo cách đọc, nghĩa và ví dụ.',
                    WeaknessKind.kanji =>
                      'AI sẽ tạo cách đọc, nghĩa và Hán Việt.',
                    WeaknessKind.reading =>
                      'AI sẽ tạo ý chính, từ khóa và cách suy luận.',
                    WeaknessKind.other => 'Bạn có thể ghi nội dung tự do.',
                  }, style: const TextStyle(color: Colors.black54)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Tiếp tục'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWeaknessDraft({
    String? ocrText,
    String? sourceImagePath,
    int? requestSerial,
  }) async {
    final activeSerial = requestSerial ?? ++_aiRequestSerial;
    final resolvedOcr =
        ocrText ?? _latestOcrText ?? result?.source ?? 'Không có OCR text';
    final resolvedImage = sourceImagePath ?? _latestCropPath;
    final shortOcr = resolvedOcr.replaceAll('\n', ' ').trim();
    var kind = result?.dictionaryEntry != null
        ? WeaknessKind.vocabulary
        : WeaknessKind.grammar;
    final chosenKind = await _chooseWeaknessKind(kind);
    if (!mounted || chosenKind == null || activeSerial != _aiRequestSerial) {
      await _finishProcessingAfterOverlay();
      return;
    }
    kind = chosenKind;
    String? aiDraft;
    final weaknessModel = widget.state.modelIdFor(AiTask.createWeakPoint);
    if (widget.state.hasApiKey && weaknessModel.isNotEmpty) {
      if (!processing) setState(() => processing = true);
      try {
        aiDraft = await widget.state.aiService.complete(
          apiKey: widget.state.apiKey,
          modelId: weaknessModel,
          task: AiTask.createWeakPoint,
          text: resolvedOcr,
          jlpt: widget.state.jlpt,
          language: widget.state.explanationLanguage,
          weaknessKind: kind.name,
        );
      } catch (_) {
        // A weak-point draft remains usable when the optional AI call fails.
      }
      if (!mounted || activeSerial != _aiRequestSerial) return;
    }
    if (!mounted) return;
    await _finishProcessingAfterOverlay();
    if (!mounted) return;
    final aiMeaning = _draftSection(aiDraft, 'Nghĩa');
    final aiReading = _draftSection(aiDraft, 'Cách đọc');
    final aiHanViet = _draftSection(aiDraft, 'Hán Việt');
    final aiConjugation = _draftSection(aiDraft, 'Cách chia');
    final aiExamples = _draftSection(aiDraft, 'Ví dụ');
    final aiReminder = _draftSection(aiDraft, 'Điểm cần nhớ');
    final aiNote = _draftSection(aiDraft, 'Ghi chú');
    final aiTitle = aiDraft?.split('\n').first.trim() ?? '';
    final titleController = TextEditingController(
      text: result?.dictionaryEntry != null
          ? '${result!.dictionaryEntry!.word}【${result!.dictionaryEntry!.reading}】'
          : aiTitle.isNotEmpty
          ? aiTitle
          : shortOcr.isEmpty
          ? 'Điểm cần ôn'
          : 'Ôn lại ${shortOcr.length > 18 ? '${shortOcr.substring(0, 18)}…' : shortOcr}',
    );
    final contentController = TextEditingController(
      text:
          result?.shortBody ??
          (aiMeaning.isNotEmpty ? aiMeaning : aiDraft) ??
          'Nội dung OCR từ vùng đã khoanh:\n$resolvedOcr',
    );
    final readingController = TextEditingController(
      text: aiReading.isNotEmpty
          ? aiReading
          : result?.dictionaryEntry?.reading ?? '',
    );
    final hanVietController = TextEditingController(text: aiHanViet);
    final conjugationController = TextEditingController(text: aiConjugation);
    final examplesController = TextEditingController(text: aiExamples);
    final reminderController = TextEditingController(
      text: aiReminder.isNotEmpty
          ? aiReminder
          : 'Ghi điều bạn thường nhầm để ôn lại.',
    );
    final noteController = TextEditingController(text: aiNote);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thêm điểm yếu',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const Text(
                              'AI đã tạo bản nháp — hãy kiểm tra trước khi lưu.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.auto_awesome, color: AppColors.weakness),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 90),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xfffff4e8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child:
                        resolvedImage != null &&
                            File(resolvedImage).existsSync()
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(resolvedImage),
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Text(
                            resolvedOcr,
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Văn bản OCR trên thiết bị'),
                    subtitle: const Text(
                      'Có thể đối chiếu với ảnh trước khi lưu',
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(resolvedOcr),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Tên'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<WeaknessKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Loại'),
                    items: WeaknessKind.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => kind = value ?? kind),
                  ),
                  const SizedBox(height: 12),
                  if ({
                    WeaknessKind.vocabulary,
                    WeaknessKind.kanji,
                  }.contains(kind)) ...[
                    TextField(
                      controller: readingController,
                      decoration: const InputDecoration(
                        labelText: 'Cách đọc (よみ / furigana)',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if ({
                    WeaknessKind.vocabulary,
                    WeaknessKind.kanji,
                  }.contains(kind)) ...[
                    TextField(
                      controller: hanVietController,
                      decoration: const InputDecoration(labelText: 'Hán Việt'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: contentController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: kind == WeaknessKind.grammar
                          ? 'Nghĩa / cách dùng'
                          : 'Nghĩa',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (kind == WeaknessKind.grammar) ...[
                    TextField(
                      controller: conjugationController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Cách chia / cấu trúc',
                        hintText: 'Ví dụ: Vます bỏ ます + ながら',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if ({
                    WeaknessKind.grammar,
                    WeaknessKind.vocabulary,
                    WeaknessKind.kanji,
                  }.contains(kind)) ...[
                    TextField(
                      controller: examplesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Ví dụ (mỗi dòng một ví dụ)',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: reminderController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Điểm cần nhớ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú của tôi',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text('N3')),
                      Chip(label: Text('dễ nhầm')),
                      ActionChip(label: Text('+ Tag'), onPressed: null),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () {
                          widget.state.addWeakPoint(
                            WeakPoint(
                              id: DateTime.now().millisecondsSinceEpoch
                                  .toString(),
                              title: titleController.text.trim(),
                              kind: kind,
                              content: contentController.text.trim(),
                              reminder: reminderController.text.trim(),
                              note: noteController.text.trim(),
                              reading: readingController.text.trim(),
                              hanViet: hanVietController.text.trim(),
                              conjugation: conjugationController.text.trim(),
                              examples: examplesController.text
                                  .split('\n')
                                  .map((line) => line.trim())
                                  .where((line) => line.isNotEmpty)
                                  .toList(),
                              tags: ['N3', 'dễ nhầm'],
                              notebookId: widget.notebook.id,
                              notebookTitle: widget.notebook.title,
                              page: widget.state.openPage,
                              ocrText: resolvedOcr,
                              sourceImagePath: resolvedImage,
                              createdAt: DateTime.now(),
                            ),
                          );
                          Navigator.pop(context, true);
                        },
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Lưu điểm yếu'),
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
    titleController.dispose();
    contentController.dispose();
    readingController.dispose();
    hanVietController.dispose();
    conjugationController.dispose();
    examplesController.dispose();
    reminderController.dispose();
    noteController.dispose();
    if (saved != true && resolvedImage != null) {
      try {
        await File(resolvedImage).delete();
      } catch (_) {}
      if (_latestCropPath == resolvedImage) {
        _latestCropPath = null;
        _latestOcrText = null;
      }
    }
    if (saved == true && mounted) {
      setState(() {
        result = null;
        selectionStart = null;
        selectionEnd = null;
      });
      showAppSnack(
        context,
        'Đã lưu vào Điểm yếu',
        actionLabel: 'Xem',
        onAction: () => widget.state.goTo(AppDestination.weaknesses),
      );
    }
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.selected,
    required this.onTap,
  });
  final EditorTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _toolColor(tool);
    final (icon, label) = switch (tool) {
      EditorTool.pen => (Icons.draw_outlined, 'Bút thư pháp'),
      EditorTool.highlighter => (Icons.border_color_outlined, 'Highlight'),
      EditorTool.eraser => (Icons.auto_fix_normal_outlined, 'Tẩy'),
      EditorTool.ruler => (Icons.straighten_rounded, 'Thước'),
      EditorTool.dictionary => (Icons.menu_book_outlined, 'Tra từ'),
      EditorTool.quickDictionary => (Icons.search_rounded, 'Tra từ nhanh'),
      EditorTool.aiDictionary => (Icons.auto_stories_outlined, 'AI Tra từ'),
      EditorTool.translate => (Icons.translate_rounded, 'AI Dịch'),
      EditorTool.explain => (Icons.auto_awesome_outlined, 'AI Giải thích'),
      EditorTool.weakness => (Icons.bookmark_add_outlined, 'Điểm yếu'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? color.withValues(alpha: .14) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(
              color: selected
                  ? color.withValues(alpha: .55)
                  : Colors.transparent,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              width: tool == EditorTool.explain
                  ? 92
                  : tool == EditorTool.pen
                  ? 104
                  : 72,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: selected
                        ? color
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? color : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      SliderTheme(
        data: SliderTheme.of(
          context,
        ).copyWith(activeTrackColor: color, thumbColor: color),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

Color _toolColor(EditorTool tool) => switch (tool) {
  EditorTool.dictionary => AppColors.dictionary,
  EditorTool.quickDictionary => AppColors.dictionary,
  EditorTool.aiDictionary => AppColors.translate,
  EditorTool.translate => AppColors.translate,
  EditorTool.explain => AppColors.explain,
  EditorTool.weakness => AppColors.weakness,
  _ => AppColors.primary,
};

class _PageRail extends StatelessWidget {
  const _PageRail({
    required this.currentPage,
    required this.pageCount,
    required this.onPageSelected,
    required this.onAddPage,
    required this.onClose,
  });
  final int currentPage;
  final int pageCount;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onAddPage;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'TRANG',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: pageCount,
            itemBuilder: (context, index) {
              final page = index + 1;
              final active = page == currentPage;
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 5, 14, 7),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: Semantics(
                    button: true,
                    label: 'Trang $page',
                    onTap: () => onPageSelected(page),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onPageSelected(page),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Column(
                          children: [
                            Container(
                              height: 112,
                              decoration: BoxDecoration(
                                color: AppColors.paper,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: active
                                      ? AppColors.primary
                                      : const Color(0xffdedbd3),
                                  width: active ? 2.5 : 1,
                                ),
                              ),
                              // Keep thumbnails blank until the user writes
                              // or imports content on that page.
                              child: const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$page',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: active
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: active ? AppColors.primary : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: onAddPage,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Thêm trang'),
          ),
        ),
      ],
    ),
  );
}

class _PrintedPage extends StatelessWidget {
  const _PrintedPage({required this.isPdf});
  final bool isPdf;
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.contain,
    alignment: Alignment.topCenter,
    child: SizedBox(
      width: 684,
      height: 950,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(54, 42, 46, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isPdf ? AppColors.weakness : AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPdf ? '読解問題  12' : '文法ノート',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        isPdf ? 'Shinkanzen Master N3' : '〜ながら・〜からといって',
                        style: const TextStyle(
                          color: Color(0xff747684),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            const Text(
              '彼の意見を尊重しながら、',
              style: TextStyle(fontSize: 19, height: 1.8, color: AppColors.ink),
            ),
            const Text(
              'もう一度検討する必要がある。',
              style: TextStyle(fontSize: 19, height: 1.8, color: AppColors.ink),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xfffff5cf),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '〜ながら：Hai hành động xảy ra đồng thời.\nChủ ngữ của hai vế thường giống nhau.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.7,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 34),
            if (isPdf) ...[
              const Text(
                '日本に10年住んでいるからといって、日本語が＿＿＿。',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'A. 上手なはずだ\nB. 上手とは限らない\nC. 上手に違いない\nD. 上手になった',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.9,
                  color: AppColors.ink,
                ),
              ),
            ] else ...[
              const Text(
                '例：音楽を聞きながら、宿題をします。',
                style: TextStyle(fontSize: 15, color: AppColors.ink),
              ),
              const SizedBox(height: 22),
              const Text(
                'Ghi nhớ',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '「ながら」前の động từ dùng thể ます bỏ ます.',
                style: TextStyle(fontSize: 14, color: AppColors.ink),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PageImageLayer extends StatelessWidget {
  const _PageImageLayer({required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ColoredBox(
      color: Colors.white.withValues(alpha: .92),
      child: Column(
        children: paths
            .map(
              (path) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter({required this.style, required this.isPdf});
  final PaperStyle style;
  final bool isPdf;
  @override
  void paint(Canvas canvas, Size size) {
    if (isPdf || style == PaperStyle.blank) return;
    final paint = Paint()
      ..color = const Color(0x16758ab4)
      ..strokeWidth = .8;
    if (style == PaperStyle.lined) {
      for (double y = 72; y < size.height; y += 30) {
        canvas.drawLine(Offset(40, y), Offset(size.width - 30, y), paint);
      }
    } else {
      for (double y = 0; y < size.height; y += 24) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      for (double x = 0; x < size.width; x += 24) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
    canvas.drawLine(
      const Offset(36, 0),
      Offset(36, size.height),
      Paint()
        ..color = const Color(0x22d9822b)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.isPdf != isPdf;
}

class _InkPainter extends CustomPainter {
  const _InkPainter({
    required this.strokes,
    required this.activePoints,
    required this.activeColor,
    required this.activeWidth,
    required this.selectionStart,
    required this.selectionEnd,
    required this.selectionTool,
    required this.sourcePulse,
  });
  final List<InkStroke> strokes;
  final List<StrokePoint>? activePoints;
  final Color activeColor;
  final double activeWidth;
  final Offset? selectionStart;
  final Offset? selectionEnd;
  final EditorTool selectionTool;
  final bool sourcePulse;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(
        canvas,
        stroke.points,
        stroke.color,
        stroke.width,
        stroke.tool == EditorTool.highlighter,
      );
    }
    if (activePoints != null) {
      _drawStroke(
        canvas,
        activePoints!,
        activeColor,
        activeWidth,
        selectionTool == EditorTool.highlighter,
      );
    }
    if (selectionStart != null && selectionEnd != null) {
      final color = _toolColor(selectionTool);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      if (selectionTool == EditorTool.dictionary) {
        canvas.drawLine(
          selectionStart!,
          selectionEnd!,
          Paint()
            ..color = color.withValues(alpha: .34)
            ..strokeWidth = 19
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromPoints(selectionStart!, selectionEnd!),
            const Radius.circular(8),
          ),
          paint,
        );
      }
    }
    if (sourcePulse) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(42, 102, size.width - 84, 92),
          const Radius.circular(10),
        ),
        Paint()
          ..color = AppColors.weakness
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
  }

  void _drawStroke(
    Canvas canvas,
    List<StrokePoint> points,
    Color color,
    double width,
    bool highlight,
  ) {
    if (points.length < 2) return;

    // Build a smoothed centerline from quadratic midpoints, then expand it
    // into a filled left/right mesh. This gives every point its own radius,
    // unlike Canvas.drawPath(strokeWidth), and produces natural tapering.
    final centers = <Offset>[points.first.offset];
    for (var i = 0; i < points.length - 1; i++) {
      centers.add(
        Offset(
          (points[i].offset.dx + points[i + 1].offset.dx) / 2,
          (points[i].offset.dy + points[i + 1].offset.dy) / 2,
        ),
      );
    }
    centers.add(points.last.offset);
    final radii = <double>[];
    for (var i = 0; i < centers.length; i++) {
      final sourceIndex = (i * points.length / centers.length).floor().clamp(
        0,
        points.length - 1,
      );
      final previous = centers[i == 0 ? 0 : i - 1];
      final next = centers[i == centers.length - 1 ? i : i + 1];
      final direction = (next - previous).direction;
      final pressure = points[sourceIndex].pressure.clamp(.35, 1.0);
      final dt = i == 0
          ? 0
          : (points[sourceIndex].timeMicros -
                    points[(sourceIndex - 1).clamp(0, points.length - 1)]
                        .timeMicros)
                .clamp(1, 1000000);
      final distance = (next - previous).distance;
      final speed = dt == 0 ? 0 : distance / dt;
      final speedFactor = (1 - speed * 1800).clamp(.58, 1.0);
      final nibFactor = highlight
          ? 1.0
          : .76 + .28 * math.sin(direction + math.pi / 5).abs();
      var radius =
          width * .5 * (highlight ? 1 : pressure) * speedFactor * nibFactor;
      final startTaper = (i / 4).clamp(0, 1);
      final endTaper = ((centers.length - 1 - i) / 5).clamp(0, 1);
      radius *= math.min(startTaper, endTaper);
      radii.add(radius);
    }
    final path = Path();
    for (var i = 0; i < centers.length; i++) {
      final tangent =
          (centers[i == centers.length - 1 ? i : i + 1] -
                  centers[i == 0 ? i : i - 1])
              .direction;
      final normal = Offset(-math.sin(tangent), math.cos(tangent));
      final left = centers[i] + normal * radii[i];
      if (i == 0) {
        path.moveTo(left.dx, left.dy);
      } else {
        path.lineTo(left.dx, left.dy);
      }
    }
    for (var i = centers.length - 1; i >= 0; i--) {
      final tangent =
          (centers[i == centers.length - 1 ? i : i + 1] -
                  centers[i == 0 ? i : i - 1])
              .direction;
      final normal = Offset(-math.sin(tangent), math.cos(tangent));
      final right = centers[i] - normal * radii[i];
      path.lineTo(right.dx, right.dy);
    }
    path.close();
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = color;
    if (highlight) paint.blendMode = BlendMode.multiply;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}

class _Ruler extends StatelessWidget {
  const _Ruler();
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -.08,
    child: Container(
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xbbdce1ff),
        border: Border.all(color: AppColors.primary.withValues(alpha: .5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          for (var i = 0; i < 20; i++)
            Positioned(
              left: i * 24.0,
              top: 0,
              child: Container(
                width: 1,
                height: i % 5 == 0 ? 20 : 11,
                color: AppColors.primary,
              ),
            ),
          const Center(
            child: Text(
              'Dùng Bút để kẻ · Bấm Thước lần nữa để ẩn',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SmartResult {
  const _SmartResult({
    required this.title,
    required this.source,
    required this.body,
    this.dictionaryEntry,
  });
  factory _SmartResult.dictionary(DictionaryEntry entry) {
    final sections = <String>[
      if (entry.partOfSpeech.trim().isNotEmpty) entry.partOfSpeech.trim(),
      if (entry.hanViet.trim().isNotEmpty) 'Hán Việt: ${entry.hanViet.trim()}',
      entry.meaning.trim(),
      if (entry.example.trim().isNotEmpty) entry.example.trim(),
      if (entry.exampleMeaning.trim().isNotEmpty) entry.exampleMeaning.trim(),
    ];
    return _SmartResult(
      title: entry.word,
      source: entry.reading,
      body: sections.join('\n\n'),
      dictionaryEntry: entry,
    );
  }
  factory _SmartResult.ai({
    required EditorTool tool,
    required String source,
    required String body,
  }) => _SmartResult(
    title: switch (tool) {
      EditorTool.translate => 'Bản dịch',
      EditorTool.aiDictionary => 'AI Tra từ',
      _ => 'Giải thích',
    },
    source: source,
    body: body,
  );
  final String title;
  final String source;
  final String body;
  final DictionaryEntry? dictionaryEntry;
  String get shortBody =>
      body.length > 170 ? '${body.substring(0, 170)}…' : body;
}

class _QuickDictionaryCard extends StatelessWidget {
  const _QuickDictionaryCard({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.results,
    required this.onChanged,
    required this.onClear,
    required this.onSelect,
    required this.onClose,
    required this.width,
    required this.height,
    required this.opacity,
    required this.editing,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onConfirmEdit,
    required this.onDrag,
    required this.onResize,
    required this.onOpacityChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final List<DictionaryEntry> results;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<DictionaryEntry> onSelect;
  final VoidCallback onClose;
  final double width;
  final double height;
  final double opacity;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onConfirmEdit;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onResize;
  final ValueChanged<double> onOpacityChanged;

  @override
  Widget build(BuildContext context) {
    final query = controller.text.trim();
    final screen = MediaQuery.sizeOf(context);
    final cardWidth = math
        .min(width, math.max(220, screen.width - 32))
        .toDouble();
    final cardHeight = math
        .min(height, math.max(260, screen.height - 32))
        .toDouble();
    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: editing
                        ? (details) => onDrag(details.delta)
                        : null,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.menu_book_outlined,
                          color: AppColors.dictionary,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Tra từ nhanh',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (editing) ...[
                          IconButton(
                            onPressed: onCancelEdit,
                            icon: const Icon(Icons.close),
                            tooltip: 'Hủy thay đổi vị trí/kích thước',
                          ),
                          IconButton(
                            onPressed: onConfirmEdit,
                            icon: const Icon(Icons.check_rounded),
                            tooltip: 'Xác nhận vị trí/kích thước',
                          ),
                        ] else ...[
                          IconButton(
                            onPressed: onEdit,
                            icon: const Icon(Icons.open_with_rounded),
                            tooltip: 'Chỉnh vị trí/kích thước',
                          ),
                          IconButton(
                            onPressed: onClose,
                            icon: const Icon(Icons.close),
                            tooltip: 'Đóng tra từ nhanh',
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Text(
                    'Kana · Kanji · Hán Việt · nghĩa tiếng Việt',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  if (editing)
                    Row(
                      children: [
                        const Text('Đậm/nhạt', style: TextStyle(fontSize: 11)),
                        Expanded(
                          child: Slider(
                            value: opacity,
                            min: .35,
                            max: 1,
                            onChanged: onOpacityChanged,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Ví dụ: 食べる, たべる, ăn...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: loading
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: onClear,
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Xóa từ khóa',
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: query.isEmpty
                        ? const _QuickDictionaryMessage(
                            icon: Icons.keyboard_alt_outlined,
                            message:
                                'Gõ từ cần tra để tìm trong kho ngoại tuyến.',
                          )
                        : !loading && results.isEmpty
                        ? const _QuickDictionaryMessage(
                            icon: Icons.search_off_rounded,
                            message: 'Không tìm thấy từ phù hợp.',
                          )
                        : ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = results[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 3,
                                ),
                                onTap: () => onSelect(entry),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${entry.word}【${entry.reading}】',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (entry.level.isNotEmpty)
                                      _TinyBadge(label: entry.level),
                                  ],
                                ),
                                subtitle: Text(
                                  entry.meaning,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            if (editing)
              Positioned(
                right: 5,
                bottom: 5,
                child: GestureDetector(
                  onPanUpdate: (details) => onResize(details.delta),
                  child: const Icon(Icons.drag_handle_rounded, size: 22),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickDictionaryMessage extends StatelessWidget {
  const _QuickDictionaryMessage({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.width,
    required this.height,
    required this.opacity,
    required this.editing,
    required this.onClose,
    required this.onPin,
    required this.onWeakness,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onConfirmEdit,
    required this.onDrag,
    required this.onResize,
    required this.onOpacityChanged,
  });
  final _SmartResult result;
  final double width;
  final double height;
  final double opacity;
  final bool editing;
  final VoidCallback onClose;
  final VoidCallback onPin;
  final VoidCallback onWeakness;
  final VoidCallback onEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onConfirmEdit;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onResize;
  final ValueChanged<double> onOpacityChanged;
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final cardWidth = math
        .min(width, math.max(220, screen.width - 32))
        .toDouble();
    final cardHeight = math
        .min(height, math.max(220, screen.height - 32))
        .toDouble();
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Container(
            width: cardWidth,
            constraints: BoxConstraints(
              minHeight: cardHeight,
              maxHeight: cardHeight,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: editing
                        ? (details) => onDrag(details.delta)
                        : null,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.drag_indicator_rounded,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            result.dictionaryEntry == null
                                ? Icons.auto_awesome
                                : Icons.menu_book_outlined,
                            color: result.dictionaryEntry == null
                                ? AppColors.explain
                                : AppColors.dictionary,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              result.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (editing) ...[
                            IconButton(
                              onPressed: onCancelEdit,
                              icon: const Icon(Icons.close),
                              tooltip: 'Hủy thay đổi vị trí/kích thước',
                            ),
                            IconButton(
                              onPressed: onConfirmEdit,
                              icon: const Icon(Icons.check_rounded),
                              tooltip: 'Xác nhận vị trí/kích thước',
                            ),
                          ] else ...[
                            IconButton(
                              onPressed: onEdit,
                              icon: const Icon(Icons.open_with_rounded),
                              tooltip: 'Chỉnh vị trí/kích thước',
                            ),
                            IconButton(
                              onPressed: onClose,
                              icon: const Icon(Icons.close),
                              tooltip: 'Đóng',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 30, top: 2),
                    child: Text(
                      'Kéo thanh tiêu đề để di chuyển',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ),
                  if (editing)
                    Row(
                      children: [
                        const Text('Đậm/nhạt', style: TextStyle(fontSize: 11)),
                        Expanded(
                          child: Slider(
                            value: opacity,
                            min: .35,
                            max: 1,
                            onChanged: onOpacityChanged,
                          ),
                        ),
                      ],
                    ),
                  if (result.dictionaryEntry != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        const _TinyBadge(label: 'Từ điển ngoại tuyến'),
                        if (result.dictionaryEntry!.level.isNotEmpty)
                          _TinyBadge(
                            label: 'JLPT ${result.dictionaryEntry!.level}',
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Text(
                    result.source,
                    style: TextStyle(
                      fontSize: result.dictionaryEntry != null ? 18 : 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.55,
                    ),
                  ),
                  const Divider(height: 24),
                  Text(
                    result.body,
                    style: const TextStyle(fontSize: 15, height: 1.55),
                  ),
                  if (result.dictionaryEntry case final entry?
                      when entry.similarEntries.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Gợi ý gần nghĩa',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...entry.similarEntries.map(
                      (similar) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${similar.word}【${similar.reading}】',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (similar.level.isNotEmpty)
                                    _TinyBadge(label: similar.level),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                similar.meaning,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: onPin,
                        icon: const Icon(Icons.push_pin_outlined, size: 18),
                        label: const Text('Ghim'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onWeakness,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Điểm yếu'),
                      ),
                      TextButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: result.body));
                          showAppSnack(context, 'Đã sao chép');
                        },
                        child: const Text('Sao chép'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (editing)
            Positioned(
              right: 5,
              bottom: 5,
              child: GestureDetector(
                onPanUpdate: (details) => onResize(details.delta),
                child: const Icon(Icons.drag_handle_rounded, size: 22),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProcessingChip extends StatelessWidget {
  const _ProcessingChip({required this.label, required this.onCancel});
  final String label;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) => Material(
    elevation: 6,
    borderRadius: BorderRadius.circular(30),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Dừng tác vụ',
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: SizedBox(
      width: 340,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Không thể xử lý',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
              ],
            ),
            Text(message),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    ),
  );
}

class _ZoomControl extends StatelessWidget {
  const _ZoomControl({
    required this.zoom,
    required this.enabled,
    required this.onChanged,
  });
  final double zoom;
  final bool enabled;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(20),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: enabled ? () => onChanged(zoom - .1) : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        Text(
          '${(zoom * 100).round()}%',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        IconButton(
          onPressed: enabled ? () => onChanged(zoom + .1) : null,
          icon: const Icon(Icons.add, size: 18),
        ),
        IconButton(
          onPressed: enabled ? () => onChanged(1) : null,
          icon: const Icon(Icons.fit_screen, size: 18),
          tooltip: 'Vừa trang',
        ),
      ],
    ),
  );
}

class _PinnedNoteCard extends StatelessWidget {
  const _PinnedNoteCard({required this.note});
  final PinnedNote note;
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -.025,
    child: Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          note.color.withValues(alpha: .12),
          AppColors.paper,
        ),
        border: Border(left: BorderSide(color: note.color, width: 4)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title,
            style: TextStyle(fontWeight: FontWeight.w800, color: note.color),
          ),
          const SizedBox(height: 5),
          Text(
            note.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, height: 1.35),
          ),
        ],
      ),
    ),
  );
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

class _CapturedRegion {
  const _CapturedRegion(this.path);
  final String path;
}

class _PenPreviewPainter extends CustomPainter {
  const _PenPreviewPainter({required this.color, required this.width});
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width.clamp(1.5, 10);
    final path = Path()
      ..moveTo(20, size.height * .68)
      ..cubicTo(
        size.width * .25,
        size.height * .08,
        size.width * .48,
        size.height * .92,
        size.width * .67,
        size.height * .35,
      )
      ..quadraticBezierTo(
        size.width * .78,
        size.height * .12,
        size.width - 18,
        size.height * .55,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PenPreviewPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.width != width;
}

class _HighlighterPreviewPainter extends CustomPainter {
  const _HighlighterPreviewPainter({required this.color, required this.width});
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final half = (width / 2).clamp(4.0, size.height * .34);
    final y = size.height / 2;
    final path = Path()
      ..moveTo(18, y + half)
      ..lineTo(size.width - 22, y + half)
      ..lineTo(size.width - 12, y - half + 5)
      ..lineTo(28, y - half)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.fill
        ..color = color
        ..blendMode = BlendMode.multiply,
    );
  }

  @override
  bool shouldRepaint(covariant _HighlighterPreviewPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.width != width;
}
