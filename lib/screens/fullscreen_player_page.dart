import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../player/web_media_control_js.dart';
import '../widgets/player_controls.dart';
import '../widgets/stable_player_surface.dart';

/// Landscape fullscreen player on a separate route so the portrait WebView is not
/// resized in-place (Huawei/HiSilicon kills the codec on PlatformView resize).
class FullscreenPlayerPage extends StatefulWidget {
  const FullscreenPlayerPage({
    super.key,
    required this.channelName,
    required this.useWebView,
    required this.playing,
    required this.progress,
    required this.positionLabel,
    required this.durationLabel,
    this.webController,
    this.videoController,
    required this.onPlayPause,
    required this.onSeek,
    this.onOpenLanguage,
    this.onOpenSettings,
  });

  final String channelName;
  final bool useWebView;
  final bool playing;
  final double progress;
  final String positionLabel;
  final String durationLabel;
  final WebViewController? webController;
  final VideoPlayerController? videoController;
  final Future<void> Function() onPlayPause;
  final Future<void> Function(double) onSeek;
  final Future<void> Function(BuildContext context)? onOpenLanguage;
  final Future<void> Function(BuildContext context)? onOpenSettings;

  @override
  State<FullscreenPlayerPage> createState() => _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState extends State<FullscreenPlayerPage> {
  bool _controlsVisible = true;
  bool _playing = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _playing = widget.playing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_nudgePlayback());
      _scheduleControlsHide();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _nudgePlayback() async {
    if (widget.useWebView) {
      final web = widget.webController;
      if (web == null) return;
      await web.runJavaScript(kWebMediaControlJs);
      await web.runJavaScript(kWebMediaEnsurePlayJs);
    } else {
      final video = widget.videoController;
      if (video != null && video.value.isInitialized && !video.value.isPlaying) {
        await video.play();
      }
    }
    if (mounted) setState(() => _playing = true);
  }

  void _scheduleControlsHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleControlsHide();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
      _hideTimer?.cancel();
    } else {
      _showControls();
    }
  }

  Future<void> _handlePlayPause() async {
    await widget.onPlayPause();
    if (!mounted) return;
    final video = widget.videoController;
    if (!widget.useWebView && video != null && video.value.isInitialized) {
      setState(() => _playing = video.value.isPlaying);
    } else {
      setState(() => _playing = !_playing);
    }
    _showControls();
  }

  Widget _buildSurface() {
    if (widget.useWebView && widget.webController != null) {
      return PinnedWebView(
        key: const ValueKey('washa-fullscreen-wv'),
        controller: widget.webController!,
      );
    }
    final video = widget.videoController;
    if (video != null && video.value.isInitialized) {
      return PinnedVideoPlayer(
        key: const ValueKey('washa-fullscreen-exo'),
        controller: video,
      );
    }
    return const ColoredBox(color: Colors.black);
  }

  Widget _buildControls() {
    final video = widget.videoController;
    if (!widget.useWebView && video != null && video.value.isInitialized) {
      return ListenableBuilder(
        listenable: video,
        builder: (context, _) {
          final value = video.value;
          final durMs = value.duration.inMilliseconds;
          final pos = value.position;
          final prog = durMs > 0 ? (pos.inMilliseconds / durMs).clamp(0.0, 1.0) : 0.0;
          return PlayerControls(
            playing: value.isPlaying,
            progress: prog,
            positionLabel: durMs > 0 ? _formatDuration(pos) : widget.positionLabel,
            durationLabel: durMs > 0 ? _formatDuration(value.duration) : widget.durationLabel,
            visible: _controlsVisible,
            isFullscreen: true,
            onUserInteraction: _showControls,
            onOpenLanguage: widget.onOpenLanguage == null
                ? null
                : () => unawaited(widget.onOpenLanguage!(context)),
            onOpenSettings: widget.onOpenSettings == null
                ? null
                : () => unawaited(widget.onOpenSettings!(context)),
            onToggleFullscreen: () => Navigator.of(context).pop(),
            onPlay: () => unawaited(_handlePlayPause()),
            onSeek: (seek) => unawaited(widget.onSeek(seek)),
          );
        },
      );
    }

    return PlayerControls(
      playing: _playing,
      progress: widget.progress,
      positionLabel: widget.positionLabel,
      durationLabel: widget.durationLabel,
      visible: _controlsVisible,
      isFullscreen: true,
      onUserInteraction: _showControls,
      onOpenLanguage:
          widget.onOpenLanguage == null ? null : () => unawaited(widget.onOpenLanguage!(context)),
      onOpenSettings:
          widget.onOpenSettings == null ? null : () => unawaited(widget.onOpenSettings!(context)),
      onToggleFullscreen: () => Navigator.of(context).pop(),
      onPlay: () => unawaited(_handlePlayPause()),
      onSeek: (seek) => unawaited(widget.onSeek(seek)),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildSurface(),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.75),
                              Colors.black.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Rudi',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                            ),
                            Expanded(
                              child: Text(
                                widget.channelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }
}
