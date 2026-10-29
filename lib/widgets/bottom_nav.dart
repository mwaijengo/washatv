import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../app.dart';
import '../theme/app_theme.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.current,
    required this.onTap,
  });

  final AppScreen current;
  final ValueChanged<AppScreen> onTap;

  static const _items = [
    (Icons.home_rounded, 'Nyumbani', AppScreen.home),
    (Icons.grid_view_rounded, 'Aina', AppScreen.categories),
    (Icons.diamond_rounded, 'Premium', AppScreen.subscription),
    (Icons.person_rounded, 'Akaunti', AppScreen.profile),
    (Icons.settings_rounded, 'Mipangilio', AppScreen.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: AppTheme.blur32,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.navPanel,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 32,
                  offset: const Offset(0, -4),
                ),
                BoxShadow(
                  color: AppTheme.cyan.withValues(alpha: 0.06),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  _NavItem(
                    icon: _items[i].$1,
                    label: _items[i].$2,
                    screen: _items[i].$3,
                    active: current == _items[i].$3,
                    onTap: () => onTap(_items[i].$3),
                    index: i,
                  ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms, delay: 200.ms)
        .slideY(begin: 0.3, end: 0, duration: 500.ms, curve: Curves.easeOutCubic);
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.screen,
    required this.active,
    required this.onTap,
    required this.index,
  });

  final IconData icon;
  final String label;
  final AppScreen screen;
  final bool active;
  final VoidCallback onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: active ? AppTheme.primaryGradient : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppTheme.cyan.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? AppTheme.background : AppTheme.textMuted,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.labelSmall.copyWith(
                  fontSize: 8,
                  color: active ? AppTheme.background : AppTheme.textMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
