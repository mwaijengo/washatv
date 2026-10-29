import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/channel.dart';
import '../theme/app_theme.dart';
import 'channel_card.dart';

/// Horizontal Netflix-style channel row with snap scrolling.
class ChannelRow extends StatelessWidget {
  const ChannelRow({
    super.key,
    required this.channels,
    required this.onTap,
    required this.lockedFor,
    this.imageCacheEpoch = 0,
    this.startIndex = 0,
    this.height = 236,
  });

  final List<Channel> channels;
  final ValueChanged<Channel> onTap;
  final bool Function(Channel channel) lockedFor;
  final int imageCacheEpoch;
  final int startIndex;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          'Hakuna channel hapa kwa sasa.',
          style: AppTheme.bodyMedium.copyWith(fontSize: 13),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final channel = channels[i];
          return ChannelCard(
            channel: channel,
            variant: ChannelCardVariant.poster,
            locked: lockedFor(channel),
            imageCacheEpoch: imageCacheEpoch,
            index: startIndex + i,
            onTap: () => onTap(channel),
          );
        },
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideX(begin: 0.03, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }
}
