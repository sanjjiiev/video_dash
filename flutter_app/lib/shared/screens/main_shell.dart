import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../widgets/mini_player.dart';
import '../../core/providers/player_provider.dart';

/// Persistent bottom navigation shell.
/// Wraps the ShellRoute — the nav bar stays visible across all main tabs.
class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  static const _tabs = [
    _TabItem(icon: Icons.home_outlined,       activeIcon: Icons.home_rounded,     label: 'Home',    route: '/'),
    _TabItem(icon: Icons.bolt_outlined,       activeIcon: Icons.bolt_rounded,     label: 'Shorts',  route: '/shorts'),
    _TabItem(icon: Icons.add_circle_outline,  activeIcon: Icons.add_circle,       label: 'Upload',  route: '/upload'),
    _TabItem(icon: Icons.search_outlined,     activeIcon: Icons.search_rounded,   label: 'Search',  route: '/search'),
    _TabItem(icon: Icons.person_outline,      activeIcon: Icons.person_rounded,   label: 'You',     route: '/profile'),
  ];

  void _onTap(int index, BuildContext context) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    context.go(_tabs[index].route);
  }

  @override
  Widget build(BuildContext context) {
    // Sync index from current route
    final location = GoRouterState.of(context).matchedLocation;
    final syncedIndex = _tabs.indexWhere((t) => t.route == location);
    if (syncedIndex != -1 && syncedIndex != _currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = syncedIndex);
      });
    }

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Column(
        children: [
          Expanded(child: widget.child),
          // Mini player strip (visible when navigating away from player)
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: _HubBottomNav(
        currentIndex: _currentIndex,
        tabs:         _tabs,
        onTap:        (i) => _onTap(i, context),
      ),
    );
  }
}

// ── Custom Bottom Navigation Bar ──────────────────────────────────────────────
class _HubBottomNav extends StatelessWidget {
  final int              currentIndex;
  final List<_TabItem>   tabs;
  final ValueChanged<int> onTap;

  const _HubBottomNav({
    required this.currentIndex,
    required this.tabs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 68 + MediaQuery.of(context).padding.bottom,
    decoration: const BoxDecoration(
      color: AppColors.darkSurface,
      border: Border(top: BorderSide(color: AppColors.darkDivider, width: 0.5)),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(tabs.length, (i) {
          final tab       = tabs[i];
          final isActive  = i == currentIndex;
          final isUpload  = tab.route == '/upload';

          // Upload tab gets special treatment — center plus icon
          if (isUpload) {
            return GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient:     AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentOrange.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
              ),
            );
          }

          return GestureDetector(
            onTap:     () => onTap(i),
            behavior:  HitTestBehavior.opaque,
            child: SizedBox(
              width: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration:       const Duration(milliseconds: 150),
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      isActive ? tab.activeIcon : tab.icon,
                      key:   ValueKey(isActive),
                      color: isActive ? AppColors.accentOrange : AppColors.textSecondary,
                      size:  24,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: TextStyle(
                      color:      isActive ? AppColors.accentOrange : AppColors.textSecondary,
                      fontSize:   10,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                    ),
                    child: Text(tab.label),
                  ),
                  // Active dot indicator
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin:    const EdgeInsets.only(top: 3),
                    width:     isActive ? 16 : 0,
                    height:    2,
                    decoration: BoxDecoration(
                      color:        AppColors.accentOrange,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    ),
  );
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String   label;
  final String   route;
  const _TabItem({
    required this.icon, required this.activeIcon,
    required this.label, required this.route,
  });
}
