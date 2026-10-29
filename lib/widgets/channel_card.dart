import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../constants/app_channel_categories.dart';
import '../models/channel.dart';
import '../theme/app_theme.dart';
import '../utils/cache_bust_image_url.dart';
import 'channel_category_style.dart';

enum ChannelCardVariant { poster, grid, premium }

class ChannelCard extends StatefulWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.locked,
    required this.onTap,
    this.imageCacheEpoch = 0,
    this.index = 0,
    this.variant = ChannelCardVariant.grid,
  });

  final Channel channel;
  final bool locked;
  final VoidCallback onTap;
  final int imageCacheEpoch;
  final int index;
  final ChannelCardVariant variant;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _livePulse;

  @override
  void initState() {
    super.initState();
    _livePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _livePulse.dispose();
    super.dispose();
  }

  Color get _accent => widget.channel.premium ? AppTheme.gold : AppTheme.cyan;

  @override
  Widget build(BuildContext context) {
    final delay = (widget.index * 50).ms;
    final child = switch (widget.variant) {
      ChannelCardVariant.poster => _buildPosterCard(),
      ChannelCardVariant.premium => _buildPremiumFlexCard(),
      ChannelCardVariant.grid => _buildGridCard(),
    };

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    )
        .animate(delay: delay)
        .fadeIn(duration: 420.ms, curve: Curves.easeOut)
        .slideY(
          begin: widget.variant == ChannelCardVariant.poster ? 0.06 : 0.08,
          end: 0,
          duration: 420.ms,
          curve: Curves.easeOutCubic,
        );
  }

  Widget _buildPosterCard() {
    const width = 176.0;
    const imageHeight = 150.0;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PosterFrame(
            accent: _accent,
            locked: widget.locked,
            pressed: _pressed,
            child: SizedBox(
              height: imageHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ChannelThumbnail(
                    url: imageUrlWithCacheEpoch(widget.channel.imageUrl, widget.imageCacheEpoch),
                    channelId: widget.channel.id,
                    borderRadius: 16,
                    hd: true,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                  if (widget.channel.live) _LiveBadge(pulse: _livePulse),
                  const Positioned(top: 8, right: 8, child: _QualityBadge()),
                  if (_pressed && !widget.locked) const _PlayOverlay(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.channel.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.titleMedium.copyWith(fontSize: 13, height: 1.25),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: _AccessPill(
              channel: widget.channel,
              locked: widget.locked,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumFlexCard() {
    final style = ChannelCategoryStyle.forCategory(widget.channel.category);

    return _PosterFrame(
      accent: AppTheme.gold,
      locked: widget.locked,
      pressed: _pressed,
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ChannelThumbnail(
              url: imageUrlWithCacheEpoch(widget.channel.imageUrl, widget.imageCacheEpoch),
              channelId: widget.channel.id,
              borderRadius: 16,
              hd: true,
            ),
            const _ThumbnailOverlay(intensity: 0.82),
            if (widget.channel.live) _LiveBadge(pulse: _livePulse),
            Positioned(
              top: 8,
              right: 8,
              child: _QualityBadge(gold: true),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: _PremiumCornerBadge(),
            ),
            if (_pressed && !widget.locked)
              Container(
                color: Colors.black.withValues(alpha: 0.2),
                alignment: Alignment.center,
                child: _playIcon(size: 44, gold: true),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppTheme.background.withValues(alpha: 0.95),
                      AppTheme.background.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.channel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.titleMedium.copyWith(
                        fontSize: 13,
                        height: 1.2,
                        shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(style.icon, size: 12, color: style.color),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            channelCategoryLabel(widget.channel.category),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.labelSmall.copyWith(
                              color: style.color,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        _AccessPill(
                          channel: widget.channel,
                          locked: widget.locked,
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playIcon({required double size, bool gold = false}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gold ? AppTheme.premiumGradient : AppTheme.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: (gold ? AppTheme.gold : AppTheme.cyan).withValues(alpha: 0.45),
            blurRadius: 18,
          ),
        ],
      ),
      child: Icon(Icons.play_arrow_rounded, color: AppTheme.background, size: size * 0.55),
    );
  }

  Widget _buildGridCard() {
    final style = ChannelCategoryStyle.forCategory(widget.channel.category);

    return _PosterFrame(
      accent: _accent,
      locked: widget.locked,
      pressed: _pressed,
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ChannelThumbnail(
              url: imageUrlWithCacheEpoch(widget.channel.imageUrl, widget.imageCacheEpoch),
              channelId: widget.channel.id,
              borderRadius: 18,
            ),
            _ThumbnailOverlay(intensity: 0.7),
            // Category accent strip
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: style.gradient),
                ),
              ),
            ),
            if (widget.channel.live) _LiveBadge(pulse: _livePulse),
            const Positioned(top: 10, right: 10, child: _QualityBadge()),
            if (widget.locked) _LockBadge(full: true),
            if (_pressed && !widget.locked) const _PlayOverlay(),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CategoryChip(category: widget.channel.category),
                  const SizedBox(height: 6),
                  Text(
                    widget.channel.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.titleMedium.copyWith(
                      fontSize: 14,
                      height: 1.2,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  _AccessPill(channel: widget.channel, locked: widget.locked),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gradient border frame with depth shadow.
class _PosterFrame extends StatelessWidget {
  const _PosterFrame({
    required this.accent,
    required this.locked,
    required this.pressed,
    required this.child,
  });

  final Color accent;
  final bool locked;
  final bool pressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: pressed ? 0.35 : 0.18),
            blurRadius: pressed ? 24 : 16,
            offset: Offset(0, pressed ? 10 : 6),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: locked
                ? [AppTheme.gold.withValues(alpha: 0.5), AppTheme.orange.withValues(alpha: 0.3)]
                : [accent.withValues(alpha: 0.55), accent.withValues(alpha: 0.15)],
          ),
        ),
        padding: const EdgeInsets.all(1.5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16.5),
          child: child,
        ),
      ),
    );
  }
}

class _ChannelThumbnail extends StatelessWidget {
  const _ChannelThumbnail({
    required this.url,
    required this.channelId,
    required this.borderRadius,
    this.hd = false,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String url;
  final int channelId;
  final double borderRadius;
  final bool hd;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius - 1.5),
      child: Image.network(
        url,
        fit: fit,
        alignment: alignment,
        filterQuality: hd ? FilterQuality.high : FilterQuality.medium,
        width: double.infinity,
        height: double.infinity,
        key: ValueKey('$channelId|$url'),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return _ShimmerPlaceholder(progress: progress);
        },
        errorBuilder: (_, __, ___) => Container(
          color: AppTheme.surface,
          alignment: Alignment.center,
          child: Icon(
            Icons.live_tv_rounded,
            color: AppTheme.textMuted.withValues(alpha: 0.4),
            size: 36,
          ),
        ),
      ),
    );
  }
}

class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder({required this.progress});

  final ImageChunkEvent progress;

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.progress.expectedTotalBytes != null
        ? widget.progress.cumulativeBytesLoaded / widget.progress.expectedTotalBytes!
        : null;

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + _shimmer.value * 2, 0),
              end: Alignment(0 + _shimmer.value * 2, 0),
              colors: [
                AppTheme.surface,
                AppTheme.surfaceElevated,
                AppTheme.surface,
              ],
            ),
          ),
          child: value != null
              ? Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: value,
                      color: AppTheme.cyan.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _ThumbnailOverlay extends StatelessWidget {
  const _ThumbnailOverlay({required this.intensity});

  final double intensity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color.fromRGBO(1, 2, 8, intensity),
            Color.fromRGBO(1, 2, 8, intensity * 0.35),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.pulse});

  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, __) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.live.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.live.withValues(alpha: 0.35 + pulse.value * 0.25),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.6 + pulse.value * 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'LIVE',
                      style: AppTheme.labelSmall.copyWith(
                        color: Colors.white,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({this.gold = false});

  final bool gold;

  @override
  Widget build(BuildContext context) {
    final color = gold ? AppTheme.gold : AppTheme.cyan;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Text(
            'HD',
            style: AppTheme.labelSmall.copyWith(
              color: color,
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumCornerBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: AppTheme.premiumGradient,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: AppTheme.gold.withValues(alpha: 0.35), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.diamond_rounded, size: 11, color: AppTheme.background),
          const SizedBox(width: 4),
          Text(
            'PRO',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.background,
              fontSize: 9,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge({this.full = false});

  final bool full;

  @override
  Widget build(BuildContext context) {
    if (full) {
      return Container(
        color: Colors.black.withValues(alpha: 0.42),
        child: Center(child: _lockIcon(size: 48)),
      );
    }
    return Positioned(
      bottom: 8,
      right: 8,
      child: _lockIcon(size: 32),
    );
  }

  Widget _lockIcon({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.65),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.65), width: 1.5),
        boxShadow: [
          BoxShadow(color: AppTheme.gold.withValues(alpha: 0.25), blurRadius: 12),
        ],
      ),
      child: Icon(Icons.lock_rounded, color: AppTheme.gold, size: size * 0.48),
    );
  }
}

class _PlayOverlay extends StatelessWidget {
  const _PlayOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.25),
      alignment: Alignment.center,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppTheme.primaryGradient,
          boxShadow: [
            BoxShadow(
              color: AppTheme.cyan.withValues(alpha: 0.45),
              blurRadius: 20,
            ),
          ],
        ),
        child: const Icon(Icons.play_arrow_rounded, color: AppTheme.background, size: 30),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, this.compact = false});

  final String category;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = ChannelCategoryStyle.forCategory(category);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: style.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: compact ? 10 : 11, color: style.color),
          SizedBox(width: compact ? 4 : 5),
          Text(
            channelCategoryLabel(category),
            style: AppTheme.labelSmall.copyWith(
              color: style.color,
              fontSize: compact ? 8 : 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessPill extends StatelessWidget {
  const _AccessPill({
    required this.channel,
    required this.locked,
    this.compact = false,
  });

  final Channel channel;
  final bool locked;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = channelAccessLabel(channelPremium: channel.premium, locked: locked);
    final Color color;
    if (!channel.premium) {
      color = AppTheme.emerald;
    } else if (locked) {
      color = AppTheme.danger;
    } else {
      color = AppTheme.gold;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(
          color: color,
          fontSize: compact ? 8 : 9,
        ),
      ),
    );
  }
}
