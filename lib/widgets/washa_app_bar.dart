import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';

class WashaAppBar extends StatelessWidget {
  const WashaAppBar({
    super.key,
    this.displayName,
    this.premium = false,
    this.showAvatar = true,
    this.trailing,
  });

  final String? displayName;
  final bool premium;
  final bool showAvatar;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(displayName);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: AppTheme.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: AppTheme.cyan.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.play_arrow_rounded, color: AppTheme.background, size: 26),
        )
            .animate()
            .fadeIn(duration: 400.ms)
            .scale(begin: const Offset(0.8, 0.8), duration: 400.ms, curve: Curves.easeOutBack),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
                child: Text(
                  'WASHA TV',
                  style: AppTheme.displayLarge.copyWith(
                    fontSize: 26,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                'Stream bora, ubora wa HD',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textMuted,
                  letterSpacing: 0.3,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (showAvatar) ...[
          const SizedBox(width: 10),
          _PremiumBadge(premium: premium),
          const SizedBox(width: 8),
          _Avatar(initials: initials),
        ],
      ],
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .slideY(begin: -0.1, end: 0, duration: 350.ms, curve: Curves.easeOutCubic);
  }

  String _initials(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty || n.toLowerCase() == 'free user' || n.toLowerCase() == 'mtumiaji') {
      return 'MT';
    }
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length.clamp(1, 2)).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge({required this.premium});

  final bool premium;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: premium ? AppTheme.premiumGradient : null,
        color: premium ? null : AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: premium ? AppTheme.gold.withValues(alpha: 0.5) : AppTheme.white10,
        ),
        boxShadow: premium
            ? [
                BoxShadow(
                  color: AppTheme.gold.withValues(alpha: 0.25),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Text(
        premium ? 'PREMIUM' : 'FREE',
        style: AppTheme.labelSmall.copyWith(
          fontSize: 9,
          color: premium ? AppTheme.background : AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppTheme.accentGradient,
        boxShadow: [
          BoxShadow(
            color: AppTheme.violet.withValues(alpha: 0.3),
            blurRadius: 12,
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.surfaceElevated,
        ),
        child: Center(
          child: Text(
            initials,
            style: AppTheme.titleMedium.copyWith(fontSize: 14),
          ),
        ),
      ),
    );
  }
}
