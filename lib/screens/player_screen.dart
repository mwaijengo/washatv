import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/channel.dart';
import '../player/channel_playback_engine.dart';
import '../player/php_gateway_js.dart';
import '../utils/cache_bust_image_url.dart';
import '../widgets/channel_card.dart';
import '../widgets/playback_unavailable_overlay.dart';
import '../widgets/player_controls.dart';

typedef PlayerBackHandler = bool Function();

const _kMaxAutoRetries = 8;
const _kRetryDelay = Duration(seconds: 3);
const _kWebPlaybackPollInterval = Duration(milliseconds: 800);
const _kWebPlaybackPollMaxTicks = 45;

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
    this.onFullscreenChanged,
  });

  final Channel? channel;
  final bool premium;
  final VoidCallback onBack;
  final ValueChanged<Channel> onOpenPlayer;
  final VoidCallback onOpenSubscription;
  final List<Channel> channels;
  final int channelImageCacheEpoch;
  final ValueChanged<PlayerBackHandler?>? onBackHandlerChanged;
  final ValueChanged<bool>? onFullscreenChanged;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  bool playing = true;
  bool fullscreen = false;
  bool _immersiveControlsVisible = false;
  OverlayEntry? _fullscreenOverlay;
  Timer? _controlsHideTimer;
  double progress = 0.0;
  String _positionLabel = '0:00';
  String _durationLabel = 'LIVE';

  VideoPlayerController? _video;
  bool _useWebView = false;
  bool _streamLoading = true;
  bool _showManualRetry = false;
  bool _webFallbackTried = false;
  bool _handlingPlaybackFailure = false;

  int _loadToken = 0;
  int _autoRetryCount = 0;
  Timer? _loadWatchdog;
  Timer? _playbackRetryTimer;
  Timer? _webPlaybackPollTimer;
  ChannelPlaybackSession? _session;

  Channel get _current => widget.channel ?? widget.channels.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    widget.onBackHandlerChanged?.call(null);
    _loadWatchdog?.cancel();
    _cancelPlaybackRetry();
    _cancelWebPlaybackPoll();
    _detachVideoListener();
    _cancelControlsHideTimer();
    _removeFullscreenOverlay();
    unawaited(_applyFullscreenSystemUi(enter: false));
    widget.onFullscreenChanged?.call(false);
    unawaited(_session?.dispose());
    _session = null;
    _video = null;
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (fullscreen) {
      _fullscreenOverlay?.markNeedsBuild();
    }
  }

  void _cancelLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
  }

  void _cancelPlaybackRetry() {
    _playbackRetryTimer?.cancel();
    _playbackRetryTimer = null;
  }

  void _cancelWebPlaybackPoll() {
    _webPlaybackPollTimer?.cancel();
    _webPlaybackPollTimer = null;
  }

  void _armLoadWatchdog(int token, Channel ch, {required bool forceWebView}) {
    _cancelLoadWatchdog();
    final timeout = forceWebView ? const Duration(seconds: 30) : const Duration(seconds: 12);
    _loadWatchdog = Timer(timeout, () {
      if (!mounted || token != _loadToken || !_streamLoading) return;
      if (!kIsWeb && !forceWebView && !_webFallbackTried) {
        _webFallbackTried = true;
        unawaited(_startPlayback(ch, forceWebView: true));
        return;
      }
      _handlePlaybackFailure(forceWebView: forceWebView);
    });
  }

  void _showRetryPrompt() {
    if (!mounted) return;
    setState(() {
      _showManualRetry = true;
      _streamLoading = false;
      playing = false;
    });
  }

  void _handlePlaybackFailure({bool forceWebView = false}) {
    if (!mounted || _handlingPlaybackFailure) return;
    _handlingPlaybackFailure = true;

    _cancelLoadWatchdog();
    _cancelWebPlaybackPoll();
    _cancelPlaybackRetry();
    _detachVideoListener();

    final retiring = _session;
    _session = null;
    _video = null;
    if (retiring != null) unawaited(retiring.dispose());

    if (!forceWebView && !kIsWeb && !_webFallbackTried && _current.streamUrl.trim().isNotEmpty) {
      _webFallbackTried = true;
      _handlingPlaybackFailure = false;
      unawaited(_startPlayback(_current, forceWebView: true));
      return;
    }

    if (_autoRetryCount < _kMaxAutoRetries) {
      _autoRetryCount++;
      setState(() {
        _streamLoading = true;
        _showManualRetry = false;
        playing = true;
      });
      _playbackRetryTimer = Timer(_kRetryDelay, () {
        _handlingPlaybackFailure = false;
        if (!mounted) return;
        unawaited(_startPlayback(_current, forceWebView: forceWebView || _webFallbackTried));
      });
      return;
    }

    _handlingPlaybackFailure = false;
    _showRetryPrompt();
  }

  void _manualRetryPlayback() {
    _autoRetryCount = 0;
    _webFallbackTried = false;
    unawaited(_startPlayback(_current));
  }

  void _attachWebViewMonitoring(WebViewController web, int token) {
    web.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) => unawaited(web.runJavaScript(kPhpGatewayRecoveryJs)),
        onPageFinished: (_) => unawaited(web.runJavaScript(kPhpGatewayRecoveryJs)),
        onWebResourceError: (error) {
          if (error.isForMainFrame ?? false) {
            _handlePlaybackFailure(forceWebView: true);
          }
        },
      ),
    );

    _cancelWebPlaybackPoll();
    var ticks = 0;
    _webPlaybackPollTimer = Timer.periodic(_kWebPlaybackPollInterval, (timer) async {
      ticks++;
      if (!mounted || token != _loadToken) {
        timer.cancel();
        return;
      }

      if (ticks > _kWebPlaybackPollMaxTicks) {
        timer.cancel();
        _handlePlaybackFailure(forceWebView: true);
        return;
      }

      try {
        final raw = await web.runJavaScriptReturningResult(
          "(() => { const v = document.querySelector('video'); if (!v) return '0'; if (v.error) return 'err'; if (!v.paused && v.readyState >= 2 && v.currentTime > 0) return '1'; return '0'; })()",
        );
        final status = raw.toString().replaceAll('"', '');
        if (status == '1') {
          timer.cancel();
          _cancelLoadWatchdog();
          _autoRetryCount = 0;
          if (!mounted || token != _loadToken) return;
          setState(() {
            _streamLoading = false;
            _showManualRetry = false;
            playing = true;
            _durationLabel = 'LIVE';
          });
        } else if (status == 'err') {
          timer.cancel();
          _handlePlaybackFailure(forceWebView: true);
        }
      } catch (_) {}
    });
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

  void _onVideoTick() {
    final v = _video;
    if (v == null || !mounted) return;

    if (v.value.hasError && !_useWebView) {
      if (kDebugMode) debugPrint('Washa playback error (hidden from user)');
      _handlePlaybackFailure();
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
    _handlingPlaybackFailure = false;
    final url = ch.streamUrl.trim();

    _cancelLoadWatchdog();
    _cancelPlaybackRetry();
    _cancelWebPlaybackPoll();
    _detachVideoListener();
    final retiring = _session;
    _session = null;
    _video = null;
    if (retiring != null) unawaited(retiring.dispose());

    if (!mounted || token != _loadToken) return;

    setState(() {
      _streamLoading = true;
      _showManualRetry = false;
      _useWebView = false;
      if (!forceWebView) {
        _webFallbackTried = false;
        _autoRetryCount = 0;
      }
      playing = true;
      progress = 0;
      _positionLabel = '0:00';
      _durationLabel = 'LIVE';
    });

    if (url.isEmpty) {
      _showRetryPrompt();
      return;
    }

    _armLoadWatchdog(token, ch, forceWebView: forceWebView);

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
        final web = session.web!;
        _attachWebViewMonitoring(web, token);
        _armLoadWatchdog(token, ch, forceWebView: true);
        setState(() {
          _streamLoading = true;
          _showManualRetry = false;
          playing = true;
          _durationLabel = 'LIVE';
        });
        return;
      }

      final video = session.video!;
      video.addListener(_onVideoTick);

      if (!mounted || token != _loadToken) {
        await session.dispose();
        return;
      }

      _cancelLoadWatchdog();
      _autoRetryCount = 0;
      setState(() {
        _video = video;
        _streamLoading = false;
        _showManualRetry = false;
        playing = true;
      });
      unawaited(video.play());
    } catch (e) {
      if (kDebugMode) debugPrint('Washa playback: $e');
      if (!mounted || token != _loadToken) return;
      _handlePlaybackFailure(forceWebView: forceWebView);
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

  void _cancelControlsHideTimer() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
  }

  void _scheduleControlsHide() {
    _cancelControlsHideTimer();
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !fullscreen) return;
      setState(() => _immersiveControlsVisible = false);
    });
  }

  void _showImmersiveControls() {
    if (!fullscreen) return;
    if (!_immersiveControlsVisible) {
      setState(() => _immersiveControlsVisible = true);
    }
    _scheduleControlsHide();
  }

  void _hideImmersiveControls() {
    _cancelControlsHideTimer();
    if (_immersiveControlsVisible) {
      setState(() => _immersiveControlsVisible = false);
    }
  }

  void _onImmersiveScreenTap() {
    if (_immersiveControlsVisible) {
      _hideImmersiveControls();
    } else {
      _showImmersiveControls();
    }
  }

  void _removeFullscreenOverlay() {
    _fullscreenOverlay?.remove();
    _fullscreenOverlay = null;
  }

  Future<void> _applyFullscreenSystemUi({required bool enter}) async {
    try {
      if (enter) {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
          overlays: const [],
        );
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
          overlays: SystemUiOverlay.values,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Washa fullscreen UI: $e');
    }
  }

  Future<void> _enterFullscreen() async {
    if (fullscreen || !mounted) return;

    await _applyFullscreenSystemUi(enter: true);
    if (!mounted) return;

    _immersiveControlsVisible = false;
    _cancelControlsHideTimer();

    final heroUrl = imageUrlWithCacheEpoch(_current.imageUrl, widget.channelImageCacheEpoch);
    _fullscreenOverlay = OverlayEntry(
      builder: (overlayContext) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_exitFullscreen());
          },
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.black,
            ),
            child: Material(
              color: Colors.black,
              child: _buildPlayerStack(_current, heroUrl, immersive: true),
            ),
          ),
        );
      },
    );

    final overlayState = Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.of(context);
    overlayState.insert(_fullscreenOverlay!);
    widget.onFullscreenChanged?.call(true);
    setState(() => fullscreen = true);
  }

  Future<void> _exitFullscreen({bool silent = false}) async {
    if (!fullscreen && !silent) return;

    _cancelControlsHideTimer();
    _immersiveControlsVisible = false;
    _removeFullscreenOverlay();
    await _applyFullscreenSystemUi(enter: false);

    if (mounted && (fullscreen || silent)) {
      widget.onFullscreenChanged?.call(false);
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

  Widget _buildVideoLayer(Channel c, String heroUrl, {required bool fillScreen}) {
    final hideWebView = _streamLoading || _showManualRetry;

    if (_useWebView && _session?.web != null) {
      final web = Opacity(
        opacity: hideWebView ? 0 : 1,
        child: WebViewWidget(controller: _session!.web!),
      );
      return ColoredBox(
        color: Colors.black,
        child: fillScreen ? SizedBox.expand(child: web) : web,
      );
    }

    final v = _video;
    if (v != null && v.value.isInitialized) {
      final player = VideoPlayer(v);
      if (fillScreen) {
        final size = v.value.size;
        final width = size.width > 0 ? size.width : 16.0;
        final height = size.height > 0 ? size.height : 9.0;
        return ColoredBox(
          color: Colors.black,
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(width: width, height: height, child: player),
            ),
          ),
        );
      }

      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: v.value.aspectRatio > 0 ? v.value.aspectRatio : 16 / 9,
            child: player,
          ),
        ),
      );
    }

    if (_streamLoading || _showManualRetry) {
      return const ColoredBox(color: Colors.black);
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
    final controlsVisible = !immersive || _immersiveControlsVisible;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: immersive ? _onImmersiveScreenTap : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildVideoLayer(c, heroUrl, fillScreen: immersive),
          if (!_showManualRetry && !_streamLoading && _video == null && !_useWebView)
            Image.network(
              heroUrl,
              fit: BoxFit.cover,
              key: ValueKey('player-poster|${c.id}|$heroUrl'),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (_streamLoading) const _PlaybackLoadingShade(),
          if (_showManualRetry)
            PlaybackUnavailableOverlay(
              onRetry: _manualRetryPlayback,
              onClose: immersive ? widget.onBack : null,
            ),
          if (!_showManualRetry && !_streamLoading && !playing)
            IgnorePointer(
              ignoring: immersive && !controlsVisible,
              child: AnimatedOpacity(
                opacity: controlsVisible || !immersive ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Container(
                  color: const Color(0x66000000),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        if (immersive) _showImmersiveControls();
                        unawaited(_togglePlayPause());
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(color: Color(0xF2FFFFFF), shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow, color: Color(0xFF111827), size: 34),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!_showManualRetry && !_streamLoading)
            PlayerControls(
              playing: playing,
              progress: progress,
              positionLabel: _positionLabel,
              durationLabel: _durationLabel,
              isFullscreen: fullscreen,
              visible: controlsVisible,
              onUserInteraction: immersive ? _showImmersiveControls : null,
              onPlay: () => unawaited(_togglePlayPause()),
              onToggleFullscreen: () => unawaited(_toggleFullscreen()),
              onSeek: (v) => unawaited(_seekTo(v)),
            ),
        ],
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
    final related = widget.premium
        ? widget.channels.where((e) => e.id != c.id).take(12).toList()
        : widget.channels.where((e) => e.premium && e.id != c.id).take(12).toList();

    if (fullscreen) {
      _fullscreenOverlay?.markNeedsBuild();
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
