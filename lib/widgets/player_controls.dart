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
    this.channelName,
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
  final String? channelName;

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
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onUserInteraction,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xF0010208), Color(0x99010208), Colors.transparent],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (channelName != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.live,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'LIVE',
                              style: AppTheme.labelSmall.copyWith(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              channelName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.titleMedium.copyWith(fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _SeekBar(
                    progress: progress,
                    onSeek: onSeek,
                    onUserInteraction: onUserInteraction,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _ControlButton(
                        icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        onTap: () {
                          onUserInteraction?.call();
                          onPlay();
                        },
                        primary: true,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        positionLabel,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        ' / $durationLabel',
                        style: AppTheme.labelSmall.copyWith(fontSize: 12),
                      ),
                      const Spacer(),
                      if (onOpenLanguage != null)
                        _ControlButton(
                          icon: Icons.language_rounded,
                          onTap: () {
                            onUserInteraction?.call();
                            onOpenLanguage!();
                          },
                        ),
                      if (onOpenSettings != null)
                        _ControlButton(
                          icon: Icons.tune_rounded,
                          onTap: () {
                            onUserInteraction?.call();
                            onOpenSettings!();
                          },
                        ),
                      if (onToggleFullscreen != null)
                        _ControlButton(
                          icon: isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                          onTap: () {
                            onUserInteraction?.call();
                            onToggleFullscreen!();
                          },
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

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.progress,
    required this.onSeek,
    this.onUserInteraction,
  });

  final double progress;
  final ValueChanged<double> onSeek;
  final VoidCallback? onUserInteraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (d) {
            onUserInteraction?.call();
            onSeek((d.localPosition.dx / constraints.maxWidth).clamp(0, 1));
          },
          onHorizontalDragUpdate: (d) {
            onUserInteraction?.call();
            onSeek((d.localPosition.dx / constraints.maxWidth).clamp(0, 1));
          },
          child: SizedBox(
            height: 20,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.white10,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0, 1),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.cyan.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: (progress.clamp(0, 1) * constraints.maxWidth) - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.cyan,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.cyan.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: primary ? 44 : 40,
          height: primary ? 44 : 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: primary ? AppTheme.primaryGradient : null,
            color: primary ? null : AppTheme.white07,
            border: primary ? null : Border.all(color: AppTheme.white10),
          ),
          child: Icon(
            icon,
            size: primary ? 24 : 20,
            color: primary ? AppTheme.background : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}
