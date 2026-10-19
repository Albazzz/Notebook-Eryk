import 'package:flutter/material.dart';

import '../models.dart';

/// Danh sách chọn điểm yếu chia thành trang [pageSize] mục, vuốt ngang để
/// sang trang. Danh sách dài không còn phải kéo dọc rất xa.
/// Cần được đặt trong vùng có chiều cao giới hạn (ví dụ Expanded).
class PagedPointPicker extends StatefulWidget {
  const PagedPointPicker({
    super.key,
    required this.points,
    required this.selectedIds,
    required this.onChanged,
    this.pageSize = 10,
    this.isDisabled,
  });

  final List<WeakPoint> points;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;
  final int pageSize;

  /// Mục thiếu dữ liệu: vẫn hiện nhưng gạch mờ để người học biết bị bỏ qua.
  final bool Function(WeakPoint point)? isDisabled;

  @override
  State<PagedPointPicker> createState() => _PagedPointPickerState();
}

class _PagedPointPickerState extends State<PagedPointPicker> {
  final PageController _controller = PageController();
  int _page = 0;

  int get _pageCount => widget.points.isEmpty
      ? 1
      : (widget.points.length / widget.pageSize).ceil();

  List<WeakPoint> _pageItems(int page) {
    final start = page * widget.pageSize;
    if (start >= widget.points.length) return const [];
    final end = (start + widget.pageSize).clamp(0, widget.points.length);
    return widget.points.sublist(start, end);
  }

  @override
  void didUpdateWidget(covariant PagedPointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= _pageCount) {
      _page = _pageCount - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) _controller.jumpToPage(_page);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (page < 0 || page >= _pageCount) return;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _toggle(WeakPoint point, bool selected) {
    final next = Set.of(widget.selectedIds);
    if (selected) {
      next.add(point.id);
    } else {
      next.remove(point.id);
    }
    widget.onChanged(next);
  }

  void _setPage(bool selected) {
    final next = Set.of(widget.selectedIds);
    for (final point in _pageItems(_page)) {
      if (selected) {
        next.add(point.id);
      } else {
        next.remove(point.id);
      }
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = widget.points.length;
    final pageItems = _pageItems(_page);
    final pageAllSelected =
        pageItems.isNotEmpty &&
        pageItems.every((point) => widget.selectedIds.contains(point.id));
    final first = total == 0 ? 0 : _page * widget.pageSize + 1;
    final last = (first - 1 + pageItems.length).clamp(0, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            TextButton(
              onPressed: () =>
                  widget.onChanged(widget.points.map((p) => p.id).toSet()),
              child: const Text('Chọn tất cả'),
            ),
            TextButton(
              onPressed: () => widget.onChanged(<String>{}),
              child: const Text('Bỏ chọn'),
            ),
            TextButton(
              onPressed: pageItems.isEmpty
                  ? null
                  : () => _setPage(!pageAllSelected),
              child: Text(
                pageAllSelected ? 'Bỏ chọn trang này' : 'Chọn trang này',
              ),
            ),
          ],
        ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: _pageCount,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, page) {
              final items = _pageItems(page);
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    'Chưa có mục nào.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                );
              }
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final point in items)
                    CheckboxListTile(
                      key: ValueKey('picker-${point.id}'),
                      value: widget.selectedIds.contains(point.id),
                      title: Text(
                        point.title,
                        style: widget.isDisabled?.call(point) == true
                            ? TextStyle(
                                color: scheme.onSurfaceVariant,
                                decoration: TextDecoration.lineThrough,
                              )
                            : null,
                      ),
                      subtitle: Text(
                        [
                          point.reading,
                          point.content,
                        ].where((part) => part.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: (value) => _toggle(point, value == true),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              tooltip: 'Trang trước',
              onPressed: _page == 0 ? null : () => _goTo(_page - 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    total == 0 ? '0 mục' : '$first–$last / $total',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  if (_pageCount > 1)
                    _PageDots(count: _pageCount, current: _page, onTap: _goTo),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Trang sau',
              onPressed: _page >= _pageCount - 1
                  ? null
                  : () => _goTo(_page + 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

/// Chấm trang; quá nhiều trang thì chỉ hiện các chấm quanh trang hiện tại.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.current,
    required this.onTap,
  });

  final int count;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const visible = 9;
    final start = (current - visible ~/ 2).clamp(
      0,
      (count - visible).clamp(0, count),
    );
    final end = (start + visible).clamp(0, count);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var page = start; page < end; page++)
          GestureDetector(
            onTap: () => onTap(page),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: page == current ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: page == current ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}
