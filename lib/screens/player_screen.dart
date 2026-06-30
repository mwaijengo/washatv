import 'dart:async';

import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../player/wash_channel_playback.dart';
import '../services/native_android_player.dart';
import '../services/remote_config_service.dart';
import '../services/storage_service.dart';
import '../utils/player_orientation.dart';
import 'fullscreen_video_page.dart';

typedef PlayerBackHandler = bool Function();

/// Opens channel playback in landscape fullscreen immediately; back restores portrait home.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channel,
    required this.onBack,
    required this.channels,
    this.onBackHandlerChanged,
    this.onFullscreenChanged,
  });

  final Channel? channel;
  final VoidCallback onBack;
  final List<Channel> channels;
  final ValueChanged<PlayerBackHandler?>? onBackHandlerChanged;
  final ValueChanged<bool>? onFullscreenChanged;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _storage = StorageService();

  bool _fullscreenRouteOpen = false;
  bool _playbackShellActive = false;
  bool _dataSaverEnabled = true;
  final String _preferredLanguage = 'sw';
  int _openGeneration = 0;

  Channel get _current => widget.channel ?? widget.channels.first;

  @override
  void initState() {
    super.initState();
    widget.onBackHandlerChanged?.call(_handlePlayerBack);
    unawaited(_bootstrapPlayback());
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

  Future<void> _loadSettings() async {
    final enabled = await _storage.getDataSaverEnabled();
    if (mounted) setState(() => _dataSaverEnabled = enabled);
  }

  Future<void> _bootstrapPlayback() async {
    await _loadSettings();
    if (!mounted) return;
    unawaited(_openLandscapePlayback());
  }

  String get _defaultQuality => _dataSaverEnabled ? '360p' : 'auto';

  Map<String, String> _headersFor(Channel c) {
    final data = channelDataFor(c);
    return mergedPlaybackHeaders(url: c.streamUrl, channelData: data);
  }

  Future<void> _restorePortraitShell() async {
    if (!_playbackShellActive) return;
    _playbackShellActive = false;
    widget.onFullscreenChanged?.call(false);
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

  Future<void> _openLandscapePlayback() async {
    if (!mounted) return;
    final c = _current;
    if (!c.hasStream) {
      widget.onBack();
      return;
    }

    final generation = ++_openGeneration;

    final data = channelDataFor(c);
    final ck = extractClearKeyPayload(data);
    final headers = _headersFor(c);
    final drm = normalizedDrmType(data, ck, c.streamUrl);
    final token = extractPlaybackToken(data);

    try {
      if (!_sessionAlive(generation)) return;

      if (NativeAndroidPlayer.supported) {
        // Native activity owns landscape + immersive UI — rotating Flutter first
        // causes EGL churn and slow startup on Huawei / HiSilicon devices.
        widget.onFullscreenChanged?.call(true);
        _playbackShellActive = true;
        await NativeAndroidPlayer.open(
          url: c.streamUrl,
          channelId: c.id,
          channelName: c.name,
          licenseUrl: '',
          token: token,
          drmType: drm,
          clearKeyHex: ck,
          headers: headers.isEmpty ? null : headers,
          audioLanguage: _preferredLanguage,
          playerPolicy: RemoteConfigService.playerConfig,
        );
        return;
      }

      widget.onFullscreenChanged?.call(true);
      await PlayerOrientation.enterFullscreenPlayer();
      if (!_sessionAlive(generation)) {
        await _restorePortraitShell();
        return;
      }
      _playbackShellActive = true;

      if (!_sessionAlive(generation)) return;

      if (!mounted) return;
      setState(() => _fullscreenRouteOpen = true);

      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: true,
          fullscreenDialog: true,
          pageBuilder: (_, __, ___) => FullscreenVideoPage(
            videoUrl: c.streamUrl,
            channelName: c.name,
            channelId: c.id,
            httpHeaders: headers,
            drmType: drm,
            clearKeyRaw: ck,
            playbackToken: token,
            playbackMode: resolveFlutterPlaybackMode(c.streamUrl, drm: c.drm),
            audioLanguage: _preferredLanguage,
            defaultQuality: _defaultQuality,
          ),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
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
      child: const ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFEF4444)),
          ),
        ),
      ),
    );
  }
}
