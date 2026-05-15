import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/channel.dart';
import '../player/channel_playback_engine.dart';
import '../utils/cache_bust_image_url.dart';
import '../widgets/channel_card.dart';
import '../widgets/player_controls.dart';

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
  });

  final Channel? channel;
  final bool premium;
  final VoidCallback onBack;
  final ValueChanged<Channel> onOpenPlayer;
  final VoidCallback onOpenSubscription;
  final List<Channel> channels;
  final int channelImageCacheEpoch;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool playing = true;
  bool fullscreen = false;
  double progress = 0.0;

  VideoPlayerController? _video;
  bool _useWebView = false;
  bool _streamLoading = true;
  bool _streamError = false;
  bool _noStreamUrl = false;
  bool _webFallbackTried = false;

  int _loadToken = 0;
  ChannelPlaybackSession? _session;

  Channel get _current => widget.channel ?? widget.channels.first;

  @override
  void initState() {
    super.initState();
    unawaited(_startPlayback(_current));
  }

  @override
  void didUpdateWidget(PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _current;
    final prev = oldWidget.channel ?? oldWidget.channels.first;
    if (next.id != prev.id || next.streamUrl.trim() != prev.streamUrl.trim()) {
      unawaited(_startPlayback(next));
    }
  }

  @override
  void dispose() {
    _detachVideoListener();
    unawaited(_session?.dispose());
    _session = null;
    _video = null;
    super.dispose();
  }

  void _detachVideoListener() {
    _video?.removeListener(_onVideoTick);
  }

  void _onVideoTick() {
    final v = _video;
    if (v == null || !mounted) return;

    if (v.value.hasError && !_useWebView) {
      final url = _current.streamUrl.trim();
      if (kIsWeb && url.isNotEmpty && !_webFallbackTried) {
        _webFallbackTried = true;
        unawaited(_startPlayback(_current, forceWebView: true));
        return;
      }
      if (mounted) {
        setState(() {
          _streamError = true;
          _streamLoading = false;
          playing = false;
        });
      }
      return;
    }

    final d = v.value.duration;
    final p = v.value.position;
    final durMs = d.inMilliseconds;
    final nextProgress = durMs > 0 ? (p.inMilliseconds / durMs).clamp(0.0, 1.0) : progress;
    final isPlaying = v.value.isPlaying;

    if (isPlaying != playing || (durMs > 0 && (nextProgress - progress).abs() > 0.002)) {
      setState(() {
        playing = isPlaying;
        if (durMs > 0) progress = nextProgress;
      });
    }
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
      _streamError = false;
      _noStreamUrl = url.isEmpty;
      _useWebView = false;
      if (!forceWebView) _webFallbackTried = false;
      playing = true;
      progress = 0;
    });

    if (url.isEmpty) {
      if (mounted && token == _loadToken) {
        setState(() {
          _streamLoading = false;
          playing = false;
        });
      }
      return;
    }

    try {
      final session = await ChannelPlaybackSession.open(
        streamUrl: url,
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
          _streamError = false;
          playing = true;
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
        _streamError = false;
        playing = true;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Washa playback: $e');
      if (!mounted || token != _loadToken) return;
      if (kIsWeb && !forceWebView && !_webFallbackTried) {
        _webFallbackTried = true;
        await _startPlayback(ch, forceWebView: true);
        return;
      }
      setState(() {
        _streamLoading = false;
        _streamError = true;
        playing = false;
      });
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

  bool get _showPosterOnly =>
      _noStreamUrl || _streamError || (!_useWebView && (_video == null || !_video!.value.isInitialized));

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
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: v.value.size.width,
            height: v.value.size.height,
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
        child: const Icon(Icons.broken_image_outlined, color: Color(0xFF6B7280), size: 34),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.isEmpty) {
      return const Center(child: Text('Hakuna channel kwa sasa'));
    }
    final c = _current;
    final heroUrl = imageUrlWithCacheEpoch(c.imageUrl, widget.channelImageCacheEpoch);
    final channels = widget.premium
        ? widget.channels.where((e) => e.id != c.id).take(12).toList()
        : widget.channels.where((e) => e.premium && e.id != c.id).take(12).toList();

    return Column(
      children: [
        Column(
          children: [
            AspectRatio(
              aspectRatio: fullscreen ? 1 : (16 / 9),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildVideoLayer(c, heroUrl),
                  if (_showPosterOnly && !_streamLoading)
                    Image.network(
                      heroUrl,
                      fit: BoxFit.cover,
                      key: ValueKey('player-poster|${c.id}|$heroUrl'),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  if (_streamLoading)
                    Container(
                      color: const Color(0x88000000),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFEF4444)),
                      ),
                    ),
                  if (!playing)
                    Container(
                      color: const Color(0x66000000),
                      child: Center(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: Color(0xF2FFFFFF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow, color: Color(0xFF111827), size: 34),
                          ),
                        ),
                      ),
                    ),
                  PlayerControls(
                    playing: playing,
                    progress: progress,
                    onPlay: () => unawaited(_togglePlayPause()),
                    onToggleFullscreen: () => setState(() => fullscreen = !fullscreen),
                    onSeek: (v) => unawaited(_seekTo(v)),
                  ),
                ],
              ),
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
            itemCount: channels.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (_, i) {
              final cc = channels[i];
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
