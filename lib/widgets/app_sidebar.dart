import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

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
            _NavItem(
              icon: Icons.auto_stories_outlined,
              label: 'Vở của tôi',
              active: state.destination == AppDestination.library,
              onTap: () => _go(context, AppDestination.library),
            ),
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
              child: const Row(
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
                          'Học viên Zen',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Lưu cục bộ · N3',
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
