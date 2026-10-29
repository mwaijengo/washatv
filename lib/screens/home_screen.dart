import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../constants/app_channel_categories.dart';
import '../models/channel.dart';
import '../models/hero_slide.dart';
import '../models/app_user_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/channel_flex_grid.dart';
import '../widgets/channel_row.dart';
import '../widgets/glass_panel.dart';
import '../widgets/gradient_button.dart';
import '../widgets/hero_carousel.dart';
import '../widgets/section_header.dart';
import '../widgets/washa_app_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.carouselIndex,
    required this.onCarouselDot,
    required this.onOpenPlayer,
    required this.onOpenSubscription,
    required this.premium,
    required this.channels,
    required this.slides,
    this.carouselConfigVersion = 0,
    this.displayName,
    this.channelDisplay = ChannelDisplayStyle.scroll,
  });

  final int carouselIndex;
  final ValueChanged<int> onCarouselDot;
  final ValueChanged<Channel> onOpenPlayer;
  final VoidCallback onOpenSubscription;
  final bool premium;
  final List<Channel> channels;
  final List<HeroSlide> slides;
  final int carouselConfigVersion;
  final String? displayName;
  final ChannelDisplayStyle channelDisplay;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String query = '';
  String selectedCategory = 'All';

  List<String> get categories => ['All', ...kAppChannelCategories];

  @override
  Widget build(BuildContext context) {
    bool matches(Channel c) {
      final byCategory = selectedCategory == 'All' || c.category == selectedCategory;
      final q = query.trim().toLowerCase();
      final byQuery = q.isEmpty || c.name.toLowerCase().contains(q) || c.category.toLowerCase().contains(q);
      return byCategory && byQuery;
    }

    final free = widget.channels.where((e) => !e.premium && matches(e)).toList();
    final premiumChannels = widget.channels.where((e) => e.premium && matches(e)).toList();
    final slideCount = widget.slides.length;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: WashaAppBar(
              displayName: widget.displayName,
              premium: widget.premium,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
          sliver: SliverToBoxAdapter(
            child: slideCount > 0
                ? HeroCarousel(
                    slides: widget.slides,
                    currentIndex: widget.carouselIndex,
                    onIndexChanged: widget.onCarouselDot,
                    imageCacheEpoch: widget.carouselConfigVersion,
                  )
                : _emptyHero(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(child: _searchAndFilter()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              title: kSectionFreeChannelsTitle,
              subtitle: '${free.length} channeli za bure',
              icon: Icons.tv_rounded,
              accentColor: AppTheme.cyan,
            ),
          ),
        ),
        _freeChannelsSection(free),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          sliver: SliverToBoxAdapter(child: _premiumCta()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              title: kSectionPremiumChannelsTitle,
              subtitle: '${premiumChannels.length} channeli za premium',
              icon: Icons.diamond_rounded,
              accentColor: AppTheme.gold,
              animationDelay: 100.ms,
            ),
          ),
        ),
        _premiumChannelsSection(premiumChannels, free.length),
        const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
      ],
    );
  }

  Widget _emptyHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassPanel(
        radius: 24,
        glow: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: AppTheme.accentGradient,
                ),
                child: const Icon(Icons.slideshow_rounded, color: AppTheme.background),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Hakuna matangazo ya slides kwa sasa.',
                  style: AppTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchAndFilter() {
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: GlassPanel(
            radius: 14,
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              style: AppTheme.titleMedium.copyWith(fontSize: 14),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: InputBorder.none,
                hintText: 'Tafuta channel...',
                hintStyle: AppTheme.bodyMedium.copyWith(fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.cyan.withValues(alpha: 0.7), size: 22),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: GlassPanel(
            radius: 14,
            child: DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceElevated,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.cyan.withValues(alpha: 0.7)),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: InputBorder.none,
              ),
              items: categories
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c,
                      child: Text(
                        categoryDisplayName(c),
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.titleMedium.copyWith(fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => selectedCategory = v);
              },
            ),
          ),
        ),
      ],
    )
        .animate(delay: 150.ms)
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 400.ms);
  }

  Widget _premiumCta() {
    return GlassPanel(
      radius: 24,
      glow: true,
      glowColor: AppTheme.gold,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.gold.withValues(alpha: 0.08),
              AppTheme.orange.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppTheme.premiumGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.gold.withValues(alpha: 0.3),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Icon(Icons.diamond_rounded, color: AppTheme.background, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fungua Channel Zote', style: AppTheme.titleLarge.copyWith(fontSize: 17)),
                  const SizedBox(height: 3),
                  Text(
                    'Zaidi ya channel 30 za premium HD',
                    style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            GradientButton(
              label: 'Fungua',
              style: GradientButtonStyle.premium,
              onPressed: widget.onOpenSubscription,
              height: 40,
            ),
          ],
        ),
      ),
    )
        .animate(delay: 200.ms)
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.06, end: 0, duration: 500.ms);
  }

  void _onChannelTap(Channel c) {
    if (c.premium && !widget.premium) {
      widget.onOpenSubscription();
    } else {
      widget.onOpenPlayer(c);
    }
  }

  Widget _freeChannelsSection(List<Channel> free) {
    if (widget.channelDisplay == ChannelDisplayStyle.grid) {
      return ChannelFlexGridSliver(
        channels: free,
        startIndex: 0,
        imageCacheEpoch: widget.carouselConfigVersion,
        lockedFor: (c) => c.premium && !widget.premium,
        onTap: _onChannelTap,
        childAspectRatio: 0.78,
        variant: ChannelCardVariant.grid,
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.only(top: 8),
      sliver: SliverToBoxAdapter(
        child: ChannelRow(
          channels: free,
          startIndex: 0,
          height: 236,
          imageCacheEpoch: widget.carouselConfigVersion,
          lockedFor: (c) => c.premium && !widget.premium,
          onTap: _onChannelTap,
        ),
      ),
    );
  }

  Widget _premiumChannelsSection(List<Channel> premiumChannels, int startIndex) {
    return ChannelFlexGridSliver(
      channels: premiumChannels,
      startIndex: startIndex,
      imageCacheEpoch: widget.carouselConfigVersion,
      lockedFor: (c) => c.premium && !widget.premium,
      onTap: _onChannelTap,
      childAspectRatio: 0.78,
      premiumSection: true,
    );
  }
}
