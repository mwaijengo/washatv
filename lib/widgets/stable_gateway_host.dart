import 'package:flutter/material.dart';

/// Locks gateway WebView to a landscape-sized canvas so HiSilicon never resizes the codec surface.
class StableGatewayHost extends StatelessWidget {
  const StableGatewayHost({
    super.key,
    required this.child,
    this.canvasSize,
  });

  final Widget child;
  final Size? canvasSize;

  static Size landscapeCanvasFor(BoxConstraints constraints) {
    final long = constraints.maxWidth > constraints.maxHeight
        ? constraints.maxWidth
        : constraints.maxHeight;
    final base = long > 320 ? long : 1280.0;
    return Size(base, base * 9 / 16);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // When canvas matches the viewport, render 1:1 — no FittedBox transform
        // (transforms break hardware video surfaces on HiSilicon WebViews).
        if (canvasSize != null) {
          return ClipRect(
            child: ColoredBox(
              color: Colors.black,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: child,
              ),
            ),
          );
        }
        final canvas = landscapeCanvasFor(constraints);
        return ClipRect(
          child: ColoredBox(
            color: Colors.black,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: SizedBox(
                width: canvas.width,
                height: canvas.height,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
