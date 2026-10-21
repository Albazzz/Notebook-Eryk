import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'page_rendering.dart';

/// Bìa vở trong thư viện: ảnh thu nhỏ của trang 1 (trang PDF, ảnh nền/ảnh
/// chèn, giấy kẻ và nét viết tay) thay vì một khối màu cố định.
class NotebookCover extends StatefulWidget {
  const NotebookCover({
    super.key,
    required this.state,
    required this.notebook,
    this.selected = false,
  });

  final AppState state;
  final NotebookData notebook;
  final bool selected;

  @override
  State<NotebookCover> createState() => _NotebookCoverState();
}

class _NotebookCoverState extends State<NotebookCover> {
  static const _page = 1;
  Future<Uint8List?>? _pdfPage;
  String? _pdfSource;

  AppState get state => widget.state;
  NotebookData get notebook => widget.notebook;

  List<PageImagePlacement> get _placements =>
      state.imagePlacementsForPage(notebook.id, _page);

  bool get _blankPage => state.blankPages.contains('${notebook.id}:$_page');

  /// Trang PDF chỉ cần render khi trang 1 không bị ảnh nền hay trang trắng
  /// thay thế (giống editor).
  String? get _pdfToRender {
    final source = state.sourceDocuments[notebook.id];
    if (!notebook.isPdf || source == null || _blankPage) return null;
    if (_placements.any((placement) => placement.isBackground)) return null;
    return source;
  }

  void _syncPdf() {
    final source = _pdfToRender;
    if (source == _pdfSource) return;
    _pdfSource = source;
    _pdfPage = source == null ? null : state.renderPdfPage(notebook.id, _page);
  }

  @override
  void initState() {
    super.initState();
    _syncPdf();
  }

  @override
  void didUpdateWidget(covariant NotebookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notebook.id != notebook.id) _pdfSource = null;
    _syncPdf();
  }

  @override
  Widget build(BuildContext context) {
    final size = state.pageCanvasSize;
    final scheme = Theme.of(context).colorScheme;
    final placements = _placements;
    final hasBackground = placements.any((placement) => placement.isBackground);
    final page = SizedBox.fromSize(
      size: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.paper),
          if (_pdfPage != null)
            FutureBuilder<Uint8List?>(
              future: _pdfPage,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) return const SizedBox.shrink();
                return Image.memory(
                  bytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                );
              },
            ),
          CustomPaint(
            painter: PaperPainter(
              style: notebook.paperStyle,
              isPdf: (notebook.isPdf && !_blankPage) || hasBackground,
              lineOpacity: notebook.paperLineOpacity,
              lineColor: notebook.paperLineColor,
            ),
          ),
          for (final placement in placements)
            Positioned.fromRect(
              rect: Rect.fromLTWH(
                placement.rect.left * size.width,
                placement.rect.top * size.height,
                placement.rect.width * size.width,
                placement.rect.height * size.height,
              ),
              child: Transform.rotate(
                angle: placement.rotation,
                child: Image.file(
                  File(placement.path),
                  fit: placement.isBackground ? BoxFit.fill : BoxFit.contain,
                  cacheWidth: 600,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          CustomPaint(
            painter: InkStrokesPainter(state.strokesFor(notebook.id, _page)),
          ),
        ],
      ),
    );
    return Center(
      child: AspectRatio(
        aspectRatio: size.width / size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.selected
                  ? AppColors.primary
                  : scheme.outlineVariant,
              width: widget.selected ? 3 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: RepaintBoundary(
              child: FittedBox(fit: BoxFit.fill, child: page),
            ),
          ),
        ),
      ),
    );
  }
}
