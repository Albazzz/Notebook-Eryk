import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

import '../app_state.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/color_panel.dart';
import '../widgets/common.dart';
import '../widgets/ocr_highlight_sheet.dart';
import '../widgets/quick_check_sheet.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.state, required this.notebook});
  final AppState state;
  final NotebookData notebook;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  static const _nativeChannel = MethodChannel(
    'com.example.noteeryk/shared_import',
  );

  EditorTool tool = EditorTool.pen;
  Color penColor = AppColors.ink;
  Color highlightColor = const Color(0x88f4c542);
  double penWidth = 3;
  PenStyle penStyle = PenStyle.calligraphy;
  double penOpacity = 1;
  double highlightWidth = 22;
  double highlightOpacity = .64;
  double eraserWidth = 36;
  String eraserMode = 'stroke';
  String? selectedImageId;
  bool railOpen = true;
  bool rulerVisible = false;
  Offset _rulerPosition = const Offset(.12, .38);
  double _rulerWidthFraction = .72;
  double _rulerHeight = 62;
  double _rulerAngle = -.08;
  double _rulerGestureStartWidth = .72;
  double _rulerGestureStartHeight = 62;
  double _rulerGestureStartAngle = -.08;
  bool pageLocked = false;
  bool annotationsVisible = true;

  /// Góc xoay trang để viết (độ, 0–360). Chỉ đổi cách hiển thị; nét vẽ vẫn
  /// lưu theo toạ độ trang nên không bị lệch khi xoay lại.
  double pageAngle = 0;

  /// Xoay bằng hai ngón chỉ bắt đầu sau khi vượt ngưỡng, để chụm/zoom không
  /// làm trang nghiêng.
  static const _rotationStartThreshold = 12.0;
  static const _rotationSnap = 5.0;
  double? _rotationStartVector;
  double _rotationStartPageAngle = 0;
  bool _rotationActive = false;
  double zoom = 1;
  late List<InkStroke> strokes;
  final List<List<InkStroke>> _undoStrokeHistory = [];
  final List<List<InkStroke>> _redoStrokeHistory = [];
  bool _eraserGestureRecorded = false;
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
  double _resultEditRight = 24;
  double _resultEditTop = 24;
  double _resultEditWidth = 410;
  double _resultEditHeight = 530;
  final TextEditingController _quickDictionaryController =
      TextEditingController();
  final FocusNode _quickDictionaryFocus = FocusNode();
  Timer? _quickDictionaryDebounce;
  List<DictionaryEntry> _quickDictionaryResults = const [];
  bool _quickDictionaryOpen = false;
  bool _quickDictionaryLoading = false;
  bool _sessionPdfExportRunning = false;
  bool _sessionPdfExportRequested = false;
  int _quickDictionaryRequestSerial = 0;
  bool _quickDictionaryEditing = false;
  double _quickRight = 24;
  double _quickTop = 24;
  double _quickWidth = 390;
  double _quickHeight = 520;
  double _quickEditRight = 24;
  double _quickEditTop = 24;
  double _quickEditWidth = 390;
  double _quickEditHeight = 520;
  final TransformationController _canvasController = TransformationController();
  final TransformationController _canvasGestureStartController =
      TransformationController();
  final Map<int, Offset> _canvasTouches = {};
  Offset _canvasGestureStartFocal = Offset.zero;
  double _canvasGestureStartSpan = 1;
  bool _canvasGestureReady = false;
  late int _strokesPage;
  late String _strokesNotebookId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _strokesPage = widget.state.openPage;
    _strokesNotebookId = widget.notebook.id;
    final state = widget.state;
    penColor = state.penColor;
    penOpacity = state.penOpacity;
    penWidth = state.penWidth;
    penStyle = state.penStyle;
    highlightColor = state.highlightColor;
    highlightOpacity = state.highlightOpacity;
    highlightWidth = state.highlightWidth;
    strokes = List.of(
      widget.state.strokesFor(widget.notebook.id, _strokesPage),
    );
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
    WidgetsBinding.instance.removeObserver(this);
    _deleteTemporaryCropIfUnused(_latestCropPath);
    _quickDictionaryDebounce?.cancel();
    _quickDictionaryController.dispose();
    _quickDictionaryFocus.dispose();
    _canvasController.dispose();
    _canvasGestureStartController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sessionPdfExportRequested = false;
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Keep the editable .noteeryk backup and the flattened PDF in sync at
      // the end of every editor session. The stable filename is overwritten,
      // so Files contains one current PDF instead of a file per session.
      if (!_sessionPdfExportRequested) {
        _sessionPdfExportRequested = true;
        unawaited(_exportSessionPdf());
      }
    }
  }

  Future<void> _exportSessionPdf() async {
    if (_sessionPdfExportRunning || !mounted) return;
    _sessionPdfExportRunning = true;
    try {
      await _exportNotebookPdf(showMessage: false);
    } catch (error) {
      debugPrint('[NoteEryk][Export] automatic PDF export failed: $error');
    } finally {
      _sessionPdfExportRunning = false;
    }
  }

  void _beginResultEdit() {
    setState(() {
      _resultEditing = true;
      _resultEditRight = _resultRight;
      _resultEditTop = _resultTop;
      _resultEditWidth = _resultWidth;
      _resultEditHeight = _resultHeight;
    });
  }

  void _cancelResultEdit() {
    setState(() {
      _resultRight = _resultEditRight;
      _resultTop = _resultEditTop;
      _resultWidth = _resultEditWidth;
      _resultHeight = _resultEditHeight;
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
    });
  }

  void _cancelQuickDictionaryEdit() {
    setState(() {
      _quickRight = _quickEditRight;
      _quickTop = _quickEditTop;
      _quickWidth = _quickEditWidth;
      _quickHeight = _quickEditHeight;
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

  void _syncStrokesWithCurrentPage() {
    final page = widget.state.openPage;
    final notebookId = widget.notebook.id;
    if (_strokesPage == page && _strokesNotebookId == notebookId) return;
    strokes = List.of(widget.state.strokesFor(notebookId, page));
    _undoStrokeHistory.clear();
    _redoStrokeHistory.clear();
    activePoints = null;
    selectionStart = null;
    selectionEnd = null;
    _strokesPage = page;
    _strokesNotebookId = notebookId;
  }

  @override
  Widget build(BuildContext context) {
    _syncStrokesWithCurrentPage();
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
                      thumbnailPathForPage: (page) => widget.state
                          .imagesForPage(widget.notebook.id, page)
                          .firstOrNull,
                      thumbnailDataForPage:
                          widget.notebook.isPdf &&
                              widget.state.sourceDocuments[widget
                                      .notebook
                                      .id] !=
                                  null
                          ? (page) => widget.state.renderPdfPage(
                              widget.notebook.id,
                              page,
                              width: 300,
                            )
                          : null,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        _buildToolbar(),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(child: _buildWorkspace()),
                              if (!pageLocked)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: _PageEdgeNavigator(
                                    key: const ValueKey('previous-page-edge'),
                                    direction: AxisDirection.left,
                                    tooltip: 'Trang trước',
                                    onActivate: _goToPreviousPage,
                                  ),
                                ),
                              if (!pageLocked)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: _PageEdgeNavigator(
                                    key: const ValueKey('next-page-edge'),
                                    direction: AxisDirection.right,
                                    tooltip: 'Trang sau',
                                    onActivate: _goToNextPage,
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
                                        : tool == EditorTool.quickCheck
                                        ? 'AI đang xử lý...'
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
                                    editing: _resultEditing,
                                    onClose: () =>
                                        setState(() => result = null),
                                    onPin: _pinResult,
                                    onWeakness: _openWeaknessDraft,
                                    onAskMore: _askMoreAboutResult,
                                    onEdit: _beginResultEdit,
                                    onCancelEdit: _cancelResultEdit,
                                    onConfirmEdit: _confirmResultEdit,
                                    onDrag: _moveResult,
                                    onResize: _resizeResult,
                                    showOcr: widget.state.showOcrInAiResults,
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
                                    editing: _quickDictionaryEditing,
                                    onEdit: _beginQuickDictionaryEdit,
                                    onCancelEdit: _cancelQuickDictionaryEdit,
                                    onConfirmEdit: _confirmQuickDictionaryEdit,
                                    onDrag: _moveQuickDictionary,
                                    onResize: _resizeQuickDictionary,
                                  ),
                                ),
                              Positioned(
                                right: 20,
                                bottom: 70,
                                child: _RotationControl(
                                  angle: pageAngle,
                                  enabled: !pageLocked,
                                  onChanged: _setPageAngle,
                                ),
                              ),
                              Positioned(
                                right: 20,
                                bottom: 18,
                                child: _ZoomControl(
                                  zoom: zoom,
                                  enabled: !pageLocked,
                                  onChanged: _setToolbarZoom,
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
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _showJumpToPage,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 3,
                    ),
                    child: Text(
                      'Trang ${widget.state.openPage} · Đã lưu',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
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
                    _setPageAngle(pageAngle + 90);
                    showAppSnack(context, 'Đã xoay trang 90°');
                  case 'export':
                    _exportNotebookPdf();
                  case 'paper':
                    unawaited(_showNotebookPaperSettings());
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
                const PopupMenuItem(
                  value: 'paper',
                  child: Text('Cài đặt giấy của vở'),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: Text('Xuất toàn bộ vở thành PDF'),
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
          IconButton(
            tooltip: widget.state.drawWithFinger
                ? 'Một ngón viết · Hai ngón di chuyển/thu phóng'
                : 'Ngón tay di chuyển/thu phóng · Pencil để viết',
            isSelected: widget.state.drawWithFinger,
            style: IconButton.styleFrom(
              backgroundColor: widget.state.drawWithFinger
                  ? AppColors.primary.withValues(alpha: .14)
                  : null,
              foregroundColor: widget.state.drawWithFinger
                  ? AppColors.primary
                  : null,
            ),
            onPressed: () {
              setState(() {
                widget.state.drawWithFinger = !widget.state.drawWithFinger;
              });
              widget.state.saveGeneralSettings();
            },
            icon: const Icon(Icons.gesture_rounded),
          ),
          const SizedBox(width: 8),
          ...widget.state.toolbarTools.map(_toolbarButton),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Cài đặt kết quả AI',
            onPressed: _showAiOutputSettings,
            icon: const Icon(Icons.settings_suggest_outlined),
          ),
          IconButton(
            tooltip: 'Tùy chỉnh công cụ',
            onPressed: _showToolbarCustomization,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton(EditorTool value) {
    final VoidCallback callback = switch (value) {
      EditorTool.ruler => _toggleRuler,
      EditorTool.image => () => unawaited(_activateImageTool()),
      EditorTool.quickDictionary => _toggleQuickDictionary,
      _ => () => _selectTool(value),
    };
    final selected = switch (value) {
      EditorTool.ruler => rulerVisible,
      EditorTool.quickDictionary => _quickDictionaryOpen,
      _ => tool == value,
    };
    return _ToolButton(tool: value, selected: selected, onTap: callback);
  }

  Future<void> _showAiOutputSettings() async {
    var style = widget.state.translationStyle;
    var showOcr = widget.state.showOcrInAiResults;
    var highlightWeakness = widget.state.weaknessHighlightMode;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cài đặt kết quả AI'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phong cách dịch',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                SegmentedButton<TranslationStyle>(
                  segments: TranslationStyle.values
                      .map(
                        (value) => ButtonSegment(
                          value: value,
                          label: Text(value.label),
                        ),
                      )
                      .toList(),
                  selected: {style},
                  onSelectionChanged: (values) => setDialogState(() {
                    style = values.first;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  style.helper,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const Divider(height: 30),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: showOcr,
                  onChanged: (value) => setDialogState(() => showOcr = value),
                  title: const Text('Hiện nội dung OCR trong kết quả'),
                  subtitle: const Text(
                    'Tắt để chỉ xem bản dịch hoặc lời giải. Lưu ý phục dựng OCR vẫn được giữ ở cuối.',
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: highlightWeakness,
                  onChanged: (value) =>
                      setDialogState(() => highlightWeakness = value),
                  title: const Text('Điểm yếu: tự tô cụm cần học trên OCR'),
                  subtitle: const Text(
                    'Sau khi khoanh, chạm/kéo để tô từ hoặc mẫu ngữ pháp; AI chỉ tạo điểm yếu cho phần đã tô. Tắt để AI tự tìm toàn bộ.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      widget.state.translationStyle = style;
      widget.state.showOcrInAiResults = showOcr;
      widget.state.weaknessHighlightMode = highlightWeakness;
    });
    await widget.state.saveAiSettings(key: '');
  }

  Future<void> _showToolbarCustomization() async {
    final selected = widget.state.toolbarTools.toSet();
    final result = await showDialog<Set<EditorTool>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tùy chỉnh thanh công cụ'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: EditorTool.values
                    .map(
                      (value) => CheckboxListTile(
                        dense: true,
                        value: selected.contains(value),
                        title: Text(_toolLabel(value)),
                        subtitle: value == EditorTool.pen
                            ? const Text(
                                'Luôn giữ lại để tránh mất công cụ viết',
                              )
                            : null,
                        onChanged: value == EditorTool.pen
                            ? null
                            : (enabled) => setDialogState(() {
                                if (enabled == true) {
                                  selected.add(value);
                                } else {
                                  selected.remove(value);
                                }
                              }),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (result != null) widget.state.setToolbarTools(result);
  }

  String _toolLabel(EditorTool value) => switch (value) {
    EditorTool.pen => 'Bút',
    EditorTool.highlighter => 'Highlight',
    EditorTool.eraser => 'Tẩy',
    EditorTool.ruler => 'Thước',
    EditorTool.image => 'Ảnh',
    EditorTool.dictionary => 'Tra từ ngoại tuyến',
    EditorTool.quickDictionary => 'Tra từ nhanh',
    EditorTool.aiDictionary => 'AI Tra từ',
    EditorTool.translate => 'AI Dịch',
    EditorTool.explain => 'AI Giải thích',
    EditorTool.quickCheck => 'Kiểm tra nhanh',
    EditorTool.weakness => 'Điểm yếu',
  };

  void _goToPreviousPage() {
    if (widget.state.openPage > 1) {
      widget.state.goToPage(widget.state.openPage - 1);
    } else {
      showAppSnack(context, 'Đây là trang đầu tiên');
    }
  }

  void _goToNextPage() {
    if (widget.state.openPage < widget.notebook.pages) {
      widget.state.goToPage(widget.state.openPage + 1);
    } else {
      unawaited(_askCreatePage());
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

  Future<void> _showJumpToPage() async {
    final controller = TextEditingController(text: '${widget.state.openPage}');
    final page = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đi nhanh tới trang'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Nhập số từ 1 đến ${widget.notebook.pages}',
          ),
          onSubmitted: (_) =>
              Navigator.pop(dialogContext, int.tryParse(controller.text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const Text('Đi tới'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || page == null) return;
    if (page < 1 || page > widget.notebook.pages) {
      showAppSnack(context, 'Số trang phải từ 1 đến ${widget.notebook.pages}');
      return;
    }
    widget.state.goToPage(page);
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
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Xuất PDF trang hiện tại'),
              onTap: () {
                Navigator.pop(context);
                _exportCurrentPagePdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('Xuất toàn bộ vở thành PDF'),
              onTap: () {
                Navigator.pop(context);
                _exportNotebookPdf();
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

  Future<void> _exportCurrentPagePdf() async {
    try {
      final boundary =
          _pageBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw const FormatException('Không thể chụp trang');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final width = image.width.toDouble();
      final height = image.height.toDouble();
      image.dispose();
      if (bytes == null) throw const FormatException('Không thể tạo ảnh');
      final document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: pdf.PdfPageFormat(width, height),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(
            pw.MemoryImage(bytes.buffer.asUint8List()),
            fit: pw.BoxFit.fill,
          ),
        ),
      );
      final directory = await getApplicationDocumentsDirectory();
      final exportDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}exports',
      );
      await exportDirectory.create(recursive: true);
      final path =
          '${exportDirectory.path}${Platform.pathSeparator}${widget.notebook.id}_page_${widget.state.openPage}.pdf';
      await File(path).writeAsBytes(await document.save(), flush: true);
      if (mounted) showAppSnack(context, 'Đã xuất PDF trang hiện tại');
    } catch (exception) {
      if (mounted) showAppSnack(context, _friendlyError(exception));
    }
  }

  Future<void> _precachePageImagesForExport(int page) async {
    if (!mounted) return;
    final paths = widget.state
        .imagePlacementsForPage(widget.notebook.id, page)
        .map((placement) => placement.path)
        .toSet();
    await Future.wait(
      paths.map((path) async {
        final file = File(path);
        if (!await file.exists() || !mounted) return;
        try {
          await precacheImage(FileImage(file), context);
        } catch (error) {
          debugPrint('[NoteEryk][Export] image preload failed: $error');
        }
      }),
    );
  }

  Future<void> _exportNotebookPdf({bool showMessage = true}) async {
    final originalPage = widget.state.openPage;
    try {
      final outputDirectory = await getApplicationDocumentsDirectory();
      final exportDirectory = Directory(
        '${outputDirectory.path}${Platform.pathSeparator}exports',
      );
      await exportDirectory.create(recursive: true);
      final outputPath =
          '${exportDirectory.path}${Platform.pathSeparator}${widget.notebook.id}_annotated.pdf';

      // For an imported PDF, keep the PDF's text/vector content and add
      // standard PDFKit ink annotations. This is editable in PDF apps that
      // support ink annotations, unlike the screenshot fallback below.
      final sourcePath = widget.state.sourceDocuments[widget.notebook.id];
      final hasFloatingImages = [
        for (var page = 1; page <= widget.notebook.pages; page++)
          ...widget.state.imagePlacementsForPage(widget.notebook.id, page),
      ].any((placement) => !placement.isBackground);
      if (sourcePath != null &&
          sourcePath.toLowerCase().endsWith('.pdf') &&
          await File(sourcePath).exists() &&
          !hasFloatingImages) {
        final boundary =
            _pageBoundaryKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        final canvasWidth = boundary?.size.width ?? 1;
        final canvasHeight = boundary?.size.height ?? 1;
        try {
          final nativeResult = await _nativeChannel.invokeMethod<String>(
            'exportPdfWithAnnotations',
            {
              'sourcePath': sourcePath,
              'outputPath': outputPath,
              'canvasWidth': canvasWidth,
              'canvasHeight': canvasHeight,
              'pages': [
                for (var page = 1; page <= widget.notebook.pages; page++)
                  {
                    'page': page,
                    'strokes': widget.state
                        .strokesFor(widget.notebook.id, page)
                        .map((stroke) => stroke.toJson())
                        .toList(),
                  },
              ],
            },
          );
          if (nativeResult == outputPath) {
            if (showMessage && mounted) {
              showAppSnack(context, 'Đã xuất PDF có annotation chỉnh sửa được');
            }
            return;
          }
        } on MissingPluginException {
          // Fall through to the flattened screenshot export.
        } on PlatformException catch (error) {
          debugPrint(
            '[NoteEryk][Export] PDFKit export failed: ${error.message}',
          );
        }
      }

      final document = pw.Document();
      for (var page = 1; page <= widget.notebook.pages; page++) {
        if (!mounted) return;
        final sourcePdf = widget.state.sourceDocuments[widget.notebook.id];
        if (sourcePdf != null && sourcePdf.toLowerCase().endsWith('.pdf')) {
          // Ensure the on-demand PDF background is decoded before capturing a
          // page that also contains movable images.
          await widget.state.renderPdfPage(widget.notebook.id, page);
        }
        // Image.file resolves asynchronously. Without preloading, rapid
        // page-by-page capture can paint the synchronous ink strokes before
        // the imported PDF background has decoded, producing white backups.
        await _precachePageImagesForExport(page);
        widget.state.goToPage(page);
        await WidgetsBinding.instance.endOfFrame;
        await WidgetsBinding.instance.endOfFrame;
        final boundary =
            _pageBoundaryKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary == null) {
          throw FormatException('Không thể chụp trang $page');
        }
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        final width = image.width.toDouble();
        final height = image.height.toDouble();
        image.dispose();
        if (bytes == null) throw FormatException('Không thể tạo trang $page');
        document.addPage(
          pw.Page(
            pageFormat: pdf.PdfPageFormat(width, height),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(
              pw.MemoryImage(bytes.buffer.asUint8List()),
              fit: pw.BoxFit.fill,
            ),
          ),
        );
      }
      await File(outputPath).writeAsBytes(await document.save(), flush: true);
      if (showMessage && mounted) {
        showAppSnack(
          context,
          'Đã xuất ${widget.notebook.pages} trang PDF có ghi chú',
        );
      }
    } catch (exception) {
      if (mounted) showAppSnack(context, _friendlyError(exception));
    } finally {
      if (mounted && widget.state.openPage != originalPage) {
        widget.state.goToPage(originalPage);
      }
    }
  }

  Widget _buildWorkspace() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetHeight = math.min(constraints.maxHeight - 26, 770.0);
        final targetWidth = targetHeight * .72;
        // Raw touch tracking avoids Flutter's gesture arena entirely. Pencil
        // events never enter these callbacks, so writing cannot move the page.
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: pageLocked ? null : _onCanvasPointerDown,
          onPointerMove: pageLocked ? null : _onCanvasPointerMove,
          onPointerUp: pageLocked ? null : _onCanvasPointerUp,
          onPointerCancel: pageLocked ? null : _onCanvasPointerCancel,
          child: InteractiveViewer(
            transformationController: _canvasController,
            panEnabled: false,
            scaleEnabled: false,
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
                    angle: pageAngle * math.pi / 180,
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
                                          lineOpacity:
                                              widget.notebook.paperLineOpacity,
                                        ),
                                      ),
                                      if (widget.notebook.isPdf &&
                                          widget.state.sourceDocuments[widget
                                                  .notebook
                                                  .id] !=
                                              null &&
                                          !widget.state
                                              .imagePlacementsForPage(
                                                widget.notebook.id,
                                                widget.state.openPage,
                                              )
                                              .any(
                                                (placement) =>
                                                    placement.isBackground,
                                              ))
                                        Positioned.fill(
                                          child: _PdfPageBackground(
                                            state: widget.state,
                                            notebookId: widget.notebook.id,
                                            page: widget.state.openPage,
                                          ),
                                        ),
                                      if (widget.state
                                          .imagePlacementsForPage(
                                            widget.notebook.id,
                                            widget.state.openPage,
                                          )
                                          .isNotEmpty)
                                        Positioned.fill(
                                          child: _PageImageLayer(
                                            placements: widget.state
                                                .imagePlacementsForPage(
                                                  widget.notebook.id,
                                                  widget.state.openPage,
                                                ),
                                            editing: tool == EditorTool.image,
                                            selectedId: selectedImageId,
                                            onSelected: (id) => setState(
                                              () => selectedImageId = id,
                                            ),
                                            onMove: _movePageImage,
                                            onResize: _resizePageImage,
                                            onRotate: _rotatePageImage,
                                            onCrop: _cropPageImage,
                                            onDelete: _deletePageImage,
                                          ),
                                        ),
                                      IgnorePointer(
                                        child: CustomPaint(
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
                                            activePenStyle: penStyle,
                                          ),
                                        ),
                                      ),
                                      if (rulerVisible)
                                        Positioned.fill(
                                          child: LayoutBuilder(
                                            builder: (context, pageConstraints) {
                                              final pageSize =
                                                  pageConstraints.biggest;
                                              return Stack(
                                                children: [
                                                  Positioned(
                                                    left:
                                                        _rulerPosition.dx *
                                                        pageSize.width,
                                                    top:
                                                        _rulerPosition.dy *
                                                        pageSize.height,
                                                    width:
                                                        _rulerWidthFraction *
                                                        pageSize.width,
                                                    child: _Ruler(
                                                      angle: _rulerAngle,
                                                      height: _rulerHeight,
                                                      onScaleStart: (_) {
                                                        _rulerGestureStartWidth =
                                                            _rulerWidthFraction;
                                                        _rulerGestureStartHeight =
                                                            _rulerHeight;
                                                        _rulerGestureStartAngle =
                                                            _rulerAngle;
                                                      },
                                                      onScaleUpdate: (details) =>
                                                          _updateRulerGesture(
                                                            details,
                                                            pageSize,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
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
                                                            30 +
                                                            entry.key * 110,
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
          ),
        );
      },
    );
  }

  void _setToolbarZoom(double requested) {
    final next = requested.clamp(.7, 2.5).toDouble();
    if (next == 1) {
      _canvasController.value = Matrix4.identity();
    } else {
      final current = _canvasController.value.getMaxScaleOnAxis();
      final factor = next / (current == 0 ? 1 : current);
      final matrix = _canvasController.value.clone()
        ..scaleByDouble(factor, factor, 1, 1);
      _canvasController.value = matrix;
    }
    setState(() => zoom = next);
  }

  int get _minimumCanvasTouches => widget.state.drawWithFinger ? 2 : 1;

  static double _normalizeAngle(double degrees) {
    final value = degrees % 360;
    return value < 0 ? value + 360 : value;
  }

  /// Hít về 0/90/180/270° khi gần, để dễ trả trang về thẳng.
  static double _snapAngle(double degrees) {
    final value = _normalizeAngle(degrees);
    final nearest = (value / 90).round() * 90.0;
    return (value - nearest).abs() <= _rotationSnap
        ? _normalizeAngle(nearest)
        : value;
  }

  void _setPageAngle(double degrees) =>
      setState(() => pageAngle = _snapAngle(degrees));

  double _touchVectorAngle(List<Offset> positions) {
    final vector = positions[1] - positions[0];
    return math.atan2(vector.dy, vector.dx) * 180 / math.pi;
  }

  void _onCanvasPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _canvasTouches[event.pointer] = event.localPosition;
    if (_canvasTouches.length >= _minimumCanvasTouches) {
      _beginCanvasGesture();
    }
  }

  void _beginCanvasGesture() {
    final positions = _canvasTouches.values.toList(growable: false);
    if (positions.length < _minimumCanvasTouches) return;
    _canvasGestureStartController.value = _canvasController.value;
    _canvasGestureStartFocal = _centroid(positions);
    _canvasGestureStartSpan = _span(positions);
    _canvasGestureReady = true;
    _rotationStartVector = positions.length >= 2
        ? _touchVectorAngle(positions)
        : null;
    _rotationStartPageAngle = pageAngle;
    _rotationActive = false;
  }

  void _onCanvasPointerMove(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch ||
        !_canvasTouches.containsKey(event.pointer)) {
      return;
    }
    _canvasTouches[event.pointer] = event.localPosition;
    if (_canvasTouches.length < _minimumCanvasTouches) {
      _canvasGestureReady = false;
      return;
    }
    if (!_canvasGestureReady) {
      _beginCanvasGesture();
      return;
    }
    final positions = _canvasTouches.values.toList(growable: false);
    final matrix = _canvasGestureStartController.value.clone();
    final startScale = matrix.getMaxScaleOnAxis();
    final relativeScale = _span(positions) / _canvasGestureStartSpan;
    final nextScale = (startScale * relativeScale).clamp(.7, 2.5).toDouble();
    final focal = _centroid(positions);
    final focalDelta = focal - _canvasGestureStartFocal;
    matrix.translateByDouble(focalDelta.dx, focalDelta.dy, 0, 1);
    matrix.translateByDouble(
      _canvasGestureStartFocal.dx,
      _canvasGestureStartFocal.dy,
      0,
      1,
    );
    matrix.scaleByDouble(nextScale / startScale, nextScale / startScale, 1, 1);
    matrix.translateByDouble(
      -_canvasGestureStartFocal.dx,
      -_canvasGestureStartFocal.dy,
      0,
      1,
    );
    _canvasController.value = matrix;
    final rotationStart = _rotationStartVector;
    if (positions.length >= 2 && rotationStart != null) {
      final current = _touchVectorAngle(positions);
      var delta = (current - rotationStart + 540) % 360 - 180;
      if (!_rotationActive && delta.abs() >= _rotationStartThreshold) {
        // Start from the current finger angle so the page does not jump by
        // the threshold.
        _rotationActive = true;
        _rotationStartVector = current;
        _rotationStartPageAngle = pageAngle;
        delta = 0;
      }
      if (_rotationActive) {
        pageAngle = _snapAngle(_rotationStartPageAngle + delta);
      }
    }
    if (mounted) setState(() => zoom = nextScale);
  }

  void _onCanvasPointerUp(PointerUpEvent event) {
    _finishCanvasPointer(event);
  }

  void _onCanvasPointerCancel(PointerCancelEvent event) {
    _finishCanvasPointer(event);
  }

  void _finishCanvasPointer(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _canvasTouches.remove(event.pointer);
    _canvasGestureReady = false;
    if (_canvasTouches.length >= _minimumCanvasTouches) {
      _beginCanvasGesture();
    }
  }

  Offset _centroid(List<Offset> positions) {
    var sum = Offset.zero;
    for (final position in positions) {
      sum += position;
    }
    return sum / positions.length.toDouble();
  }

  double _span(List<Offset> positions) {
    if (positions.length < 2) return 1;
    final center = _centroid(positions);
    var distance = 0.0;
    for (final position in positions) {
      distance += (position - center).distance;
    }
    return math.max(distance / positions.length, .001);
  }

  bool _acceptPointer(PointerEvent event) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse) {
      return true;
    }
    return event.kind == PointerDeviceKind.touch &&
        widget.state.drawWithFinger &&
        _touchStarts.length == 1;
  }

  bool _isStylus(PointerEvent event) {
    return event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
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
    if (_isStylus(event)) {
      _canvasGestureReady = false;
    }
    if (tool == EditorTool.image) return;
    if (event.kind == PointerDeviceKind.touch) {
      _trackTouchDown(event);
      if (!widget.state.drawWithFinger || _touchStarts.length != 1) return;
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
      _eraserGestureRecorded = false;
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
    if (tool == EditorTool.image) return;
    if (event.kind == PointerDeviceKind.touch) {
      final start = _touchStarts[event.pointer];
      if (start != null && (event.localPosition - start).distance > 14) {
        _twoFingerCandidate = false;
      }
      if (!widget.state.drawWithFinger || _touchStarts.length != 1) return;
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
    if (tool == EditorTool.image) return;
    if (event.kind == PointerDeviceKind.touch) {
      if (widget.state.drawWithFinger && _touchStarts.length == 1) {
        _finishPointerInteraction();
      }
      _trackTouchUp(event);
      return;
    }
    if (!_acceptPointer(event)) return;
    _finishPointerInteraction();
  }

  void _finishPointerInteraction() {
    if (tool == EditorTool.eraser) {
      _eraserGestureRecorded = false;
      return;
    }
    if (activePoints != null && activePoints!.length > 1) {
      final drawingTool = tool;
      var points = List<StrokePoint>.of(activePoints!);
      if (rulerVisible && drawingTool == EditorTool.pen) {
        final direction = Offset(math.cos(_rulerAngle), math.sin(_rulerAngle));
        final delta = points.last.offset - points.first.offset;
        final projected = delta.dx * direction.dx + delta.dy * direction.dy;
        points = [
          points.first,
          StrokePoint(
            points.first.offset + direction * projected,
            points.last.pressure,
          ),
        ];
      }
      _recordStrokeHistory();
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
          penStyle: drawingTool == EditorTool.pen
              ? penStyle
              : PenStyle.calligraphy,
        ),
      );
      activePoints = null;
      widget.state.saveStrokes(widget.notebook.id, strokes, _strokesPage);
      setState(() {});
    } else if (selectionStart != null && selectionEnd != null) {
      _processSelection();
    }
  }

  Future<void> _processSelection() async {
    if (selectionStart == null || selectionEnd == null) return;
    final requestSerial = ++_aiRequestSerial;
    final selectionTool = tool;
    var completed = false;
    setState(() {
      processing = true;
      error = null;
      result = null;
    });
    try {
      final crop = await _captureSelection();
      if (!mounted || requestSerial != _aiRequestSerial) return;
      final previousCrop = _latestCropPath;
      var recognized = await _recognizeSelectionText(crop.path);
      if (!mounted || requestSerial != _aiRequestSerial) return;
      _latestCropPath = crop.path;
      _deleteTemporaryCropIfUnused(previousCrop, except: crop.path);
      _latestOcrText = recognized;
      if (selectionTool == EditorTool.dictionary) {
        var entry = await widget.state.dictionary.lookupNormalized(recognized);
        // A tiny crop can be difficult for on-device OCR. Only after the
        // deterministic dictionary lookup misses do we spend time on the
        // optional Vision model, then try the local dictionary once more.
        if (entry == null && _canUseAiVision) {
          recognized = await _recognizeWithAiVision(crop.path);
          entry = await widget.state.dictionary.lookupNormalized(recognized);
        }
        if (entry == null) {
          throw const FormatException(
            'Không tìm thấy từ trong từ điển ngoại tuyến',
          );
        }
        final resolvedEntry = entry;
        if (!mounted) return;
        setState(() => result = _SmartResult.dictionary(resolvedEntry));
        completed = true;
      } else if (selectionTool == EditorTool.aiDictionary) {
        final response = await widget.state.aiService.complete(
          apiKey: widget.state.apiKey,
          modelId: widget.state.modelIdFor(AiTask.dictionary),
          task: AiTask.dictionary,
          text: recognized,
          jlpt: widget.state.jlpt,
          language: widget.state.explanationLanguage,
          translationStyle: widget.state.translationStyle,
        );
        if (!mounted || requestSerial != _aiRequestSerial) return;
        setState(
          () => result = _SmartResult.ai(
            tool: selectionTool,
            source: recognized,
            body: response,
          ),
        );
        completed = true;
      } else if (selectionTool == EditorTool.quickCheck) {
        if (!mounted) return;
        await _openQuickCheck(recognized);
        completed = true;
        return;
      } else if (selectionTool == EditorTool.weakness) {
        if (!mounted) return;
        await _openWeaknessDraft(
          ocrText: recognized,
          sourceImagePath: crop.path,
          requestSerial: requestSerial,
          askHighlight: widget.state.weaknessHighlightMode,
        );
        completed = true;
        return;
      } else {
        final task = selectionTool == EditorTool.translate
            ? AiTask.translate
            : AiTask.explain;
        final response = await widget.state.aiService.complete(
          apiKey: widget.state.apiKey,
          modelId: widget.state.modelIdFor(task),
          task: task,
          text: recognized,
          jlpt: widget.state.jlpt,
          language: widget.state.explanationLanguage,
          translationStyle: widget.state.translationStyle,
        );
        if (!mounted || requestSerial != _aiRequestSerial) return;
        setState(
          () => result = _SmartResult.ai(
            tool: selectionTool,
            source: recognized,
            body: response,
          ),
        );
        completed = true;
      }
    } catch (exception) {
      if (mounted && requestSerial == _aiRequestSerial) {
        setState(() => error = _friendlyError(exception));
      }
    } finally {
      if (mounted && requestSerial == _aiRequestSerial) {
        setState(() {
          processing = false;
          if (completed && widget.state.shouldReturnToPenAfter(selectionTool)) {
            tool = EditorTool.pen;
            selectionStart = null;
            selectionEnd = null;
          }
        });
      }
    }
  }

  void _deleteTemporaryCropIfUnused(String? path, {String? except}) {
    if (path == null || path.isEmpty || path == except) return;
    final usedByWeakPoint = widget.state.weakPoints.any(
      (item) => item.sourceImagePath == path,
    );
    if (!usedByWeakPoint) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
  }

  void _cancelPendingAi() {
    _aiRequestSerial++;
    if (processing) processing = false;
  }

  Future<void> _askMoreAboutResult() async {
    final current = result;
    if (current == null || current.dictionaryEntry != null) return;
    final controller = TextEditingController();
    final question = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hỏi thêm về phần giải thích'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Ví dụ: Vì sao đáp án B sai? Cho thêm ví dụ dễ hơn.',
          ),
          onSubmitted: (_) => Navigator.pop(dialogContext, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Hỏi AI'),
          ),
        ],
      ),
    );
    controller.dispose();
    final cleanQuestion = question?.trim() ?? '';
    if (!mounted || cleanQuestion.isEmpty) return;
    final serial = ++_aiRequestSerial;
    setState(() {
      processing = true;
      error = null;
    });
    try {
      final response = await widget.state.aiService.complete(
        apiKey: widget.state.apiKey,
        modelId: widget.state.modelIdFor(AiTask.explain),
        task: AiTask.explain,
        text:
            'Nội dung đang xem:\n${current.source}\n\nGiải thích hiện tại:\n${current.body}\n\nCâu hỏi bổ sung của người học:\n$cleanQuestion',
        jlpt: widget.state.jlpt,
        language: widget.state.explanationLanguage,
        translationStyle: widget.state.translationStyle,
      );
      if (!mounted || serial != _aiRequestSerial) return;
      setState(
        () => result = _SmartResult.ai(
          tool: EditorTool.explain,
          source: current.source,
          body: response,
        ),
      );
    } catch (exception) {
      if (mounted && serial == _aiRequestSerial) {
        setState(() => error = _friendlyError(exception));
      }
    } finally {
      if (mounted && serial == _aiRequestSerial) {
        setState(() => processing = false);
      }
    }
  }

  bool get _canUseAiVision {
    final modelId = widget.state.modelIds[AiModelSlot.vision] ?? '';
    return widget.state.useAiVision &&
        modelId.trim().isNotEmpty &&
        widget.state.hasApiKey;
  }

  Future<String> _recognizeWithAiVision(String imagePath) {
    final modelId = widget.state.modelIds[AiModelSlot.vision]!.trim();
    return widget.state.aiService.recognizeImageWithAi(
      apiKey: widget.state.apiKey,
      modelId: modelId,
      imagePath: imagePath,
    );
  }

  Future<String> _recognizeSelectionText(String imagePath) async {
    // Dictionary tools should be fast and reproducible: use Apple Vision first
    // and reserve paid/network Vision OCR for an actual local-OCR failure. Other
    // AI tools retain the explicit Vision preference configured by the user.
    final dictionaryTool =
        tool == EditorTool.dictionary || tool == EditorTool.aiDictionary;
    if (dictionaryTool) {
      try {
        return await widget.state.ocr.recognizeImage(imagePath);
      } catch (localError) {
        if (_canUseAiVision) return _recognizeWithAiVision(imagePath);
        rethrow;
      }
    }
    if (_canUseAiVision) {
      try {
        return await _recognizeWithAiVision(imagePath);
      } catch (visionError) {
        // A temporary provider limit must not block the whole tool. The crop
        // is already local, so fall back to on-device OCR without another
        // network request and preserve the Vision error only if both fail.
        try {
          return await widget.state.ocr.recognizeImage(imagePath);
        } catch (_) {
          throw visionError;
        }
      }
    }
    return widget.state.ocr.recognizeImage(imagePath);
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
      _eraserGestureRecorded = false;
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
    // Keep a small safety margin around glyphs at the edge of the selection;
    // the margin is still clipped to the page and is the image sent to AI.
    region = region.inflate(
      tool == EditorTool.dictionary || tool == EditorTool.aiDictionary
          ? 18
          : 10,
    );
    region = region.intersect(Offset.zero & logicalSize);
    if (region.width < 8 || region.height < 8) {
      throw const FormatException('Vùng chọn quá nhỏ. Hãy khoanh lại.');
    }
    // Small selections otherwise become only a few dozen pixels wide. Render
    // them at a higher scale so Japanese kana strokes survive OCR; full-page
    // selections stay at the cheaper 2x scale.
    final shortestSide = math.min(region.width, region.height);
    final ratio = shortestSide < 90
        ? 4.0
        : shortestSide < 180
        ? 3.0
        : 2.0;
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
    // Upscale only very small crops. This is inexpensive compared with a
    // network request and gives Apple Vision a useful minimum glyph size.
    var encoded = bytes.buffer.asUint8List();
    if (source.width < 320 || source.height < 160) {
      final small = encoded;
      encoded = await Isolate.run(() {
        final decoded = img.decodeImage(small);
        if (decoded == null) return small;
        final enlarged = img.copyResize(
          decoded,
          width: math.max(decoded.width, 320).toInt(),
          interpolation: img.Interpolation.cubic,
        );
        return Uint8List.fromList(img.encodePng(enlarged));
      });
    }
    final path =
        '${cropDirectory.path}${Platform.pathSeparator}crop_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(path).writeAsBytes(encoded, flush: true);
    return _CapturedRegion(path);
  }

  String _friendlyError(Object exception) {
    final value = exception.toString();
    if (value.contains('401')) {
      return 'API key không hợp lệ. Hãy kiểm tra trong Cài đặt AI.';
    }
    if (value.contains('quota') || value.contains('402')) {
      return 'Tài khoản OpenRouter không đủ credit cho yêu cầu này. Nạp thêm hoặc giảm "Mức suy luận AI" trong Cài đặt.';
    }
    if (value.contains('429')) {
      return 'Dịch vụ AI đang giới hạn lượt. Hãy đợi một chút rồi thử lại.';
    }
    if (value.contains('SocketException')) {
      return 'Mất kết nối mạng. Vùng chọn của bạn vẫn được giữ.';
    }
    if (exception is TimeoutException) {
      return 'AI phản hồi quá lâu. Hãy thử lại hoặc giảm "Mức suy luận AI" trong Cài đặt.';
    }
    return value
        .replaceFirst('Exception: ', '')
        .replaceFirst('HttpException: ', '')
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
          EditorTool.quickCheck,
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

  Future<void> _activateImageTool() async {
    _cancelPendingAi();
    final alreadySelected = tool == EditorTool.image;
    setState(() {
      tool = EditorTool.image;
      error = null;
      selectionStart = null;
      selectionEnd = null;
    });
    final editableImages = widget.state
        .imagePlacementsForPage(widget.notebook.id, widget.state.openPage)
        .where((item) => !item.isBackground)
        .toList();
    if (alreadySelected || editableImages.isEmpty) {
      await _pickImagesForPage();
    } else {
      showAppSnack(context, 'Chạm ảnh để kéo, co giãn, xoay, cắt hoặc xóa');
    }
  }

  Future<void> _pickImagesForPage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (!mounted || result.isEmpty) return;
    final sources = result
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => File(path).existsSync())
        .toList();
    if (sources.isEmpty) {
      showAppSnack(context, 'Không đọc được ảnh đã chọn');
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}imports${Platform.pathSeparator}page_images',
    );
    await imageDirectory.create(recursive: true);
    final copied = <String>[];
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      final name = source.split(RegExp(r'[/\\]')).last;
      final target =
          '${imageDirectory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_${index}_$name';
      copied.add((await File(source).copy(target)).path);
    }
    if (!mounted) return;
    widget.state.attachImages(
      widget.notebook.id,
      widget.state.openPage,
      copied,
      asPageBackground: false,
    );
    final inserted = widget.state
        .imagePlacementsForPage(widget.notebook.id, widget.state.openPage)
        .where((item) => copied.contains(item.path))
        .lastOrNull;
    setState(() => selectedImageId = inserted?.id);
    showAppSnack(context, 'Đã chèn ${copied.length} ảnh vào trang');
  }

  void _movePageImage(PageImagePlacement placement, Offset delta) {
    final rect = placement.rect;
    final left = (rect.left + delta.dx).clamp(0.0, 1.0 - rect.width);
    final top = (rect.top + delta.dy).clamp(0.0, 1.0 - rect.height);
    widget.state.updateImagePlacement(
      placement.copyWith(
        rect: Rect.fromLTWH(left, top, rect.width, rect.height),
      ),
    );
  }

  void _resizePageImage(PageImagePlacement placement, Offset delta) {
    final rect = placement.rect;
    final width = (rect.width + delta.dx).clamp(.12, 1.0 - rect.left);
    final height = (rect.height + delta.dy).clamp(.12, 1.0 - rect.top);
    widget.state.updateImagePlacement(
      placement.copyWith(
        rect: Rect.fromLTWH(rect.left, rect.top, width, height),
      ),
    );
  }

  void _rotatePageImage(PageImagePlacement placement) {
    widget.state.updateImagePlacement(
      placement.copyWith(rotation: placement.rotation + math.pi / 2),
    );
  }

  Future<void> _cropPageImage(PageImagePlacement placement) async {
    final source = File(placement.path);
    if (!await source.exists()) return;
    final bytes = await source.readAsBytes();
    int imageWidth;
    int imageHeight;
    try {
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      imageWidth = frame.image.width;
      imageHeight = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (_) {
      if (mounted) showAppSnack(context, 'iPad không đọc được ảnh này');
      return;
    }
    if (!mounted) return;
    var left = 0.0;
    var top = 0.0;
    var right = 0.0;
    var bottom = 0.0;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cắt ảnh'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 260,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: imageWidth / imageHeight,
                        child: LayoutBuilder(
                          builder: (context, constraints) => Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(bytes, fit: BoxFit.fill),
                              Positioned(
                                left: left * constraints.maxWidth,
                                top: top * constraints.maxHeight,
                                right: right * constraints.maxWidth,
                                bottom: bottom * constraints.maxHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.primary,
                                      width: 3,
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
                  _ImageCropSlider(
                    label: 'Trái',
                    value: left,
                    onChanged: (value) => setDialogState(() => left = value),
                  ),
                  _ImageCropSlider(
                    label: 'Trên',
                    value: top,
                    onChanged: (value) => setDialogState(() => top = value),
                  ),
                  _ImageCropSlider(
                    label: 'Phải',
                    value: right,
                    onChanged: (value) => setDialogState(() => right = value),
                  ),
                  _ImageCropSlider(
                    label: 'Dưới',
                    value: bottom,
                    onChanged: (value) => setDialogState(() => bottom = value),
                  ),
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
              icon: const Icon(Icons.crop_rounded),
              label: const Text('Cắt ảnh'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || accepted != true) return;
    final directory = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}imports${Platform.pathSeparator}page_images',
    );
    await imageDirectory.create(recursive: true);
    final target =
        '${imageDirectory.path}${Platform.pathSeparator}crop_${DateTime.now().microsecondsSinceEpoch}.png';
    try {
      if (Platform.isIOS) {
        await _nativeChannel.invokeMethod<String>('cropImage', {
          'sourcePath': placement.path,
          'outputPath': target,
          'left': left,
          'top': top,
          'right': right,
          'bottom': bottom,
        });
      } else {
        final croppedBytes = await Isolate.run(() {
          final sourceImage = img.decodeImage(bytes)!;
          final x = (sourceImage.width * left).round();
          final y = (sourceImage.height * top).round();
          final width = (sourceImage.width * (1 - left - right)).round().clamp(
            1,
            sourceImage.width - x,
          );
          final height = (sourceImage.height * (1 - top - bottom))
              .round()
              .clamp(1, sourceImage.height - y);
          return img.encodePng(
            img.copyCrop(sourceImage, x: x, y: y, width: width, height: height),
          );
        });
        await File(target).writeAsBytes(croppedBytes);
      }
    } catch (exception) {
      if (mounted) showAppSnack(context, 'Không thể cắt ảnh: $exception');
      return;
    }
    widget.state.replacePageImage(
      widget.notebook.id,
      widget.state.openPage,
      placement,
      target,
    );
    await source.delete().catchError((_) => source);
    if (!mounted) return;
    showAppSnack(context, 'Đã cắt ảnh');
  }

  Future<void> _showNotebookPaperSettings() async {
    var style = widget.notebook.paperStyle;
    var opacity = widget.notebook.paperLineOpacity;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cài đặt giấy của vở'),
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
                          label: Text(_paperStyleName(value)),
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
      widget.notebook.copyWith(paperStyle: style, paperLineOpacity: opacity),
    );
    showAppSnack(context, 'Đã cập nhật giấy của vở');
  }

  String _paperStyleName(PaperStyle style) => switch (style) {
    PaperStyle.blank => 'Trắng',
    PaperStyle.lined => 'Kẻ ngang',
    PaperStyle.grid => 'Ô vuông',
    PaperStyle.dotted => 'Chấm',
    PaperStyle.genkou => 'Genkō',
  };

  void _deletePageImage(PageImagePlacement placement) {
    widget.state.removePageImage(
      widget.notebook.id,
      widget.state.openPage,
      placement.id,
    );
    File(placement.path).delete().catchError((_) => File(placement.path));
    setState(() => selectedImageId = null);
    showAppSnack(context, 'Đã xóa ảnh khỏi trang');
  }

  void _updateRulerGesture(ScaleUpdateDetails details, Size pageSize) {
    if (pageSize.isEmpty) return;
    setState(() {
      final width = (_rulerGestureStartWidth * details.scale).clamp(.3, .95);
      final next = Offset(
        _rulerPosition.dx + details.focalPointDelta.dx / pageSize.width,
        _rulerPosition.dy + details.focalPointDelta.dy / pageSize.height,
      );
      _rulerWidthFraction = width;
      _rulerHeight = (_rulerGestureStartHeight * details.scale).clamp(
        42.0,
        108.0,
      );
      _rulerAngle = _rulerGestureStartAngle + details.rotation;
      _rulerPosition = Offset(
        next.dx.clamp(0.0, 1.0 - width),
        next.dy.clamp(.02, .9),
      );
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
    if (rulerVisible) {
      showAppSnack(
        context,
        'Một ngón để kéo · Hai ngón để thu phóng và xoay thước',
      );
    }
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
      // The pen panel grew a style picker; let it scroll on short screens.
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedTool == EditorTool.pen
                    ? 'Bút · ${penStyle.label}'
                    : selectedTool == EditorTool.highlighter
                    ? 'Highlight'
                    : 'Tẩy',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              if (selectedTool == EditorTool.pen) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final style in PenStyle.values)
                      ChoiceChip(
                        label: Text(style.label),
                        selected: penStyle == style,
                        onSelected: (_) {
                          setState(() => penStyle = style);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  penStyle.helper,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (selectedTool != EditorTool.eraser) ...[
                ColorPanel(
                  key: ValueKey('color-panel-${selectedTool.name}'),
                  color: selectedTool == EditorTool.pen
                      ? penColor
                      : highlightColor,
                  opacity: selectedTool == EditorTool.pen
                      ? penOpacity
                      : highlightOpacity,
                  minOpacity: selectedTool == EditorTool.pen ? .1 : .2,
                  maxOpacity: selectedTool == EditorTool.pen ? 1 : .9,
                  opacityLabel: selectedTool == EditorTool.pen
                      ? 'Độ đậm'
                      : 'Độ mờ',
                  recentColors: widget.state.recentColors,
                  onChanged: (color, opacity) {
                    setState(() {
                      if (selectedTool == EditorTool.pen) {
                        penColor = color;
                        penOpacity = opacity;
                      } else {
                        highlightColor = color;
                        highlightOpacity = opacity;
                      }
                    });
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 18),
              ],
              Text(
                selectedTool == EditorTool.eraser
                    ? 'Kích thước tẩy: ${eraserWidth.round()}'
                    : 'Độ dày: ${selectedTool == EditorTool.highlighter ? highlightWidth.round() : penWidth.toStringAsFixed(1)}',
              ),
              Slider(
                value: selectedTool == EditorTool.eraser
                    ? eraserWidth
                    : selectedTool == EditorTool.highlighter
                    ? highlightWidth
                    : penWidth,
                min: selectedTool == EditorTool.eraser
                    ? 12
                    : selectedTool == EditorTool.highlighter
                    ? 10
                    : 1,
                max: selectedTool == EditorTool.eraser
                    ? 60
                    : selectedTool == EditorTool.highlighter
                    ? 40
                    : 12,
                onChanged: (value) {
                  setSheetState(() {});
                  setState(() {
                    if (selectedTool == EditorTool.eraser) {
                      eraserWidth = value;
                    } else if (selectedTool == EditorTool.highlighter) {
                      highlightWidth = value;
                    } else {
                      penWidth = value;
                    }
                  });
                },
              ),
              if (selectedTool == EditorTool.pen) ...[
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
                      style: penStyle,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Nét theo lực bút'),
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
                  'Đầu dẹt vát 45° · chồng nét sẽ đậm hơn',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
              if (selectedTool == EditorTool.eraser)
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'part', label: Text('Tẩy một phần')),
                    ButtonSegment(value: 'stroke', label: Text('Tẩy cả nét')),
                  ],
                  selected: {eraserMode},
                  onSelectionChanged: (selection) {
                    final mode = selection.first;
                    setState(() => eraserMode = mode);
                    setSheetState(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (selectedTool != EditorTool.eraser) _savePenDefaults(selectedTool);
  }

  /// Màu, độ đậm, độ dày và kiểu bút vừa chỉnh trở thành mặc định cho các
  /// lần mở vở sau; màu tự chọn được thêm vào "Màu đã dùng gần đây".
  void _savePenDefaults(EditorTool selectedTool) {
    final state = widget.state
      ..penColor = penColor
      ..penOpacity = penOpacity
      ..penWidth = penWidth
      ..penStyle = penStyle
      ..highlightColor = highlightColor
      ..highlightOpacity = highlightOpacity
      ..highlightWidth = highlightWidth;
    state.rememberColor(
      selectedTool == EditorTool.pen ? penColor : highlightColor,
      presets: colorPanelPresets,
    );
    unawaited(state.savePenSettings());
  }

  void _eraseNear(Offset point) {
    if (eraserMode == 'stroke') {
      final index = strokes.lastIndexWhere(
        (stroke) => _strokeTouchesEraser(stroke, point),
      );
      if (index < 0) return;
      _recordEraserHistoryOnce();
      strokes.removeAt(index);
    } else {
      var changed = false;
      final next = <InkStroke>[];
      for (final stroke in strokes) {
        final parts = _erasePartOfStroke(stroke, point);
        if (parts == null) {
          next.add(stroke);
        } else {
          changed = true;
          next.addAll(parts);
        }
      }
      if (!changed) return;
      _recordEraserHistoryOnce();
      strokes = next;
    }
    widget.state.saveStrokes(widget.notebook.id, strokes, _strokesPage);
    setState(() {});
  }

  bool _strokeTouchesEraser(InkStroke stroke, Offset center) {
    final radius = eraserWidth / 2 + stroke.width / 2;
    if (stroke.points.any(
      (sample) => (sample.offset - center).distance <= radius,
    )) {
      return true;
    }
    for (var index = 1; index < stroke.points.length; index++) {
      if (_distanceToSegment(
            center,
            stroke.points[index - 1].offset,
            stroke.points[index].offset,
          ) <=
          radius) {
        return true;
      }
    }
    return false;
  }

  List<InkStroke>? _erasePartOfStroke(InkStroke stroke, Offset center) {
    if (!_strokeTouchesEraser(stroke, center)) return null;
    final radius = eraserWidth / 2 + stroke.width / 2;
    final spacing = (radius / 3).clamp(2.0, 8.0);
    final samples = <StrokePoint>[];
    for (var index = 0; index < stroke.points.length; index++) {
      final current = stroke.points[index];
      if (index == 0) samples.add(current);
      if (index + 1 >= stroke.points.length) continue;
      final next = stroke.points[index + 1];
      final distance = (next.offset - current.offset).distance;
      final steps = math.max(1, (distance / spacing).ceil());
      for (var step = 1; step <= steps; step++) {
        final fraction = step / steps;
        samples.add(
          StrokePoint(
            Offset.lerp(current.offset, next.offset, fraction)!,
            current.pressure + (next.pressure - current.pressure) * fraction,
            (current.timeMicros +
                    (next.timeMicros - current.timeMicros) * fraction)
                .round(),
          ),
        );
      }
    }

    final groups = <List<StrokePoint>>[];
    var currentGroup = <StrokePoint>[];
    for (final sample in samples) {
      if ((sample.offset - center).distance <= radius) {
        if (currentGroup.length >= 2) groups.add(currentGroup);
        currentGroup = <StrokePoint>[];
      } else {
        currentGroup.add(sample);
      }
    }
    if (currentGroup.length >= 2) groups.add(currentGroup);
    return groups
        .map(
          (points) => InkStroke(
            points: points,
            color: stroke.color,
            width: stroke.width,
            tool: stroke.tool,
            createdAt: stroke.createdAt,
            penStyle: stroke.penStyle,
          ),
        )
        .toList(growable: false);
  }

  double _distanceToSegment(Offset point, Offset start, Offset end) {
    final delta = end - start;
    final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
    if (lengthSquared == 0) return (point - start).distance;
    final projection =
        ((point.dx - start.dx) * delta.dx + (point.dy - start.dy) * delta.dy) /
        lengthSquared;
    final nearest = start + delta * projection.clamp(0.0, 1.0);
    return (point - nearest).distance;
  }

  void _recordEraserHistoryOnce() {
    if (_eraserGestureRecorded) return;
    _recordStrokeHistory();
    _eraserGestureRecorded = true;
  }

  void _recordStrokeHistory() {
    _undoStrokeHistory.add(List<InkStroke>.of(strokes));
    if (_undoStrokeHistory.length > 50) _undoStrokeHistory.removeAt(0);
    _redoStrokeHistory.clear();
  }

  void _undo() {
    if (_undoStrokeHistory.isEmpty) return;
    _redoStrokeHistory.add(List<InkStroke>.of(strokes));
    strokes = _undoStrokeHistory.removeLast();
    widget.state.saveStrokes(widget.notebook.id, strokes, _strokesPage);
    setState(() {});
  }

  void _redo() {
    if (_redoStrokeHistory.isEmpty) return;
    _undoStrokeHistory.add(List<InkStroke>.of(strokes));
    strokes = _redoStrokeHistory.removeLast();
    widget.state.saveStrokes(widget.notebook.id, strokes, _strokesPage);
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

  /// Kiểm tra nhanh: mở bảng chấm ngay sau OCR, AI giải đề ở nền.
  Future<void> _openQuickCheck(String ocrText) async {
    final state = widget.state;
    final future = state.aiService.completeQuickCheck(
      apiKey: state.apiKey,
      modelId: state.modelIdFor(AiTask.solve),
      text: ocrText,
      jlpt: state.jlpt,
      language: state.explanationLanguage,
    );
    if (mounted && processing) setState(() => processing = false);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickCheckSheet(
        result: future,
        title: 'Kiểm tra nhanh đáp án',
        sourceText: ocrText,
        initialQuestionCount: estimateQuestionCount(ocrText),
        onRetry: () => unawaited(_openQuickCheck(ocrText)),
        onWrongAnswers: (wrong) => unawaited(
          _openWeaknessDraft(
            ocrText: wrong.map((answer) => answer.questionText).join('\n\n'),
            sourceImagePath: _latestCropPath,
            learnerContext: wrong
                .map((answer) => answer.learnerContext)
                .join('\n'),
          ),
        ),
        onExplain: (answer) => unawaited(_explainQuickCheckAnswer(answer)),
      ),
    );
  }

  Future<void> _explainQuickCheckAnswer(QuickCheckAnswer answer) async {
    final serial = ++_aiRequestSerial;
    setState(() {
      processing = true;
      error = null;
    });
    try {
      final picked = answer.pickedText;
      final response = await widget.state.aiService.complete(
        apiKey: widget.state.apiKey,
        modelId: widget.state.modelIdFor(AiTask.explain),
        task: AiTask.explain,
        text: [
          answer.questionText,
          if (picked.isNotEmpty)
            'Thông tin làm bài (không phải nội dung đề): người học chọn "$picked".',
        ].join('\n\n'),
        jlpt: widget.state.jlpt,
        language: widget.state.explanationLanguage,
        translationStyle: widget.state.translationStyle,
      );
      if (!mounted || serial != _aiRequestSerial) return;
      setState(
        () => result = _SmartResult.ai(
          tool: EditorTool.explain,
          source: answer.questionText,
          body: response,
        ),
      );
    } catch (exception) {
      if (mounted && serial == _aiRequestSerial) {
        setState(() => error = _friendlyError(exception));
      }
    } finally {
      if (mounted && serial == _aiRequestSerial) {
        setState(() => processing = false);
      }
    }
  }

  /// Cách đọc/Hán Việt do AI viết được đối chiếu với từ điển ngoại tuyến:
  /// Hán Việt lấy theo từ điển, cách đọc khác thì ghi chú để người học xem.
  Future<List<WeakPointDraft>> _verifyWithDictionary(
    List<WeakPointDraft> drafts,
  ) async {
    final verified = <WeakPointDraft>[];
    for (final draft in drafts) {
      if (draft.kind != WeaknessKind.vocabulary &&
          draft.kind != WeaknessKind.kanji) {
        verified.add(draft);
        continue;
      }
      DictionaryEntry? entry;
      try {
        entry = await widget.state.dictionary.lookupBasic(draft.title);
      } catch (_) {}
      if (entry == null) {
        verified.add(draft);
        continue;
      }
      final notes = <String>[if (draft.warning.isNotEmpty) draft.warning];
      var reading = draft.reading;
      if (reading.isEmpty) {
        reading = entry.reading;
      } else if (!readingsMatch(reading, entry.reading)) {
        notes.add('Từ điển ghi cách đọc: ${entry.reading}');
      }
      var hanViet = draft.hanViet;
      if (entry.hanViet.isNotEmpty) {
        if (hanViet.isNotEmpty &&
            hanViet.toUpperCase() != entry.hanViet.toUpperCase()) {
          notes.add('Hán Việt đã sửa theo từ điển (AI ghi: $hanViet)');
        }
        hanViet = entry.hanViet;
      }
      verified.add(
        draft.copyWith(
          reading: reading,
          hanViet: hanViet,
          warning: notes.join('\n'),
        ),
      );
    }
    return verified;
  }

  Future<String?> _askWeaknessFallback(String message) => showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.error_outline, color: AppColors.weakness),
      title: const Text('Chưa tạo được điểm yếu'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Hủy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'manual'),
          child: const Text('Nhập thủ công'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'retry'),
          child: const Text('Thử lại'),
        ),
      ],
    ),
  );

  Future<void> _openWeaknessDraft({
    String? ocrText,
    String? sourceImagePath,
    int? requestSerial,
    String learnerContext = '',
    bool askHighlight = false,
  }) async {
    final activeSerial = requestSerial ?? ++_aiRequestSerial;
    final state = widget.state;
    var resolvedOcr = ocrText ?? _latestOcrText ?? result?.source ?? '';
    final resolvedImage = sourceImagePath ?? _latestCropPath;
    void discardCrop() {
      _deleteTemporaryCropIfUnused(resolvedImage);
      if (_latestCropPath == resolvedImage &&
          !state.weakPoints.any(
            (item) => item.sourceImagePath == resolvedImage,
          )) {
        _latestCropPath = null;
        _latestOcrText = null;
      }
    }

    // Người học tự tô cụm cần học trên OCR; AI chỉ điền nội dung cho các cụm
    // đó nên nhanh và ít token hơn để AI tự dò cả vùng.
    var focusTerms = const <String>[];
    if (askHighlight && resolvedOcr.trim().isNotEmpty) {
      await _finishProcessingAfterOverlay();
      if (!mounted) return;
      final picked = await showOcrHighlightSheet(
        context,
        ocrText: resolvedOcr,
        previewImagePath: resolvedImage,
      );
      if (!mounted || activeSerial != _aiRequestSerial) return;
      if (picked == null) {
        discardCrop();
        return;
      }
      resolvedOcr = picked.text;
      focusTerms = picked.terms;
    }

    var drafts = <WeakPointDraft>[];
    var batchWarning = '';
    var manual = false;
    final model = state.modelIdFor(AiTask.createWeakPoint);
    if (state.hasApiKey && model.isNotEmpty && resolvedOcr.trim().isNotEmpty) {
      while (true) {
        if (mounted && !processing) setState(() => processing = true);
        Object? failure;
        try {
          final batch = await state.aiService.completeWeakPointDrafts(
            apiKey: state.apiKey,
            modelId: model,
            text: resolvedOcr,
            jlpt: state.jlpt,
            language: state.explanationLanguage,
            learnerContext: learnerContext,
            focusTerms: focusTerms,
          );
          drafts = await _verifyWithDictionary(batch.items);
          batchWarning = batch.warning;
        } catch (exception) {
          failure = exception;
        }
        if (!mounted || activeSerial != _aiRequestSerial) return;
        await _finishProcessingAfterOverlay();
        if (!mounted) return;
        if (failure == null && drafts.isNotEmpty) break;
        // Không bao giờ âm thầm lưu OCR thô làm điểm yếu: hỏi người học.
        final choice = await _askWeaknessFallback(
          failure == null
              ? 'AI không tìm thấy điểm cần học trong vùng này.'
              : _friendlyError(failure),
        );
        if (!mounted) return;
        if (choice == 'retry') continue;
        if (choice == 'manual') {
          manual = true;
          break;
        }
        discardCrop();
        return;
      }
    } else {
      manual = true;
      await _finishProcessingAfterOverlay();
      if (!mounted) return;
    }
    if (manual) {
      drafts = focusTerms.isEmpty
          ? [
              WeakPointDraft(
                title: '',
                kind: WeaknessKind.grammar,
                content: '',
                sourceSentence: resolvedOcr.trim(),
              ),
            ]
          : [
              for (final term in focusTerms)
                WeakPointDraft(
                  title: term,
                  kind: WeaknessKind.vocabulary,
                  content: '',
                  sourceSentence: _sentenceContaining(resolvedOcr, term),
                ),
            ];
    }
    final forms = drafts.asMap().entries.map((entry) {
      final form = _WeaknessDraftForm.fromDraft(entry.value, entry.key);
      form.tags = {
        state.jlpt,
        if (entry.value.questionType != JlptQuestionType.other)
          entry.value.questionType.tag,
        ...entry.value.tags,
      }.toList();
      return form;
    }).toList();
    final pageController = PageController();
    final tagController = TextEditingController();
    var activeIndex = 0;
    var saveError = '';
    var added = 0;
    var merged = 0;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (forms.isEmpty) return const SizedBox.shrink();
          final current = forms[activeIndex.clamp(0, forms.length - 1)];
          void removeCurrent() {
            setSheetState(() {
              forms.removeAt(activeIndex);
              if (forms.isNotEmpty) {
                activeIndex = activeIndex.clamp(0, forms.length - 1);
              }
            });
            if (forms.isEmpty) Navigator.pop(context, false);
          }

          void addTag() {
            final tag = tagController.text.trim();
            if (tag.isEmpty || current.tags.contains(tag)) return;
            setSheetState(() {
              current.tags.add(tag);
              tagController.clear();
            });
          }

          void save() {
            final missing = forms.indexWhere(
              (form) => form.title.trim().isEmpty,
            );
            if (missing >= 0) {
              setSheetState(() {
                saveError = 'Mục ${missing + 1} chưa có tên (mẫu/từ/kanji).';
                activeIndex = missing;
              });
              pageController.jumpToPage(missing);
              return;
            }
            for (final form in forms) {
              final duplicate = state.findDuplicateWeakPoint(
                form.kind,
                form.title,
              );
              if (duplicate != null) {
                state.reencounterWeakPoint(
                  duplicate,
                  sourceSentence: form.sourceSentence,
                );
                merged++;
                continue;
              }
              state.addWeakPoint(
                WeakPoint(
                  id: '${DateTime.now().microsecondsSinceEpoch}_${form.id}',
                  title: form.title.trim(),
                  kind: form.kind,
                  content: form.content.trim(),
                  reminder: form.reminder.trim(),
                  note: form.note.trim(),
                  tags: form.tags,
                  notebookId: widget.notebook.id,
                  notebookTitle: widget.notebook.title,
                  page: state.openPage,
                  ocrText: resolvedOcr,
                  sourceImagePath: resolvedImage,
                  reading: form.reading.trim(),
                  hanViet: form.hanViet.trim(),
                  conjugation: form.conjugation.trim(),
                  examples: form.examples,
                  sourceSentence: form.sourceSentence.trim(),
                  correctAnswer: form.correctAnswer.trim(),
                  mistake: form.mistake.trim(),
                  warning: form.warning.trim(),
                  createdAt: DateTime.now(),
                  // AI drafts already follow the current title rules, so
                  // "Chuẩn hóa toàn bộ" can skip them.
                  formatVersion: manual ? 0 : weakPointFormatVersion,
                ),
              );
              added++;
            }
            Navigator.pop(context, true);
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              MediaQuery.viewInsetsOf(context).bottom + 18,
            ),
            child: SizedBox(
              width: 720,
              height: math.min(MediaQuery.sizeOf(context).height * .86, 780),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              manual
                                  ? 'Nhập điểm yếu thủ công'
                                  : 'Duyệt điểm yếu (${forms.length})',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              manual
                                  ? 'Điền tên và nội dung cần nhớ.'
                                  : 'AI đã tách từng điểm riêng. Sửa hoặc bỏ mục không cần rồi lưu.',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.auto_awesome, color: AppColors.weakness),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (resolvedImage != null && File(resolvedImage).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(resolvedImage),
                        height: 80,
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                  if (batchWarning.isNotEmpty)
                    _DraftNotice(
                      icon: Icons.info_outline,
                      message: batchWarning,
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Nội dung đã nhận dạng'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(resolvedOcr),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: forms.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, index) {
                        final form = forms[index];
                        final question = form.questionLabel.isEmpty
                            ? ''
                            : 'Câu ${form.questionLabel} · ';
                        return ChoiceChip(
                          label: Text(
                            '${index + 1}. $question${form.kind.label}',
                          ),
                          selected: index == activeIndex,
                          onSelected: (_) {
                            setSheetState(() => activeIndex = index);
                            pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: pageController,
                      itemCount: forms.length,
                      onPageChanged: (index) =>
                          setSheetState(() => activeIndex = index),
                      itemBuilder: (_, index) => SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 4, bottom: 12),
                        child: _buildWeaknessDraftEditor(
                          forms[index],
                          setSheetState,
                          tagController,
                          addTag,
                          removeCurrent,
                        ),
                      ),
                    ),
                  ),
                  if (saveError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        saveError,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Text(
                        '${activeIndex + 1}/${forms.length}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: save,
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: Text(forms.length == 1 ? 'Lưu' : 'Lưu tất cả'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    pageController.dispose();
    tagController.dispose();
    if (saved != true) {
      discardCrop();
      return;
    }
    if (added == 0) _deleteTemporaryCropIfUnused(resolvedImage);
    if (!mounted) return;
    setState(() {
      result = null;
      selectionStart = null;
      selectionEnd = null;
    });
    final parts = [
      if (added > 0) 'Đã lưu $added điểm yếu',
      if (merged > 0) '$merged mục đã có được đưa lên ôn lại',
    ];
    showAppSnack(
      context,
      parts.join(' · '),
      actionLabel: 'Xem',
      onAction: () => state.goTo(AppDestination.weaknesses),
    );
  }

  /// Dòng OCR chứa [term], dùng làm câu gốc cho bản nháp nhập thủ công.
  String _sentenceContaining(String text, String term) => text
      .split(RegExp(r'(?<=[。！？!?])|\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.contains(term), orElse: () => '');

  Widget _buildWeaknessDraftEditor(
    _WeaknessDraftForm form,
    StateSetter setSheetState,
    TextEditingController tagController,
    VoidCallback addTag,
    VoidCallback removeCurrent,
  ) {
    Widget field(
      String label,
      String value,
      void Function(String) onChanged, {
      int minLines = 1,
      int maxLines = 4,
      String? helper,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: ValueKey('${form.id}-$label'),
        initialValue: value,
        minLines: minLines,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label, helperText: helper),
      ),
    );
    final lexical = {
      WeaknessKind.vocabulary,
      WeaknessKind.kanji,
    }.contains(form.kind);
    final duplicate = widget.state.findDuplicateWeakPoint(
      form.kind,
      form.title,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<WeaknessKind>(
                key: ValueKey('${form.id}-kind'),
                initialValue: form.kind,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Loại'),
                items: WeaknessKind.values
                    .map(
                      (kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(kind.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setSheetState(() => form.kind = value ?? form.kind),
              ),
            ),
            const SizedBox(width: 8),
            if (form.questionType != JlptQuestionType.other)
              Flexible(
                child: Chip(
                  label: Text(
                    form.questionType.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: removeCurrent,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Bỏ mục này'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (duplicate != null)
          const _DraftNotice(
            icon: Icons.repeat_rounded,
            message:
                'Đã có trong sổ điểm yếu. Lưu sẽ không tạo bản trùng mà đưa mục cũ lên ôn lại ngay.',
          ),
        if (form.warning.isNotEmpty)
          _DraftNotice(
            icon: Icons.help_outline,
            message: 'Cần kiểm tra: ${form.warning}',
          ),
        field(
          form.kind == WeaknessKind.grammar
              ? 'Mẫu ngữ pháp'
              : form.kind == WeaknessKind.kanji
              ? 'Chữ Kanji'
              : form.kind == WeaknessKind.vocabulary
              ? 'Từ khóa'
              : 'Tên điểm cần nhớ',
          form.title,
          (v) => form.title = v,
        ),
        field(
          form.kind == WeaknessKind.grammar
              ? 'Nghĩa / cách dùng'
              : 'Nghĩa trong ngữ cảnh',
          form.content,
          (v) => form.content = v,
          minLines: 2,
        ),
        if (lexical) field('Cách đọc', form.reading, (v) => form.reading = v),
        if (lexical) field('Hán Việt', form.hanViet, (v) => form.hanViet = v),
        if (form.kind == WeaknessKind.grammar)
          field(
            'Cách nối (接続)',
            form.conjugation,
            (v) => form.conjugation = v,
            minLines: 2,
          ),
        field(
          'Ví dụ (mỗi dòng một ví dụ)',
          form.examples.join('\n'),
          (v) => form.examples = v
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList(),
          minLines: 2,
        ),
        field(
          form.kind == WeaknessKind.reading
              ? 'Câu căn cứ trong bài'
              : 'Câu gốc',
          form.sourceSentence,
          (v) => form.sourceSentence = v,
          minLines: 2,
        ),
        field('Đáp án đúng', form.correctAnswer, (v) => form.correctAnswer = v),
        field(
          'Chỗ dễ nhầm',
          form.mistake,
          (v) => form.mistake = v,
          minLines: 2,
        ),
        field('Mẹo nhớ', form.reminder, (v) => form.reminder = v, minLines: 1),
        field('Ghi chú của tôi', form.note, (v) => form.note = v, minLines: 2),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ...form.tags.map(
              (tag) => InputChip(
                label: Text(tag),
                onDeleted: () => setSheetState(() => form.tags.remove(tag)),
              ),
            ),
            SizedBox(
              width: 190,
              child: TextField(
                controller: tagController,
                onSubmitted: (_) => addTag(),
                decoration: const InputDecoration(
                  hintText: 'Thêm thẻ',
                  isDense: true,
                ),
              ),
            ),
            ActionChip(label: const Text('+ Thêm'), onPressed: addTag),
          ],
        ),
      ],
    );
  }
}

class _DraftNotice extends StatelessWidget {
  const _DraftNotice({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10, top: 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.weakness.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.weakness),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

class _WeaknessDraftForm {
  _WeaknessDraftForm({
    required this.id,
    required this.kind,
    required this.title,
    required this.content,
    required this.reminder,
    required this.note,
    required this.tags,
    required this.reading,
    required this.hanViet,
    required this.conjugation,
    required this.examples,
    required this.sourceSentence,
    required this.correctAnswer,
    required this.mistake,
    required this.warning,
    required this.questionLabel,
    required this.questionType,
  });

  factory _WeaknessDraftForm.fromDraft(WeakPointDraft draft, int index) =>
      _WeaknessDraftForm(
        id: '${DateTime.now().microsecondsSinceEpoch}_$index',
        kind: draft.kind,
        title: draft.title,
        content: draft.content,
        reminder: draft.reminder,
        note: draft.note,
        tags: List.of(draft.tags),
        reading: draft.reading,
        hanViet: draft.hanViet,
        conjugation: draft.conjugation,
        examples: List.of(draft.examples),
        sourceSentence: draft.sourceSentence,
        correctAnswer: draft.correctAnswer,
        mistake: draft.mistake,
        warning: draft.warning,
        questionLabel: draft.questionLabel,
        questionType: draft.questionType,
      );

  final String id;
  WeaknessKind kind;
  String title;
  String content;
  String reminder;
  String note;
  List<String> tags;
  String reading;
  String hanViet;
  String conjugation;
  List<String> examples;
  String sourceSentence;
  String correctAnswer;
  String mistake;
  final String warning;
  final String questionLabel;
  final JlptQuestionType questionType;
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
      EditorTool.image => (Icons.add_photo_alternate_outlined, 'Ảnh'),
      EditorTool.dictionary => (Icons.menu_book_outlined, 'Tra từ'),
      EditorTool.quickDictionary => (Icons.search_rounded, 'Tra từ nhanh'),
      EditorTool.aiDictionary => (Icons.auto_stories_outlined, 'AI Tra từ'),
      EditorTool.translate => (Icons.translate_rounded, 'AI Dịch'),
      EditorTool.explain => (Icons.auto_awesome_outlined, 'AI Giải thích'),
      EditorTool.quickCheck => (Icons.fact_check_outlined, 'Kiểm tra nhanh'),
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
              width: tool == EditorTool.explain || tool == EditorTool.quickCheck
                  ? 92
                  : tool == EditorTool.quickDictionary
                  ? 88
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
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected ? color : null,
                      ),
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

Color _toolColor(EditorTool tool) => switch (tool) {
  EditorTool.image => AppColors.primary,
  EditorTool.dictionary => AppColors.dictionary,
  EditorTool.quickDictionary => AppColors.dictionary,
  EditorTool.aiDictionary => AppColors.translate,
  EditorTool.translate => AppColors.translate,
  EditorTool.explain => AppColors.explain,
  EditorTool.weakness => AppColors.weakness,
  EditorTool.quickCheck => AppColors.quickCheck,
  _ => AppColors.primary,
};

class _PageRail extends StatefulWidget {
  const _PageRail({
    required this.currentPage,
    required this.pageCount,
    required this.onPageSelected,
    required this.onAddPage,
    required this.onClose,
    required this.thumbnailPathForPage,
    this.thumbnailDataForPage,
  });
  final int currentPage;
  final int pageCount;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onAddPage;
  final VoidCallback onClose;
  final String? Function(int page) thumbnailPathForPage;
  final Future<Uint8List?> Function(int page)? thumbnailDataForPage;

  @override
  State<_PageRail> createState() => _PageRailState();
}

class _PageRailState extends State<_PageRail> {
  static const _pageItemExtent = 150.0;
  final ScrollController _scrollController = ScrollController();

  int get currentPage => widget.currentPage;
  int get pageCount => widget.pageCount;
  ValueChanged<int> get onPageSelected => widget.onPageSelected;
  VoidCallback get onAddPage => widget.onAddPage;
  VoidCallback get onClose => widget.onClose;
  String? Function(int page) get thumbnailPathForPage =>
      widget.thumbnailPathForPage;
  Future<Uint8List?> Function(int page)? get thumbnailDataForPage =>
      widget.thumbnailDataForPage;
  final Map<int, Future<Uint8List?>> _thumbnailFutures = {};

  Future<Uint8List?>? _thumbnailData(int page) {
    final loader = thumbnailDataForPage;
    if (loader == null) return null;
    return _thumbnailFutures.putIfAbsent(page, () => loader(page));
  }

  @override
  void initState() {
    super.initState();
    _scheduleRevealCurrentPage();
  }

  @override
  void didUpdateWidget(covariant _PageRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage ||
        oldWidget.pageCount != widget.pageCount) {
      _scheduleRevealCurrentPage();
    }
  }

  void _scheduleRevealCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target =
          ((currentPage - 1) * _pageItemExtent -
                  position.viewportDimension * .35)
              .clamp(0.0, position.maxScrollExtent)
              .toDouble();
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
                onPressed: _scheduleRevealCurrentPage,
                visualDensity: VisualDensity.compact,
                tooltip: 'Tìm trang hiện tại',
                icon: const Icon(Icons.my_location_rounded, size: 19),
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
            controller: _scrollController,
            itemExtent: _pageItemExtent,
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
                              width: double.infinity,
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
                              child: _buildThumbnail(page),
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

  Widget _buildThumbnail(int page) {
    final path = thumbnailPathForPage(page);
    if (path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image_outlined, size: 18),
        ),
      );
    }
    final future = _thumbnailData(page);
    if (future == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: FutureBuilder<Uint8List?>(
        future: future,
        builder: (_, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) return const SizedBox.shrink();
          return Image.memory(bytes, fit: BoxFit.contain);
        },
      ),
    );
  }
}

class _PageEdgeNavigator extends StatelessWidget {
  const _PageEdgeNavigator({
    super.key,
    required this.direction,
    required this.tooltip,
    required this.onActivate,
  });

  final AxisDirection direction;
  final String tooltip;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$tooltip · chạm hoặc vuốt ở mép ngoài',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      supportedDevices: const {PointerDeviceKind.touch},
      onTap: onActivate,
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() >= 180) onActivate();
      },
      child: SizedBox(
        width: 42,
        child: Center(
          child: Container(
            width: 24,
            height: 52,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Icon(
              direction == AxisDirection.left
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              size: 20,
            ),
          ),
        ),
      ),
    ),
  );
}

class _PdfPageBackground extends StatefulWidget {
  const _PdfPageBackground({
    required this.state,
    required this.notebookId,
    required this.page,
  });
  final AppState state;
  final String notebookId;
  final int page;

  @override
  State<_PdfPageBackground> createState() => _PdfPageBackgroundState();
}

class _PdfPageBackgroundState extends State<_PdfPageBackground> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _PdfPageBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.notebookId != widget.notebookId ||
        oldWidget.page != widget.page) {
      _future = _load();
    }
  }

  Future<Uint8List?> _load() =>
      widget.state.renderPdfPage(widget.notebookId, widget.page);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _future,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
        );
      }
      if (snapshot.hasError) {
        return const Center(child: Icon(Icons.broken_image_outlined));
      }
      return const ColoredBox(color: Colors.white);
    },
  );
}

class _PageImageLayer extends StatelessWidget {
  const _PageImageLayer({
    required this.placements,
    required this.editing,
    required this.selectedId,
    required this.onSelected,
    required this.onMove,
    required this.onResize,
    required this.onRotate,
    required this.onCrop,
    required this.onDelete,
  });
  final List<PageImagePlacement> placements;
  final bool editing;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final void Function(PageImagePlacement, Offset) onMove;
  final void Function(PageImagePlacement, Offset) onResize;
  final ValueChanged<PageImagePlacement> onRotate;
  final ValueChanged<PageImagePlacement> onCrop;
  final ValueChanged<PageImagePlacement> onDelete;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      clipBehavior: Clip.none,
      children: placements.map((placement) {
        final rect = Rect.fromLTWH(
          placement.rect.left * constraints.maxWidth,
          placement.rect.top * constraints.maxHeight,
          placement.rect.width * constraints.maxWidth,
          placement.rect.height * constraints.maxHeight,
        );
        final selected = editing && selectedId == placement.id;
        final canEdit = editing && !placement.isBackground;
        return Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            ignoring: !canEdit,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    supportedDevices: const {PointerDeviceKind.touch},
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelected(placement.id),
                    onPanUpdate: (details) => onMove(
                      placement,
                      Offset(
                        details.delta.dx / constraints.maxWidth,
                        details.delta.dy / constraints.maxHeight,
                      ),
                    ),
                    child: Transform.rotate(
                      angle: placement.rotation,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: placement.isBackground
                              ? Colors.white
                              : Colors.transparent,
                          border: selected
                              ? Border.all(color: AppColors.primary, width: 2)
                              : null,
                        ),
                        child: Image.file(
                          File(placement.path),
                          fit: placement.isBackground
                              ? BoxFit.fill
                              : BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (selected) ...[
                  Positioned(
                    right: -14,
                    top: -14,
                    child: _ImageControl(
                      icon: Icons.close,
                      color: Colors.red,
                      onTap: () => onDelete(placement),
                    ),
                  ),
                  Positioned(
                    left: -14,
                    top: -14,
                    child: _ImageControl(
                      icon: Icons.rotate_90_degrees_ccw,
                      onTap: () => onRotate(placement),
                    ),
                  ),
                  Positioned(
                    left: -14,
                    bottom: -14,
                    child: _ImageControl(
                      icon: Icons.crop_rounded,
                      onTap: () => onCrop(placement),
                    ),
                  ),
                  Positioned(
                    right: -14,
                    bottom: -14,
                    child: GestureDetector(
                      supportedDevices: const {PointerDeviceKind.touch},
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) => onResize(
                        placement,
                        Offset(
                          details.delta.dx / constraints.maxWidth,
                          details.delta.dy / constraints.maxHeight,
                        ),
                      ),
                      child: const _ImageControl(
                        icon: Icons.open_in_full_rounded,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );
}

class _ImageControl extends StatelessWidget {
  const _ImageControl({required this.icon, this.color, this.onTap});
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? AppColors.primary,
    shape: const CircleBorder(),
    elevation: 2,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      supportedDevices: const {PointerDeviceKind.touch},
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 15, color: Colors.white),
      ),
    ),
  );
}

class _ImageCropSlider extends StatelessWidget {
  const _ImageCropSlider({
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

class _PaperPainter extends CustomPainter {
  const _PaperPainter({
    required this.style,
    required this.isPdf,
    required this.lineOpacity,
  });
  final PaperStyle style;
  final bool isPdf;
  final double lineOpacity;
  @override
  void paint(Canvas canvas, Size size) {
    if (isPdf || style == PaperStyle.blank) return;
    final paint = Paint()
      ..color = const Color(0xff758ab4).withValues(alpha: lineOpacity)
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
        ..color = const Color(
          0xffd9822b,
        ).withValues(alpha: (lineOpacity * 1.5).clamp(.04, .5))
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.isPdf != isPdf ||
      oldDelegate.lineOpacity != lineOpacity;
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
    this.activePenStyle = PenStyle.calligraphy,
  });
  final List<InkStroke> strokes;
  final PenStyle activePenStyle;
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
      _paintInkStroke(
        canvas,
        stroke.points,
        stroke.color,
        stroke.width,
        highlight: stroke.tool == EditorTool.highlighter,
        style: stroke.penStyle,
      );
    }
    if (activePoints != null) {
      _paintInkStroke(
        canvas,
        activePoints!,
        activeColor,
        activeWidth,
        highlight: selectionTool == EditorTool.highlighter,
        style: activePenStyle,
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

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}

/// Vẽ một nét mực theo kiểu bút. Dùng chung cho canvas và ô xem trước.
void _paintInkStroke(
  Canvas canvas,
  List<StrokePoint> points,
  Color color,
  double width, {
  required bool highlight,
  PenStyle style = PenStyle.calligraphy,
}) {
  if (points.length < 2) return;

  // Build a smoothed centerline from quadratic midpoints.
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

  if (!highlight && (style == PenStyle.marker || style == PenStyle.pencil)) {
    _paintUniformStroke(canvas, centers, color, width, style);
    return;
  }

  // Expand the centerline into a filled left/right mesh. This gives every
  // point its own radius, unlike Canvas.drawPath(strokeWidth), and produces
  // natural tapering.
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
    final double radius;
    final double startTaperLength;
    final double endTaperLength;
    if (highlight) {
      radius = width * .5 * speedFactor;
      startTaperLength = 4;
      endTaperLength = 5;
    } else {
      switch (style) {
        case PenStyle.fountain:
          // Thin hairline at light pressure, swelling as the nib is pressed.
          radius = width * .5 * (.3 + .95 * pressure) * speedFactor;
          startTaperLength = 3;
          endTaperLength = 8;
        case PenStyle.ballpoint:
          radius = width * .5 * (.82 + .18 * pressure);
          startTaperLength = 1.5;
          endTaperLength = 1.5;
        case PenStyle.calligraphy || PenStyle.marker || PenStyle.pencil:
          final nibFactor = .76 + .28 * math.sin(direction + math.pi / 5).abs();
          radius = width * .5 * pressure * speedFactor * nibFactor;
          startTaperLength = 4;
          endTaperLength = 5;
      }
    }
    final startTaper = (i / startTaperLength).clamp(0, 1);
    final endTaper = ((centers.length - 1 - i) / endTaperLength).clamp(0, 1);
    radii.add(radius * math.min(startTaper, endTaper));
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
  if (!highlight && style == PenStyle.ballpoint) {
    // Round end caps keep the nearly uniform line from looking clipped.
    final cap = Paint()
      ..isAntiAlias = true
      ..color = color;
    canvas
      ..drawCircle(centers.first, radii[1.clamp(0, radii.length - 1)], cap)
      ..drawCircle(
        centers.last,
        radii[(radii.length - 2).clamp(0, radii.length - 1)],
        cap,
      );
  }
}

/// Bút dạ và bút chì: nét có độ rộng cố định, đầu tròn.
void _paintUniformStroke(
  Canvas canvas,
  List<Offset> centers,
  Color color,
  double width,
  PenStyle style,
) {
  final path = Path()..moveTo(centers.first.dx, centers.first.dy);
  for (var i = 1; i < centers.length - 1; i++) {
    final control = centers[i];
    final end = Offset.lerp(centers[i], centers[i + 1], .5)!;
    path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
  }
  path.lineTo(centers.last.dx, centers.last.dy);
  final paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  if (style == PenStyle.marker) {
    canvas.drawPath(
      path,
      paint
        ..color = color
        ..strokeWidth = width * 1.5,
    );
    return;
  }
  // Graphite: a soft, lighter core plus two offset passes that read as the
  // grain of a pencil dragged over paper.
  final strokeWidth = (width * .62).clamp(.8, 6.0);
  final alpha = color.a;
  canvas.drawPath(
    path,
    paint
      ..color = color.withValues(alpha: alpha * .62)
      ..strokeWidth = strokeWidth
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .35),
  );
  final grain = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = strokeWidth * .45
    ..color = color.withValues(alpha: alpha * .28);
  canvas
    ..drawPath(path.shift(Offset(strokeWidth * .22, -strokeWidth * .18)), grain)
    ..drawPath(path.shift(Offset(-strokeWidth * .2, strokeWidth * .2)), grain);
}

/// Các điểm giả lập dọc một đường cong để xem trước kiểu bút, áp lực tăng
/// rồi giảm như khi viết thật.
List<StrokePoint> _previewStrokePoints(Size size) {
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
  final points = <StrokePoint>[];
  for (final metric in path.computeMetrics()) {
    const steps = 48;
    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final tangent = metric.getTangentForOffset(metric.length * t);
      if (tangent == null) continue;
      points.add(
        StrokePoint(
          tangent.position,
          .45 + .55 * math.sin(t * math.pi),
          step * 8000,
        ),
      );
    }
  }
  return points;
}

class _Ruler extends StatelessWidget {
  const _Ruler({
    required this.angle,
    required this.height,
    required this.onScaleStart,
    required this.onScaleUpdate,
  });
  final double angle;
  final double height;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;

  @override
  Widget build(BuildContext context) => GestureDetector(
    supportedDevices: const {PointerDeviceKind.touch},
    behavior: HitTestBehavior.opaque,
    onScaleStart: onScaleStart,
    onScaleUpdate: onScaleUpdate,
    child: Transform.rotate(
      angle: angle,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xbbdce1ff),
          border: Border.all(color: AppColors.primary.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            for (var i = 0; i < 28; i++)
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
                'Một ngón kéo · Hai ngón thu phóng / xoay · Pencil để kẻ',
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
    required this.editing,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onConfirmEdit,
    required this.onDrag,
    required this.onResize,
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
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onConfirmEdit;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onResize;

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
      color: Theme.of(context).colorScheme.surface,
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
                    supportedDevices: const {PointerDeviceKind.touch},
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
                  supportedDevices: const {PointerDeviceKind.touch},
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
    required this.editing,
    required this.onClose,
    required this.onPin,
    required this.onWeakness,
    required this.onAskMore,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onConfirmEdit,
    required this.onDrag,
    required this.onResize,
    required this.showOcr,
  });
  final _SmartResult result;
  final double width;
  final double height;
  final bool editing;
  final VoidCallback onClose;
  final VoidCallback onPin;
  final VoidCallback onWeakness;
  final VoidCallback onAskMore;
  final VoidCallback onEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onConfirmEdit;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onResize;
  final bool showOcr;
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
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    supportedDevices: const {PointerDeviceKind.touch},
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
                  if (result.dictionaryEntry != null || showOcr) ...[
                    const SizedBox(height: 12),
                    if (result.dictionaryEntry == null)
                      const Text(
                        'NỘI DUNG OCR',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey,
                          letterSpacing: .7,
                        ),
                      ),
                    Text(
                      result.source,
                      style: TextStyle(
                        fontSize: result.dictionaryEntry != null ? 18 : 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.55,
                      ),
                    ),
                  ],
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
                      if (result.dictionaryEntry == null)
                        OutlinedButton.icon(
                          onPressed: onAskMore,
                          icon: const Icon(
                            Icons.question_answer_outlined,
                            size: 18,
                          ),
                          label: const Text('Hỏi thêm'),
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
                supportedDevices: const {PointerDeviceKind.touch},
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

class _RotationControl extends StatelessWidget {
  const _RotationControl({
    required this.angle,
    required this.enabled,
    required this.onChanged,
  });
  final double angle;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // Show -15° rather than 345° for small counter-clockwise tilts.
    final shown = angle > 180 ? angle - 360 : angle;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Xoay trái 15°',
            onPressed: enabled ? () => onChanged(angle - 15) : null,
            icon: const Icon(Icons.rotate_left_rounded, size: 18),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '${shown.round()}°',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Xoay phải 15°',
            onPressed: enabled ? () => onChanged(angle + 15) : null,
            icon: const Icon(Icons.rotate_right_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'Trả trang về thẳng',
            onPressed: enabled && angle != 0 ? () => onChanged(0) : null,
            icon: const Icon(Icons.crop_rotate_rounded, size: 18),
          ),
        ],
      ),
    );
  }
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
  const _PenPreviewPainter({
    required this.color,
    required this.width,
    required this.style,
  });
  final Color color;
  final double width;
  final PenStyle style;

  @override
  void paint(Canvas canvas, Size size) => _paintInkStroke(
    canvas,
    _previewStrokePoints(size),
    color,
    width,
    highlight: false,
    style: style,
  );

  @override
  bool shouldRepaint(covariant _PenPreviewPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.width != width ||
      oldDelegate.style != style;
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
