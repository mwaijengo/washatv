import 'package:flutter/material.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.playing,
    required this.progress,
    required this.onPlay,
    required this.onToggleFullscreen,
    required this.onSeek,
  });

  final bool playing;
  final double progress;
  final VoidCallback onPlay;
  final VoidCallback onToggleFullscreen;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
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
                  onPressed: onPlay,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                const Text('12:34', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                const Text('/', style: TextStyle(color: Color(0xFF6B7280))),
                const SizedBox(width: 8),
                const Text('45:20', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                const Spacer(),
                IconButton(onPressed: () {}, icon: const Icon(Icons.closed_caption, size: 20)),
                IconButton(onPressed: () {}, icon: const Icon(Icons.settings, size: 20)),
                IconButton(onPressed: onToggleFullscreen, icon: const Icon(Icons.fullscreen, size: 20)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
