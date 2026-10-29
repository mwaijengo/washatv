import 'package:flutter/material.dart';

import '../models/hero_slide.dart';
import '../theme/app_theme.dart';
import '../utils/cache_bust_image_url.dart';

/// Netflix-style hero carousel with parallax, depth, swipe, and auto-play progress.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    super.key,
    required this.slides,
    required this.currentIndex,
    required this.onIndexChanged,
    this.imageCacheEpoch = 0,
    this.autoPlayDuration = const Duration(seconds: 5),
  });

  final List<HeroSlide> slides;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final int imageCacheEpoch;
  final Duration autoPlayDuration;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _progressController;
  late AnimationController _kenBurnsController;
  double _currentPage = 0;

  @override
  void initState() {
    super.initState();
    final initial = _clampIndex(widget.currentIndex);
    _currentPage = initial.toDouble();
    _pageController = PageController(
      viewportFraction: 0.9,
      initialPage: initial,
    );
    _progressController = AnimationController(vsync: this, duration: widget.autoPlayDuration);
    _kenBurnsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _pageController.addListener(_onPageScroll);
    _restartProgress();
  }

  @override
  void didUpdateWidget(HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoPlayDuration != oldWidget.autoPlayDuration) {
      _progressController.duration = widget.autoPlayDuration;
    }
    if (widget.currentIndex != oldWidget.currentIndex &&
        widget.currentIndex != _pageController.page?.round()) {
      _animateToPage(widget.currentIndex);
    } else if (widget.currentIndex != oldWidget.currentIndex) {
      _restartProgress();
    }
    if (widget.slides.length != oldWidget.slides.length) {
      final next = _clampIndex(widget.currentIndex);
      if (next != _pageController.page?.round()) {
        _animateToPage(next);
      }
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _progressController.dispose();
    _kenBurnsController.dispose();
    super.dispose();
  }

  int _clampIndex(int i) {
    if (widget.slides.isEmpty) return 0;
    return i.clamp(0, widget.slides.length - 1);
  }

  void _onPageScroll() {
    final page = _pageController.page;
    if (page == null) return;
    setState(() => _currentPage = page);
  }

  void _restartProgress() {
    if (widget.slides.length <= 1) return;
    _progressController.forward(from: 0);
  }

  Future<void> _animateToPage(int index) async {
    final target = _clampIndex(index);
    _restartProgress();
    if (!_pageController.hasClients) return;
    await _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    if (index != widget.currentIndex) {
      widget.onIndexChanged(index);
    }
    _restartProgress();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) return const SizedBox.shrink();

    final count = widget.slides.length;
    final active = _clampIndex(widget.currentIndex);

    return Column(
      children: [
        SizedBox(
          height: 400,
          child: PageView.builder(
            controller: _pageController,
            itemCount: count,
            onPageChanged: _onPageChanged,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final delta = (_currentPage - index).abs().clamp(0.0, 1.0);
              final scale = 1.0 - (delta * 0.04);
              final opacity = 1.0 - (delta * 0.12);
              final slide = widget.slides[index];
              final isActive = index == active;

              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity.clamp(0.88, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _CarouselCard(
                      slide: slide,
                      imageCacheEpoch: widget.imageCacheEpoch,
                      isActive: isActive,
                      kenBurns: _kenBurnsController,
                      progress: isActive ? _progressController : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _CarouselIndicators(
          count: count,
          current: active,
          progress: _progressController,
          onTap: (i) {
            widget.onIndexChanged(i);
            _animateToPage(i);
          },
        ),
      ],
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({
    required this.slide,
    required this.imageCacheEpoch,
    required this.isActive,
    required this.kenBurns,
    this.progress,
  });

  final HeroSlide slide;
  final int imageCacheEpoch;
  final bool isActive;
  final AnimationController kenBurns;
  final AnimationController? progress;

  @override
  Widget build(BuildContext context) {
    final imageUrl = imageUrlWithCacheEpoch(slide.imageUrl, imageCacheEpoch);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Ken Burns zoom on active slide
          AnimatedBuilder(
            animation: kenBurns,
            builder: (_, child) {
              final scale = isActive ? 1.0 + (kenBurns.value * 0.025) : 1.0;
              return Transform.scale(scale: scale, child: child);
            },
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              width: double.infinity,
              height: double.infinity,
              alignment: Alignment.center,
              key: ValueKey('${slide.id}|$imageCacheEpoch|$imageUrl'),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: AppTheme.surface,
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.cyan.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: AppTheme.surface,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined, size: 40, color: AppTheme.textMuted),
              ),
            ),
          ),
          // Bottom text scrim only — keeps the image crisp in the upper area.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 168,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppTheme.background.withValues(alpha: 0.94),
                    AppTheme.background.withValues(alpha: 0.42),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.62, 1.0],
                ),
              ),
            ),
          ),
          // Auto-play progress bar
          if (progress != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: progress!,
                builder: (_, __) => LinearProgressIndicator(
                  value: progress!.value,
                  minHeight: 3,
                  backgroundColor: AppTheme.white07,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.cyan),
                ),
              ),
            ),
          // Glass edge glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isActive
                      ? AppTheme.cyan.withValues(alpha: 0.28)
                      : AppTheme.white07,
                  width: isActive ? 1.25 : 1,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppTheme.cyan.withValues(alpha: 0.1),
                          blurRadius: 16,
                          spreadRadius: -6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          // Content
          Positioned(
            left: 22,
            right: 22,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (slide.premium) ...[
                  Row(
                    children: [
                      _Badge(
                        label: 'PREMIUM',
                        icon: Icons.diamond_rounded,
                        color: AppTheme.gold,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutCubic,
                  child: Text(
                    slide.title,
                    key: ValueKey(slide.title),
                    style: AppTheme.displayLarge.copyWith(
                      fontSize: 30,
                      height: 1.1,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    slide.subtitle,
                    key: ValueKey(slide.subtitle),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyMedium.copyWith(
                      fontSize: 14,
                      color: AppTheme.textPrimary.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom accent line
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: isActive ? AppTheme.primaryGradient : null,
                color: isActive ? null : AppTheme.white07,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: color, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _CarouselIndicators extends StatelessWidget {
  const _CarouselIndicators({
    required this.count,
    required this.current,
    required this.progress,
    required this.onTap,
  });

  final int count;
  final int current;
  final AnimationController progress;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Slide counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.white07),
            ),
            child: Text(
              '${current + 1}/$count',
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.cyan,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Animated dots
          Expanded(
            child: Row(
              children: List.generate(count, (i) {
                final active = i == current;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onTap(i),
                    child: Container(
                      margin: EdgeInsets.only(right: i < count - 1 ? 6 : 0),
                      height: 4,
                      child: active
                          ? AnimatedBuilder(
                              animation: progress,
                              builder: (_, __) => ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Container(color: AppTheme.white10),
                                    FractionallySizedBox(
                                      widthFactor: progress.value.clamp(0.01, 1.0),
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: AppTheme.primaryGradient,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: AppTheme.white14,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
