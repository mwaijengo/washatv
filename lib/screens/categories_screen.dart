import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../constants/app_channel_categories.dart';
import '../models/channel.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/channel_category_style.dart';
import '../widgets/glass_panel.dart';
import '../widgets/section_header.dart';
import '../widgets/washa_app_bar.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.premium,
    required this.onOpenPlayer,
    required this.onOpenSubscription,
    required this.channels,
    this.channelImageCacheEpoch = 0,
  });

  final bool premium;
  final ValueChanged<Channel> onOpenPlayer;
  final VoidCallback onOpenSubscription;
  final List<Channel> channels;
  final int channelImageCacheEpoch;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String? selected;
  String query = '';
  String selectedCategory = 'All';

  static List<String> get categories =>
      List<String>.from(kAppChannelCategories);

  @override
  Widget build(BuildContext context) {
    bool matchesQuery(String value) =>
        query.trim().isEmpty ||
        value.toLowerCase().contains(query.trim().toLowerCase());

    if (selected == null) {
      final visibleCategories = categories.where((c) {
        final byQuery = matchesQuery(c);
        final byFilter = selectedCategory == 'All' || selectedCategory == c;
        return byQuery && byFilter;
      }).toList();

      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(child: WashaAppBar(showAvatar: false)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Aina za Channel',
                subtitle: 'Chagua kategoria unayopenda',
                icon: Icons.grid_view_rounded,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(child: _searchAndFilter()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.88,
              ),
              delegate: SliverChildBuilderDelegate((_, i) {
                final c = visibleCategories[i];
                final count = widget.channels
                    .where((e) => e.category == c)
                    .length;
                final style = ChannelCategoryStyle.forCategory(c);
                return _CategoryTile(
                  category: c,
                  count: count,
                  style: style,
                  index: i,
                  onTap: () => setState(() {
                    selected = c;
                    selectedCategory = c;
                  }),
                );
              }, childCount: visibleCategories.length),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
        ],
      );
    }

    final effectiveCategory = selectedCategory == 'All'
        ? selected
        : selectedCategory;
    final list = widget.channels.where((e) {
      final byCategory = e.category == effectiveCategory;
      final byQuery = matchesQuery(e.name) || matchesQuery(e.category);
      return byCategory && byQuery;
    }).toList();

    final style = ChannelCategoryStyle.forCategory(selected!);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    selected = null;
                    selectedCategory = 'All';
                    query = '';
                  }),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.white07,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.white10),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                ),
                Expanded(
                  child: SectionHeader(
                    title: categoryDisplayName(selected!),
                    subtitle: '${list.length} channeli',
                    icon: style.icon,
                    accentColor: style.color,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(child: _searchAndFilter()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 0.88,
            ),
            delegate: SliverChildBuilderDelegate((_, i) {
              final c = list[i];
              return ChannelCard(
                channel: c,
                variant: ChannelCardVariant.grid,
                index: i,
                imageCacheEpoch: widget.channelImageCacheEpoch,
                locked: c.premium && !widget.premium,
                onTap: () => c.premium && !widget.premium
                    ? widget.onOpenSubscription()
                    : widget.onOpenPlayer(c),
              );
            }, childCount: list.length),
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
      ],
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: InputBorder.none,
                hintText: 'Tafuta channel...',
                hintStyle: AppTheme.bodyMedium.copyWith(fontSize: 13),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppTheme.cyan.withValues(alpha: 0.7),
                  size: 22,
                ),
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
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTheme.cyan.withValues(alpha: 0.7),
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: InputBorder.none,
              ),
              items: <String>['All', ...categories]
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
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.count,
    required this.style,
    required this.index,
    required this.onTap,
  });

  final String category;
  final int count;
  final ChannelCategoryStyle style;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  style.color.withValues(alpha: 0.14),
                  AppTheme.surfaceElevated.withValues(alpha: 0.8),
                ],
              ),
              border: Border.all(color: style.color.withValues(alpha: 0.28)),
              boxShadow: [
                BoxShadow(
                  color: style.color.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(colors: style.gradient),
                              boxShadow: [
                                BoxShadow(
                                  color: style.color.withValues(alpha: 0.35),
                                  blurRadius: 14,
                                ),
                              ],
                            ),
                            child: Icon(
                              style.icon,
                              size: 26,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            categoryDisplayName(category),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.titleMedium.copyWith(
                              fontSize: 14,
                              height: 1.1,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count',
                            style: AppTheme.displayMedium.copyWith(
                              fontSize: 28,
                              height: 1,
                              color: style.color,
                            ),
                          ),
                          Text(
                            'channeli',
                            maxLines: 1,
                            style: AppTheme.labelSmall.copyWith(
                              fontSize: 10,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        )
        .animate(delay: (index * 70).ms)
        .fadeIn(duration: 450.ms)
        .scale(
          begin: const Offset(0.92, 0.92),
          duration: 450.ms,
          curve: Curves.easeOutBack,
        );
  }
}
