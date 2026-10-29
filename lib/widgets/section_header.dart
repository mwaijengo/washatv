import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    this.accentColor = AppTheme.cyan,
    this.animationDelay = Duration.zero,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Color accentColor;
  final Duration animationDelay;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: [
                  accentColor.withValues(alpha: 0.25),
                  accentColor.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppTheme.bodyMedium.copyWith(fontSize: 12)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    )
        .animate(delay: animationDelay)
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideX(begin: -0.05, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }
}
