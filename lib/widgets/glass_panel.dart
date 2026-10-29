import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = 20,
    this.color,
    this.border,
    this.glowColor,
    this.glow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? color;
  final Border? border;
  final Color? glowColor;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: AppTheme.blur24,
        child: Container(
          padding: padding,
          decoration: AppTheme.glass(
            radius: r,
            color: color,
            border: border ??
                Border.all(
                  color: glow
                      ? (glowColor ?? AppTheme.cyan).withValues(alpha: 0.25)
                      : AppTheme.white07,
                ),
            shadow: glow
                ? [
                    BoxShadow(
                      color: (glowColor ?? AppTheme.cyan).withValues(alpha: 0.15),
                      blurRadius: 24,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
