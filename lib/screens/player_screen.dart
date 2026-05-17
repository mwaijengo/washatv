import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/channel.dart';
import '../player/channel_playback_engine.dart';
import '../utils/cache_bust_image_url.dart';
import '../widgets/channel_card.dart';
import '../widgets/playback_unavailable_overlay.dart';
import '../widgets/player_controls.dart';

typedef PlayerBackHandler = bool Function();

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channel,
    required this.premium,
    required this.onBack,
    required this.onOpenPlayer,
    required this.onOpenSubscription,
    required this.channels,
    this.channelImageCacheEpoch = 0,
    this.onBackHandlerChanged,
  });

  final Channel? channel;
  final bool premium;
  final VoidCallback onBack;
  final ValueChanged<Channel> onOpenPlayer;
  final VoidCallback onOpenSubscription;
  final List<Channel> channels;
  final int channelImageCacheEpoch;
  final ValueChanged<PlayerBackHandler?>? onBackHandlerChanged;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool playing = true;
  bool fullscreen = false;
  double progress = 0.0;
  String _positionLabel = '0:00';
  String _durationLabel = 'LIVE';

  VideoPlayerController? _video;
  bool _useWebView = false;
  bool _streamLoading = true;
  bool _streamUnavailable = false;
  bool _webFallbackTried = false;

  int _loadToken = 0;
  ChannelPlaybackSession? _session;

  Channel get _current => widget.channel ?? widget.channels.first;

  @override
  void initState() {
    super.initState();
    widget.onBackHandlerChanged?.call(_handlePlayerBack);
    unawaited(_startPlayback(_current));
  }

  @override
  void didUpdateWidget(PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _current;
    final prev = oldWidget.channel ?? oldWidget.channels.first;
    if (next.id != prev.id ||
        next.streamUrl.trim() != prev.streamUrl.trim() ||
        next.drm != prev.drm) {
      unawaited(_startPlayback(next));
    }
    if (oldWidget.onBackHandlerChanged != widget.onBackHandlerChanged) {
      widget.onBackHandlerChanged?.call(_handlePlayerBack);
    }
  }

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(null);
    _detachVideoListener();
    unawaited(_exitFullscreen(silent: true));
    unawaited(_session?.dispose());
    _session = null;
    _video = null;
    super.dispose();
  }

  /// `true` = back consumed (e.g. left fullscreen).
  bool _handlePlayerBack() {
    if (fullscreen) {
      unawaited(_exitFullscreen());
      return true;
    }
    return false;
  }

  void _detachVideoListener() {
    _video?.removeListener(_onVideoTick);
  }

  void _markUnavailable() {
    if (!mounted) return;
    setState(() {
      _streamUnavailable = true;
      _streamLoading = false;
      playing = false;
    });
  }

  void _onVideoTick() {
    final v = _video;
    if (v == null || !mounted) return;

    if (v.value.hasError && !_useWebView) {
      if (kDebugMode) debugPrint('Washa playback error (hidden from user)');
      final url = _current.streamUrl.trim();
      if (!kIsWeb && url.isNotEmpty && !_webFallbackTried) {
        _webFallbackTried = true;
        unawaited(_startPlayback(_current, forceWebView: true));
        return;
      }
      _markUnavailable();
      return;
    }

    final d = v.value.duration;
    final p = v.value.position;
    final durMs = d.inMilliseconds;
    final nextProgress = durMs > 0 ? (p.inMilliseconds / durMs).clamp(0.0, 1.0) : progress;
    final isPlaying = v.value.isPlaying;

    final posLabel = _formatDuration(p);
    final durLabel = durMs > 0 ? _formatDuration(d) : 'LIVE';

    if (isPlaying != playing ||
        (durMs > 0 && (nextProgress - progress).abs() > 0.002) ||
        posLabel != _positionLabel ||
        durLabel != _durationLabel) {
      setState(() {
        playing = isPlaying;
        if (durMs > 0) progress = nextProgress;
        _positionLabel = posLabel;
        _durationLabel = durLabel;
      });
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  Future<void> _startPlayback(Channel ch, {bool forceWebView = false}) async {
    final token = ++_loadToken;
    final url = ch.streamUrl.trim();

    _detachVideoListener();
    await _session?.dispose();
    _session = null;
    _video = null;

    if (!mounted || token != _loadToken) return;

    setState(() {
      _streamLoading = true;
      _streamUnavailable = false;
      _useWebView = false;
      if (!forceWebView) _webFallbackTried = false;
      playing = true;
      progress = 0;
      _positionLabel = '0:00';
      _durationLabel = 'LIVE';
    });

    if (url.isEmpty) {
      _markUnavailable();
      return;
    }

    try {
      final session = await ChannelPlaybackSession.open(
        streamUrl: url,
        drm: ch.drm,
        forceWebView: forceWebView,
      );
      if (!mounted || token != _loadToken) {
        await session.dispose();
        return;
      }

      _session = session;
      _useWebView = session.useWebView;

      if (session.useWebView) {
        setState(() {
          _streamLoading = false;
          _streamUnavailable = false;
          playing = true;
          _durationLabel = 'LIVE';
        });
        return;
      }

      final video = session.video!;
      video.addListener(_onVideoTick);
      await video.play();

      if (!mounted || token != _loadToken) {
        await session.dispose();
        return;
      }

      setState(() {
        _video = video;
        _streamLoading = false;
        _streamUnavailable = false;
        playing = true;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Washa playback: $e');
      if (!mounted || token != _loadToken) return;
      if (!kIsWeb && !forceWebView && !_webFallbackTried) {
        _webFallbackTried = true;
        await _startPlayback(ch, forceWebView: true);
        return;
      }
      _markUnavailable();
    }
  }

  Future<void> _togglePlayPause() async {
    if (_useWebView) {
      final web = _session?.web;
      if (web != null) {
        await web.runJavaScript(
          "(() => { const v = document.querySelector('video'); if (!v) return; v.paused ? v.play() : v.pause(); })();",
        );
      }
      if (mounted) setState(() => playing = !playing);
      return;
    }

    final v = _video;
    if (v == null || !v.value.isInitialized) {
      if (mounted) setState(() => playing = !playing);
      return;
    }

    if (v.value.isPlaying) {
      await v.pause();
    } else {
      await v.play();
    }
    if (mounted) setState(() => playing = v.value.isPlaying);
  }

  Future<void> _seekTo(double value) async {
    final v = _video;
    if (v == null || !v.value.isInitialized) {
      if (mounted) setState(() => progress = value.clamp(0.0, 1.0));
      return;
    }
    final d = v.value.duration;
    if (d.inMilliseconds <= 0) return;
    await v.seekTo(Duration(milliseconds: (d.inMilliseconds * value.clamp(0.0, 1.0)).round()));
    if (mounted) setState(() => progress = value.clamp(0.0, 1.0));
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (mounted) setState(() => fullscreen = true);
  }

  Future<void> _exitFullscreen({bool silent = false}) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    if (mounted && (fullscreen || silent)) {
      setState(() => fullscreen = false);
    }
  }

  Future<void> _toggleFullscreen() async {
    if (fullscreen) {
      await _exitFullscreen();
    } else {
      await _enterFullscreen();
    }
  }

  Widget _buildVideoLayer(Channel c, String heroUrl) {
    if (_useWebView && _session?.web != null) {
      return ColoredBox(
        color: Colors.black,
        child: WebViewWidget(controller: _session!.web!),
      );
    }

    final v = _video;
    if (v != null && v.value.isInitialized) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: v.value.aspectRatio > 0 ? v.value.aspectRatio : 16 / 9,
            child: VideoPlayer(v),
          ),
        ),
      );
    }

    return Image.network(
      heroUrl,
      fit: BoxFit.cover,
      key: ValueKey('player-hero|${c.id}|$heroUrl'),
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFF0B1220),
        alignment: Alignment.center,
        child: const Icon(Icons.live_tv_rounded, color: Color(0xFF6B7280), size: 34),
      ),
    );
  }

  Widget _buildPlayerStack(Channel c, String heroUrl, {required bool immersive}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoLayer(c, heroUrl),
        if (!_streamUnavailable && !_streamLoading && _video == null && !_useWebView)
          Image.network(
            heroUrl,
            fit: BoxFit.cover,
            key: ValueKey('player-poster|${c.id}|$heroUrl'),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        if (_streamLoading) const _PlaybackLoadingShade(),
        if (_streamUnavailable) PlaybackUnavailableOverlay(onClose: immersive ? widget.onBack : null),
        if (!_streamUnavailable && !_streamLoading && !playing)
          Container(
            color: const Color(0x66000000),
            child: Center(
              child: GestureDetector(
                onTap: () => unawaited(_togglePlayPause()),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: Color(0xF2FFFFFF), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow, color: Color(0xFF111827), size: 34),
                ),
              ),
            ),
          ),
        if (!_streamUnavailable)
          PlayerControls(
            playing: playing,
            progress: progress,
            positionLabel: _positionLabel,
            durationLabel: _durationLabel,
            isFullscreen: fullscreen,
            onPlay: () => unawaited(_togglePlayPause()),
            onToggleFullscreen: () => unawaited(_toggleFullscreen()),
            onSeek: (v) => unawaited(_seekTo(v)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.isEmpty) {
      return const Center(child: Text('Hakuna channel kwa sasa'));
    }

    final c = _current;
    final heroUrl = imageUrlWithCacheEpoch(c.imageUrl, widget.channelImageCacheEpoch);
    final related = widget.premium
        ? widget.channels.where((e) => e.id != c.id).take(12).toList()
        : widget.channels.where((e) => e.premium && e.id != c.id).take(12).toList();

    if (fullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_exitFullscreen());
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            top: false,
            bottom: false,
            child: _buildPlayerStack(c, heroUrl, immersive: true),
          ),
        ),
      );
    }

    return Column(
      children: [
        Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildPlayerStack(c, heroUrl, immersive: false),
            ),
            Container(
              color: const Color(0xE6000000),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Unacheza: ',
                        style: const TextStyle(color: Color(0xFF9CA3AF)),
                        children: [
                          TextSpan(
                            text: c.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.premium)
              GestureDetector(
                onTap: widget.onOpenSubscription,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xE6F59E0B), Color(0xEAF97316)]),
                  ),
                  child: const Center(
                    child: Text(
                      'Fungua Channel zote kwa Punguzo Hadi Asilimia 70%',
                      style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
            itemCount: related.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (_, i) {
              final cc = related[i];
              return ChannelCard(
                channel: cc,
                imageCacheEpoch: widget.channelImageCacheEpoch,
                locked: cc.premium && !widget.premium,
                onTap: () => cc.premium && !widget.premium ? widget.onOpenSubscription() : widget.onOpenPlayer(cc),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaybackLoadingShade extends StatelessWidget {
  const _PlaybackLoadingShade();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x88000000),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFEF4444)),
      ),
    );
  }
}
