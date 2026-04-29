import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = 24,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: AppTheme.glass(
            radius: BorderRadius.circular(radius),
            color: color,
          ),
          child: child,
        ),
      ),
    );
  }
}
