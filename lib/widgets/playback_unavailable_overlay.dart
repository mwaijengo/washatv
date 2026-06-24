import 'package:flutter/material.dart';

/// Shown when playback fails — retry/loading only, never URLs or technical details.
class PlaybackUnavailableOverlay extends StatelessWidget {
  const PlaybackUnavailableOverlay({
    super.key,
    this.onRetry,
    this.onClose,
    this.isRetrying = false,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRetrying)
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFEF4444)),
              )
            else ...[
              Material(
                color: const Color(0xFFEF4444),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onRetry,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(Icons.refresh_rounded, color: Colors.white, size: 28),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: onRetry,
                child: const Text(
                  'Jaribu tena',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ],
            if (onClose != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onClose,
                child: Text(
                  'Rudi nyuma',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
