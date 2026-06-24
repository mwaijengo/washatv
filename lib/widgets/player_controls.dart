import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.playing,
    required this.progress,
    required this.onPlay,
    required this.onSeek,
    this.positionLabel = '0:00',
    this.durationLabel = 'LIVE',
    this.visible = true,
    this.onUserInteraction,
    this.onOpenLanguage,
    this.onOpenSettings,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  });

  final bool playing;
  final double progress;
  final VoidCallback onPlay;
  final ValueChanged<double> onSeek;
  final String positionLabel;
  final String durationLabel;
  final bool visible;
  final VoidCallback? onUserInteraction;
  final VoidCallback? onOpenLanguage;
  final VoidCallback? onOpenSettings;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onUserInteraction,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xE6000000), Colors.transparent],
                ),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTapDown: (d) {
                      onUserInteraction?.call();
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final local = box.globalToLocal(d.globalPosition);
                      onSeek((local.dx / box.size.width).clamp(0, 1));
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        value: progress,
                        backgroundColor: const Color(0x33FFFFFF),
                        valueColor: const AlwaysStoppedAnimation(AppTheme.danger),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          onUserInteraction?.call();
                          onPlay();
                        },
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      ),
                      Text(positionLabel, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      const Text('/', style: TextStyle(color: Color(0xFF6B7280))),
                      const SizedBox(width: 8),
                      Text(durationLabel, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                      const Spacer(),
                      if (onOpenLanguage != null)
                        IconButton(
                          tooltip: 'Lugha',
                          onPressed: () {
                            onUserInteraction?.call();
                            onOpenLanguage!();
                          },
                          icon: const Icon(Icons.public, size: 22),
                        ),
                      if (onOpenSettings != null)
                        IconButton(
                          tooltip: 'Mipangilio',
                          onPressed: () {
                            onUserInteraction?.call();
                            onOpenSettings!();
                          },
                          icon: const Icon(Icons.settings, size: 22),
                        ),
                      if (onToggleFullscreen != null)
                        IconButton(
                          tooltip: isFullscreen ? 'Toka skrini nzima' : 'Skrini nzima',
                          onPressed: () {
                            onUserInteraction?.call();
                            onToggleFullscreen!();
                          },
                          icon: Icon(
                            isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                            size: 22,
                          ),
                        ),
                    ],
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
