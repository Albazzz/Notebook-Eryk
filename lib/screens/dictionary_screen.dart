import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key, required this.state});
  final AppState state;

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<DictionaryEntry> _results = const [];
  DictionaryEntry? _selected;
  bool _loading = false;
  int _requestSerial = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _selected = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    final serial = ++_requestSerial;
    try {
      final results = await widget.state.dictionary.search(query);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  void _select(DictionaryEntry entry) {
    setState(() => _selected = entry);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PageHeader(
                  title: 'Tra từ nhanh',
                  subtitle:
                      'Gõ kana, kanji hoặc nghĩa tiếng Việt để tìm trong kho từ điển.',
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 10, right: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Ví dụ: たべる, 食べる, ăn...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xóa tìm kiếm',
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          if (_selected != null) ...[
            _DictionaryDetail(entry: _selected!),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: _results.isEmpty
                ? _EmptyDictionary(query: _searchController.text)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 28),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = _results[index];
                      return _DictionaryResultTile(
                        entry: entry,
                        selected: identical(entry, _selected),
                        onTap: () => _select(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DictionaryResultTile extends StatelessWidget {
  const _DictionaryResultTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });
  final DictionaryEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: selected
          ? AppColors.dictionary.withValues(alpha: .1)
          : Theme.of(context).cardTheme.color,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.word}【${entry.reading}】',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.meaning,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.level.isNotEmpty) _LevelBadge(level: entry.level),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _DictionaryDetail extends StatelessWidget {
  const _DictionaryDetail({required this.entry});
  final DictionaryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.dictionary.withValues(alpha: .08),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.word,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (entry.level.isNotEmpty) _LevelBadge(level: entry.level),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              entry.reading,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 9),
            Text(entry.meaning, style: const TextStyle(fontSize: 15)),
            if (entry.hanViet.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text('Hán Việt: ${entry.hanViet}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});
  final String level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.dictionary.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        level,
        style: const TextStyle(
          color: AppColors.dictionary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyDictionary extends StatelessWidget {
  const _EmptyDictionary({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final searching = query.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.menu_book_outlined,
            size: 42,
            color: AppColors.dictionary,
          ),
          const SizedBox(height: 10),
          Text(
            searching ? 'Không tìm thấy từ phù hợp.' : 'Bắt đầu gõ để tra từ.',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (!searching) ...[
            const SizedBox(height: 5),
            const Text(
              'Có thể tìm bằng hiragana, kanji hoặc nghĩa tiếng Việt.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
