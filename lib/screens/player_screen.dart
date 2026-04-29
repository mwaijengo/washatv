import 'package:flutter/material.dart';

import '../app.dart';
import '../models/channel.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/player_controls.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channel,
    required this.premium,
    required this.onBack,
    required this.onOpenPlayer,
    required this.onOpenSubscription,
  });

  final Channel? channel;
  final bool premium;
  final VoidCallback onBack;
  final ValueChanged<Channel> onOpenPlayer;
  final VoidCallback onOpenSubscription;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool playing = true;
  bool fullscreen = false;
  double progress = 0.3;

  @override
  Widget build(BuildContext context) {
    final c = widget.channel ?? allChannels.first;
    final channels = widget.premium
        ? allChannels.where((e) => e.id != c.id).take(12).toList()
        : allChannels.where((e) => e.premium && e.id != c.id).take(12).toList();
    return Column(
      children: [
        Column(
          children: [
            AspectRatio(
              aspectRatio: fullscreen ? 1 : (16 / 9),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    c.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF0B1220),
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined, color: Color(0xFF6B7280), size: 34),
                    ),
                  ),
                  if (!playing)
                    Container(
                      color: const Color(0x66000000),
                      child: Center(
                        child: GestureDetector(
                          onTap: () => setState(() => playing = !playing),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: Color(0xF2FFFFFF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow, color: Color(0xFF111827), size: 34),
                          ),
                        ),
                      ),
                    ),
                  PlayerControls(
                    playing: playing,
                    progress: progress,
                    onPlay: () => setState(() => playing = !playing),
                    onToggleFullscreen: () => setState(() => fullscreen = !fullscreen),
                    onSeek: (v) => setState(() => progress = v),
                  ),
                ],
              ),
            ),
            Container(
              color: const Color(0xE6000000),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Unacheza: ',
                        style: const TextStyle(color: Color(0xFF9CA3AF)),
                        children: [TextSpan(text: c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.premium)
              GestureDetector(
                onTap: widget.onOpenSubscription,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xE6F59E0B), Color(0xEAF97316)])),
                  child: const Center(
                    child: Text('Fungua Channel zote kwa Punguzo Hadi Asilimia 70%', style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
            itemCount: channels.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (_, i) {
              final cc = channels[i];
              return ChannelCard(
                channel: cc,
                locked: cc.premium && !widget.premium,
                onTap: () => cc.premium && !widget.premium ? widget.onOpenSubscription() : widget.onOpenPlayer(cc),
              );
            },
          ),
        ),
      ],
    );
  }
}
