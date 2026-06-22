import 'package:flutter/material.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.playing,
    required this.progress,
    required this.onPlay,
    required this.onToggleFullscreen,
    required this.onSeek,
    this.positionLabel = '0:00',
    this.durationLabel = 'LIVE',
    this.isFullscreen = false,
    this.visible = true,
    this.onUserInteraction,
    this.dataSaverEnabled = true,
    this.onToggleDataSaver,
  });

  final bool playing;
  final double progress;
  final VoidCallback onPlay;
  final VoidCallback onToggleFullscreen;
  final ValueChanged<double> onSeek;
  final String positionLabel;
  final String durationLabel;
  final bool isFullscreen;
  final bool visible;
  final VoidCallback? onUserInteraction;
  final bool dataSaverEnabled;
  final VoidCallback? onToggleDataSaver;

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
                        valueColor: const AlwaysStoppedAnimation(Color(0xFFEF4444)),
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
                      if (onToggleDataSaver != null)
                        TextButton.icon(
                          onPressed: () {
                            onUserInteraction?.call();
                            onToggleDataSaver!();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: dataSaverEnabled ? const Color(0xFF34D399) : const Color(0xFF9CA3AF),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: Icon(
                            dataSaverEnabled ? Icons.savings_rounded : Icons.savings_outlined,
                            size: 18,
                          ),
                          label: Text(
                            dataSaverEnabled ? 'Okoa bando' : 'HD',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: dataSaverEnabled ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      IconButton(
                        onPressed: () {
                          onUserInteraction?.call();
                          onToggleFullscreen();
                        },
                        icon: Icon(isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 22),
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
