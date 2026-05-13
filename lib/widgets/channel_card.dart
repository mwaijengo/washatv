import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../theme/app_theme.dart';
import '../utils/cache_bust_image_url.dart';
import 'glass_panel.dart';

class ChannelCard extends StatefulWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.locked,
    required this.onTap,
    /// From bootstrap `version` — thumbnails refresh after admin edits the same URL.
    this.imageCacheEpoch = 0,
  });

  final Channel channel;
  final bool locked;
  final VoidCallback onTap;
  final int imageCacheEpoch;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final thumbUrl = imageUrlWithCacheEpoch(widget.channel.imageUrl, widget.imageCacheEpoch);
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          transform: Matrix4.translationValues(0, hover ? -4 : 0, 0),
          child: GlassPanel(
            radius: 18,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 700),
                  scale: hover ? 1.08 : 1,
                  child: Image.network(
                    thumbUrl,
                    fit: BoxFit.cover,
                    key: ValueKey('${widget.channel.id}|$thumbUrl'),
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF111827),
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported_outlined, color: Color(0xFF6B7280), size: 26),
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Color(0x33000000), Colors.transparent],
                    ),
                  ),
                ),
                if (widget.channel.live)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.danger,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (widget.locked)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xBF000000),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.6)),
                      ),
                      child: const Icon(Icons.lock, color: AppTheme.amber, size: 18),
                    ),
                  ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0x80222636),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x33FFFFFF)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.channel.premium ? '⭐ Premium' : 'Bure',
                          style: TextStyle(
                            color: widget.channel.premium ? AppTheme.amber : AppTheme.emerald,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
