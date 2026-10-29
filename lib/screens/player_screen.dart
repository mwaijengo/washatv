import 'dart:async';

import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../player/wash_channel_playback.dart';
import '../services/native_android_player.dart';
import '../services/player_playback_service.dart';
import '../theme/app_theme.dart';
import '../utils/player_orientation.dart';

typedef PlayerBackHandler = bool Function();

/// Opens channel playback in landscape fullscreen immediately; back restores portrait home.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channel,
    required this.onBack,
    required this.channels,
    required this.resolveStream,
    this.onBackHandlerChanged,
    this.onFullscreenChanged,
  });

  final Channel? channel;
  final VoidCallback onBack;
  final List<Channel> channels;
  /// Fetches the playable stream from the server; returns null when access was denied (caller shows why).
  final Future<Channel?> Function(Channel channel) resolveStream;
  final ValueChanged<PlayerBackHandler?>? onBackHandlerChanged;
  final ValueChanged<bool>? onFullscreenChanged;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _fullscreenRouteOpen = false;
  bool _playbackShellActive = false;
  int _openGeneration = 0;

  Channel get _current => widget.channel ?? widget.channels.first;

  @override
  void initState() {
    super.initState();
    widget.onBackHandlerChanged?.call(_handlePlayerBack);
    // Defer until after first frame — onFullscreenChanged triggers parent setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrapPlayback());
    });
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel?.id == widget.channel?.id) return;
    unawaited(_restartPlaybackForNewChannel());
  }

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(null);
    _invalidatePlaybackSession();
    unawaited(_restorePortraitShell());
    super.dispose();
  }

  void _invalidatePlaybackSession() => _openGeneration++;

  Future<void> _bootstrapPlayback() async {
    if (!mounted) return;
    unawaited(_openLandscapePlayback());
  }

  Future<void> _restorePortraitShell() async {
    if (!_playbackShellActive) return;
    _playbackShellActive = false;
    _notifyFullscreenChanged(false);
    await PlayerOrientation.lockHomePortrait();
  }

  bool _sessionAlive(int generation) => mounted && generation == _openGeneration;

  bool _handlePlayerBack() {
    if (_fullscreenRouteOpen) {
      Navigator.of(context).maybePop();
      return true;
    }
    return false;
  }

  void _leaveBeforeFullscreen() {
    _invalidatePlaybackSession();
    unawaited(_restorePortraitShell());
    widget.onBack();
  }

  Future<void> _restartPlaybackForNewChannel() async {
    _invalidatePlaybackSession();
    if (_fullscreenRouteOpen && mounted) {
      Navigator.of(context).maybePop();
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
    if (!mounted) return;
    unawaited(_openLandscapePlayback());
  }

  void _notifyFullscreenChanged(bool value) {
    final cb = widget.onFullscreenChanged;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb(value);
    });
  }

  Future<void> _openLandscapePlayback() async {
    if (!mounted) return;
    final listed = _current;
    if (!listed.hasStream) {
      widget.onBack();
      return;
    }

    final generation = ++_openGeneration;
    final c = await widget.resolveStream(listed);
    if (!_sessionAlive(generation)) return;
    if (c == null || c.streamUrl.isEmpty) {
      widget.onBack();
      return;
    }
    final channelData = channelDataFor(c);

    try {
      if (!_sessionAlive(generation)) return;

      if (NativeAndroidPlayer.supported) {
        // Native activity owns landscape + immersive UI — rotating Flutter first
        // causes EGL churn and slow startup on Huawei / HiSilicon devices.
        _notifyFullscreenChanged(true);
        _playbackShellActive = true;
      } else {
        _notifyFullscreenChanged(true);
        await PlayerOrientation.enterFullscreenPlayer();
        if (!_sessionAlive(generation)) {
          await _restorePortraitShell();
          return;
        }
        _playbackShellActive = true;
        if (mounted) setState(() => _fullscreenRouteOpen = true);
      }

      if (!_sessionAlive(generation) || !mounted) return;

      await PlayerPlaybackService.open(
        context: context,
        url: c.streamUrl,
        channelId: c.id,
        channelName: c.name,
        channelData: channelData,
        extractClearKey: clearKeyPayloadFromData,
        normalizeDrm: normalizedDrmType,
        extractToken: playbackTokenFromData,
        extractHeaders: (data) => extractPlaybackHeaders(data, c.streamUrl),
        extractAudioLanguage: playbackAudioLanguageFromData,
      );
    } finally {
      await _restorePortraitShell();
      if (mounted && _fullscreenRouteOpen) {
        setState(() => _fullscreenRouteOpen = false);
      }
      if (_sessionAlive(generation)) {
        widget.onBack();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.isEmpty) {
      return const Center(child: Text('Hakuna channel kwa sasa'));
    }

    return PopScope(
      canPop: !_fullscreenRouteOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_fullscreenRouteOpen) {
          Navigator.of(context).maybePop();
        } else {
          _leaveBeforeFullscreen();
        }
      },
      child: ColoredBox(
        color: AppTheme.background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.cyan.withValues(alpha: 0.3),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.background,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _current.name,
                style: AppTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Inafungua player...',
                style: AppTheme.bodyMedium.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
