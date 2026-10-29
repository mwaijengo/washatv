import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Animated aurora mesh background for the entire app shell.
class CinematicBackground extends StatelessWidget {
  const CinematicBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: AppTheme.background),
            _AuroraLayer(),
            _GridOverlay(),
          ],
        ),
      ),
    );
  }
}

class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.025,
      child: CustomPaint(painter: _GridPainter()),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.cyan
      ..strokeWidth = 0.5;
    const spacing = 40.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AuroraLayer extends StatelessWidget {
  const _AuroraLayer();

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
      child: Stack(
        children: const [
          _AuroraOrb(
            size: 380,
            left: -60,
            top: 80,
            colors: [Color(0x5500D4FF), Color(0x157B61FF)],
            duration: Duration(seconds: 18),
          ),
          _AuroraOrb(
            size: 320,
            left: 200,
            top: 40,
            colors: [Color(0x457B61FF), Color(0x1000E5C7)],
            duration: Duration(seconds: 22),
            reverse: true,
          ),
          _AuroraOrb(
            size: 280,
            left: -20,
            top: 480,
            colors: [Color(0x3800E5C7), Color(0x0800D4FF)],
            duration: Duration(seconds: 26),
          ),
          _AuroraOrb(
            size: 300,
            left: 160,
            top: 600,
            colors: [Color(0x30FF6B35), Color(0x08FFD700)],
            duration: Duration(seconds: 20),
            reverse: true,
          ),
        ],
      ),
    );
  }
}

class _AuroraOrb extends StatefulWidget {
  const _AuroraOrb({
    required this.size,
    required this.left,
    required this.top,
    required this.colors,
    required this.duration,
    this.reverse = false,
  });

  final double size;
  final double left;
  final double top;
  final List<Color> colors;
  final Duration duration;
  final bool reverse;

  @override
  State<_AuroraOrb> createState() => _AuroraOrbState();
}

class _AuroraOrbState extends State<_AuroraOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: widget.reverse);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left,
      top: widget.top,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final angle = t * 2 * math.pi;
          return Transform.translate(
            offset: Offset(math.sin(angle) * 35, math.cos(angle * 0.7) * 45),
            child: Transform.scale(
              scale: 0.92 + math.sin(t * math.pi) * 0.08,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.15, -0.2),
                    colors: widget.colors,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
