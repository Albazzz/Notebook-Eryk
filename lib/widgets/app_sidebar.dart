import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

IconData _folderIcon(int codePoint) =>
    // ignore: non_const_argument_for_const_parameter
    IconData(codePoint, fontFamily: 'MaterialIcons');

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, required this.state, this.compact = false});
  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.asset(
                    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
                    width: 42,
                    height: 42,
                    cacheWidth: 126,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Note Eryk',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      height: 1.05,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            TextField(
              onChanged: state.setFolderSearchQuery,
              decoration: InputDecoration(
                hintText: 'Tìm folder/note…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: state.folderSearchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => state.setFolderSearchQuery(''),
                        icon: const Icon(Icons.clear),
                      ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 18),
            _NavItem(
              icon: Icons.auto_stories_outlined,
              label: 'Vở của tôi',
              active: state.destination == AppDestination.library,
              onTap: () => _go(context, AppDestination.library),
            ),
            if (state.destination == AppDestination.library) ...[
              const SizedBox(height: 8),
              _FolderTree(state: state),
            ],
            _NavItem(
              icon: Icons.bookmark_border_rounded,
              label: 'Điểm yếu',
              active: state.destination == AppDestination.weaknesses,
              badge: state.weakPoints.length,
              onTap: () => _go(context, AppDestination.weaknesses),
            ),
            _NavItem(
              icon: Icons.menu_book_outlined,
              label: 'Tra từ nhanh',
              active: state.destination == AppDestination.dictionary,
              onTap: () => _go(context, AppDestination.dictionary),
            ),
            _NavItem(
              icon: Icons.settings_outlined,
              label: 'Cài đặt',
              active: state.destination == AppDestination.settings,
              onTap: () => _go(context, AppDestination.settings),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Color(0xffdce1ff),
                    child: Icon(Icons.person_outline, color: AppColors.primary),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Học viên ${state.studentName}',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Lưu cục bộ · ${state.jlpt}',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
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

  Future<void> _go(BuildContext context, AppDestination destination) async {
    if (compact) {
      // The Drawer owns inherited dependents (Theme, MediaQuery, etc.). Let its
      // route finish tearing down before the app shell changes destination.
      await Navigator.maybePop(context);
      await WidgetsBinding.instance.endOfFrame;
    }
    state.goTo(destination);
  }
}

class _FolderTree extends StatelessWidget {
  const _FolderTree({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final query = state.folderSearchQuery.trim().toLowerCase();
    final roots = state.childFolders(null).where((folder) {
      if (query.isEmpty) return true;
      return folder.name.toLowerCase().contains(query) ||
          state
              .folderTreeIds(folder.id)
              .any(
                (id) =>
                    state.folderById(id)?.name.toLowerCase().contains(query) ??
                    false,
              );
    }).toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 390),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SmartSectionRow(
              icon: Icons.folder_outlined,
              label: 'Tất cả ghi chú',
              count: state.folderNoteCount(null),
              active:
                  state.librarySection == 'all' &&
                  state.selectedFolderId == null,
              onTap: () => state.selectLibrarySection('all'),
              onAccept: (data) {
                if (_moveData(data, null)) _showUndo(context);
              },
            ),
            _SmartSectionRow(
              icon: Icons.star_outline_rounded,
              label: 'Yêu thích',
              count: state.favoriteNotes().length,
              active: state.librarySection == 'favorites',
              onTap: () => state.selectLibrarySection('favorites'),
            ),
            _SmartSectionRow(
              icon: Icons.history_rounded,
              label: 'Gần đây',
              count: state.notebooks.where((note) => !note.isTrashed).length,
              active: state.librarySection == 'recent',
              onTap: () => state.selectLibrarySection('recent'),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'FOLDER',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tạo folder',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _createFolder(context),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 19),
                ),
              ],
            ),
            for (final folder in roots)
              _FolderRow(state: state, folder: folder, depth: 0),
            _SmartSectionRow(
              icon: Icons.delete_outline_rounded,
              label: 'Thùng rác',
              count: state.notebooks.where((note) => note.isTrashed).length,
              active: state.librarySection == 'trash',
              onTap: () => state.selectLibrarySection('trash'),
            ),
          ],
        ),
      ),
    );
  }

  bool _moveData(String data, String? folderId) {
    if (data.startsWith('notes:')) {
      return state.moveNotebooksToFolder(
        data.substring(6).split(','),
        folderId,
      );
    } else if (data.startsWith('note:')) {
      return state.moveNotebookToFolder(data.substring(5), folderId);
    } else if (data.startsWith('folder:')) {
      return state.moveFolder(data.substring(7), folderId);
    }
    return false;
  }

  void _showUndo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Đã di chuyển'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: state.undoFolderAction,
        ),
      ),
    );
  }

  Future<void> _createFolder(BuildContext context, {String? parentId}) async {
    final controller = TextEditingController();
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
    if (accepted == true) {
      state.createFolder(controller.text, parentId: parentId);
    }
    controller.dispose();
  }
}

class _SmartSectionRow extends StatelessWidget {
  const _SmartSectionRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    this.onAccept,
  });
  final IconData icon;
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<String>? onAccept;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onAcceptWithDetails: onAccept == null
        ? null
        : (details) => onAccept!(details.data),
    builder: (context, candidates, _) => Material(
      color: candidates.isNotEmpty
          ? Theme.of(context).colorScheme.primaryContainer
          : active
          ? const Color(0xffdce1ff)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(icon, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FolderRow extends StatefulWidget {
  const _FolderRow({
    required this.state,
    required this.folder,
    required this.depth,
  });
  final AppState state;
  final FolderData folder;
  final int depth;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final children = widget.state.childFolders(folder.id);
    final active =
        widget.state.selectedFolderId == folder.id &&
        widget.state.librarySection == 'all';
    return Column(
      children: [
        LongPressDraggable<String>(
          data: 'folder:${folder.id}',
          feedback: Material(
            color: Colors.transparent,
            child: Chip(
              label: Text(folder.name),
              avatar: Icon(_folderIcon(folder.iconCodePoint)),
            ),
          ),
          child: DragTarget<String>(
            onAcceptWithDetails: (details) {
              final data = details.data;
              var moved = false;
              if (data.startsWith('notes:')) {
                moved = widget.state.moveNotebooksToFolder(
                  data.substring(6).split(','),
                  folder.id,
                );
              } else if (data.startsWith('note:')) {
                moved = widget.state.moveNotebookToFolder(
                  data.substring(5),
                  folder.id,
                );
              } else if (data.startsWith('folder:')) {
                moved = widget.state.moveFolder(data.substring(7), folder.id);
              }
              if (moved && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Đã di chuyển'),
                    duration: const Duration(seconds: 3),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: widget.state.undoFolderAction,
                    ),
                  ),
                );
              }
            },
            builder: (context, candidates, _) => MouseRegion(
              onEnter: (_) => setState(() => hovering = true),
              onExit: (_) => setState(() => hovering = false),
              child: Material(
                color: candidates.isNotEmpty
                    ? Theme.of(context).colorScheme.primaryContainer
                    : active
                    ? const Color(0xffdce1ff)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      SizedBox(width: 8 + widget.depth * 16),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: children.isEmpty
                            ? null
                            : () =>
                                  widget.state.toggleFolderExpanded(folder.id),
                        icon: Icon(
                          folder.isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.chevron_right,
                          size: 19,
                        ),
                      ),
                      Icon(
                        _folderIcon(folder.iconCodePoint),
                        color: Color(folder.color),
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => widget.state.selectFolder(folder.id),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${folder.name}  (${widget.state.folderNoteCount(folder.id)})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (folder.isPinned)
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                      if (hovering || active)
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_horiz, size: 19),
                          onSelected: (value) => _handleMenu(context, value),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'new',
                              child: Text('New subfolder'),
                            ),
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            PopupMenuItem(
                              value: 'appearance',
                              child: Text('Change color/icon'),
                            ),
                            PopupMenuItem(value: 'move', child: Text('Move')),
                            PopupMenuItem(value: 'pin', child: Text('Pin')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        )
                      else
                        const SizedBox(width: 44),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (folder.isExpanded)
          for (final child in children)
            _FolderRow(
              state: widget.state,
              folder: child,
              depth: widget.depth + 1,
            ),
      ],
    );
  }

  Future<void> _handleMenu(BuildContext context, String action) async {
    final folder = widget.folder;
    if (action == 'new') {
      final controller = TextEditingController();
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Folder con mới'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên folder'),
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
      if (accepted == true) {
        widget.state.createFolder(controller.text, parentId: folder.id);
      }
      controller.dispose();
    } else if (action == 'rename') {
      final controller = TextEditingController(text: folder.name);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Đổi tên folder'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Lưu'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        widget.state.renameFolder(folder.id, controller.text);
      }
      controller.dispose();
    } else if (action == 'pin') {
      widget.state.pinFolder(folder.id);
    } else if (action == 'delete') {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xóa folder?'),
          content: const Text(
            'Bạn muốn xóa cả folder và ghi chú bên trong hay chỉ xóa folder?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'parent'),
              child: const Text('Move notes to parent'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'trash'),
              child: const Text('Move to Trash'),
            ),
          ],
        ),
      );
      if (result == 'parent') {
        widget.state.deleteFolder(folder.id, moveToTrash: false);
      }
      if (result == 'trash') {
        widget.state.deleteFolder(folder.id, moveToTrash: true);
      }
      if (result != null &&
          result != 'cancel' &&
          widget.state.canUndoFolderAction &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã thay đổi folder'),
            duration: Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: widget.state.undoFolderAction,
            ),
          ),
        );
      }
    } else if (action == 'move') {
      final targets = widget.state.folders
          .where(
            (item) =>
                item.id != folder.id &&
                !widget.state.folderTreeIds(folder.id).contains(item.id) &&
                !item.isTrashed,
          )
          .toList();
      final target = await showModalBottomSheet<String?>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text('Chọn folder cha'),
                onTap: () => Navigator.pop(sheetContext, 'root'),
              ),
              for (final item in targets)
                ListTile(
                  title: Text(item.name),
                  onTap: () => Navigator.pop(sheetContext, item.id),
                ),
            ],
          ),
        ),
      );
      var moved = false;
      if (target == 'root') {
        moved = widget.state.moveFolder(folder.id, null);
      }
      if (target != null && target != 'root') {
        moved = widget.state.moveFolder(folder.id, target);
      }
      if (moved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Folder đã di chuyển'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: widget.state.undoFolderAction,
            ),
          ),
        );
      }
    } else if (action == 'appearance') {
      final choice = await showModalBottomSheet<Map<String, int>>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Màu folder')),
              Wrap(
                children: [
                  for (final value in [
                    0xff6b7280,
                    0xff2563eb,
                    0xff16a34a,
                    0xffd97706,
                    0xffdc2626,
                    0xff9333ea,
                  ])
                    IconButton(
                      icon: Icon(Icons.folder, color: Color(value)),
                      onPressed: () =>
                          Navigator.pop(sheetContext, {'color': value}),
                    ),
                ],
              ),
              const ListTile(title: Text('Biểu tượng')),
              Wrap(
                children: [
                  for (final value in [
                    Icons.folder.codePoint,
                    Icons.bookmark.codePoint,
                    Icons.school.codePoint,
                    Icons.workspaces.codePoint,
                    Icons.star.codePoint,
                    Icons.archive.codePoint,
                  ])
                    IconButton(
                      icon: Icon(_folderIcon(value)),
                      onPressed: () =>
                          Navigator.pop(sheetContext, {'icon': value}),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      if (choice != null) {
        widget.state.updateFolderAppearance(
          folder.id,
          color: choice['color'],
          iconCodePoint: choice['icon'],
        );
      }
    }
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: active ? const Color(0xffdce1ff) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  icon,
                  color: active
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
