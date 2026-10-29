import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum GradientButtonStyle { primary, premium, accent }

class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = GradientButtonStyle.primary,
    this.expanded = false,
    this.loading = false,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final GradientButtonStyle style;
  final bool expanded;
  final bool loading;
  final double height;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  LinearGradient get _gradient => switch (widget.style) {
        GradientButtonStyle.premium => AppTheme.premiumGradient,
        GradientButtonStyle.accent => AppTheme.accentGradient,
        GradientButtonStyle.primary => AppTheme.primaryGradient,
      };

  Color get _shadowColor => switch (widget.style) {
        GradientButtonStyle.premium => AppTheme.gold,
        GradientButtonStyle.accent => AppTheme.violet,
        GradientButtonStyle.primary => AppTheme.cyan,
      };

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: widget.height,
        width: widget.expanded ? double.infinity : null,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: enabled ? _gradient : null,
          color: enabled ? null : AppTheme.surfaceElevated,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: _shadowColor.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? widget.onPressed : null,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.background,
                      ),
                    )
                  else if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: AppTheme.background),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: AppTheme.titleMedium.copyWith(
                      color: enabled ? AppTheme.background : AppTheme.textMuted,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
