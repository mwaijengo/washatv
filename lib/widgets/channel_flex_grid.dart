import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../theme/app_theme.dart';
import 'channel_card.dart';

/// Responsive 2-column flex grid for channel lists (premium sections, etc.).
class ChannelFlexGrid extends StatelessWidget {
  const ChannelFlexGrid({
    super.key,
    required this.channels,
    required this.onTap,
    required this.lockedFor,
    this.imageCacheEpoch = 0,
    this.startIndex = 0,
    this.variant = ChannelCardVariant.premium,
    this.crossAxisCount = 2,
    this.crossAxisSpacing = 14,
    this.mainAxisSpacing = 14,
    this.childAspectRatio = 0.78,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  final List<Channel> channels;
  final ValueChanged<Channel> onTap;
  final bool Function(Channel channel) lockedFor;
  final int imageCacheEpoch;
  final int startIndex;
  final ChannelCardVariant variant;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - crossAxisSpacing * (crossAxisCount - 1)) /
              crossAxisCount;

          return Wrap(
            spacing: crossAxisSpacing,
            runSpacing: mainAxisSpacing,
            children: [
              for (var i = 0; i < channels.length; i++)
                SizedBox(
                  width: itemWidth,
                  child: ChannelCard(
                    channel: channels[i],
                    variant: variant,
                    locked: lockedFor(channels[i]),
                    imageCacheEpoch: imageCacheEpoch,
                    index: startIndex + i,
                    onTap: () => onTap(channels[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Sliver version for [CustomScrollView].
class ChannelFlexGridSliver extends StatelessWidget {
  const ChannelFlexGridSliver({
    super.key,
    required this.channels,
    required this.onTap,
    required this.lockedFor,
    this.imageCacheEpoch = 0,
    this.startIndex = 0,
    this.crossAxisCount = 2,
    this.crossAxisSpacing = 14,
    this.mainAxisSpacing = 14,
    this.childAspectRatio = 0.78,
    this.premiumSection = false,
    this.variant = ChannelCardVariant.premium,
  });

  final List<Channel> channels;
  final ValueChanged<Channel> onTap;
  final bool Function(Channel channel) lockedFor;
  final int imageCacheEpoch;
  final int startIndex;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
  final bool premiumSection;
  final ChannelCardVariant variant;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final grid = SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: mainAxisSpacing,
          childAspectRatio: childAspectRatio,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final c = channels[i];
            return ChannelCard(
              channel: c,
              variant: variant,
              locked: lockedFor(c),
              imageCacheEpoch: imageCacheEpoch,
              index: startIndex + i,
              onTap: () => onTap(c),
            );
          },
          childCount: channels.length,
        ),
      );

    if (!premiumSection) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        sliver: grid,
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      sliver: SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.gold.withValues(alpha: 0.07),
                AppTheme.orange.withValues(alpha: 0.02),
              ],
            ),
            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.14)),
          ),
          child: ChannelFlexGrid(
            channels: channels,
            onTap: onTap,
            lockedFor: lockedFor,
            imageCacheEpoch: imageCacheEpoch,
            startIndex: startIndex,
            variant: ChannelCardVariant.premium,
          ),
        ),
      ),
    );
  }
}
