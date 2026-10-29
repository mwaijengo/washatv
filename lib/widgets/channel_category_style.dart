import 'package:flutter/material.dart';

import '../constants/app_channel_categories.dart';
import '../theme/app_theme.dart';

class ChannelCategoryStyle {
  const ChannelCategoryStyle({
    required this.icon,
    required this.color,
    required this.gradient,
  });

  final IconData icon;
  final Color color;
  final List<Color> gradient;

  static ChannelCategoryStyle forCategory(String category) {
    return _styles[category] ?? _default;
  }

  static const _default = ChannelCategoryStyle(
    icon: Icons.live_tv_rounded,
    color: AppTheme.cyan,
    gradient: [Color(0xFF00D4FF), Color(0xFF00E5C7)],
  );

  static const _styles = <String, ChannelCategoryStyle>{
    'Sports': ChannelCategoryStyle(
      icon: Icons.sports_soccer_rounded,
      color: Color(0xFF34D399),
      gradient: [Color(0xFF34D399), Color(0xFF10B981)],
    ),
    'Movies': ChannelCategoryStyle(
      icon: Icons.movie_rounded,
      color: Color(0xFF7B61FF),
      gradient: [Color(0xFF7B61FF), Color(0xFFA855F7)],
    ),
    'News': ChannelCategoryStyle(
      icon: Icons.newspaper_rounded,
      color: Color(0xFF38BDF8),
      gradient: [Color(0xFF38BDF8), Color(0xFF0EA5E9)],
    ),
    'Trending': ChannelCategoryStyle(
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFF6B35),
      gradient: [Color(0xFFFF6B35), Color(0xFFFFB020)],
    ),
    'Kids': ChannelCategoryStyle(
      icon: Icons.child_care_rounded,
      color: Color(0xFFF472B6),
      gradient: [Color(0xFFF472B6), Color(0xFFEC4899)],
    ),
    'Wildlife': ChannelCategoryStyle(
      icon: Icons.pets_rounded,
      color: Color(0xFFFBBF24),
      gradient: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
    ),
  };
}

String channelCategoryLabel(String category) => categoryDisplayName(category);
