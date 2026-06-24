import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/channel.dart';
import '../player/channel_playback_engine.dart';
import '../player/playback_http_headers.dart';
import '../player/playback_quality.dart';
import '../player/php_gateway_js.dart';
import '../player/stream_url_classifier.dart';
import '../player/stream_url_resolver.dart';
import '../player/web_error_hide_js.dart';
import '../player/web_media_control_js.dart';
import '../player/webview_playback_probe.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/cache_bust_image_url.dart';
import '../widgets/channel_card.dart';
import '../widgets/playback_unavailable_overlay.dart';
import '../widgets/player_controls.dart';
import '../widgets/stable_player_surface.dart';
import 'fullscreen_player_page.dart';

typedef PlayerBackHandler = bool Function();

const _kMaxAutoRetries = 1;
const _kRetryDelay = Duration(seconds: 3);
const _kWebStartupPollInterval = Duration(milliseconds: 250);
const _kWebHealthPollInterval = Duration(seconds: 8);
const _kGatewayStartupPollInterval = Duration(milliseconds: 200);
const _kWebStartupPollMaxTicks = 80;
const _kGatewayStartupPollMaxTicks = 60;
const _kWebStartupErrorThreshold = 3;
const _kWebHealthErrorThreshold = 4;
const _kNativeErrorGrace = Duration(seconds: 3);

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
  Timer? _controlsHideTimer;
  double progress = 0.0;
  String _positionLabel = '0:00';
  String _durationLabel = 'LIVE';

  final GlobalKey _playerHostKey = GlobalKey();

  VideoPlayerController? _video;
  bool _useWebView = false;
  bool _streamLoading = true;
  bool _showManualRetry = false;
  bool _webFallbackTried = false;
  bool _handlingPlaybackFailure = false;
  bool _dataSaverEnabled = true;
  int _qualityMaxHeight = kDefaultDataSaverHeight;
  String _preferredLanguage = 'sw';
  final Set<PlaybackRoute> _skipRoutes = {};

  final _storage = StorageService();
  int _loadToken = 0;
  int _autoRetryCount = 0;
  Timer? _loadWatchdog;
  Timer? _playbackRetryTimer;
  Timer? _webPlaybackPollTimer;
  Timer? _nativeErrorGraceTimer;
  bool _webPlaybackReady = false;
  int _webHealthErrorStreak = 0;
  int _webStartupErrorStreak = 0;
  bool _fullscreenBusy = false;
  bool _webPollInFlight = false;
  /// Portrait WebView/Exo must be unmounted before fullscreen route mounts the same controller.
  bool _portraitSurfaceMounted = true;
  int _playerSurfaceEpoch = 0;
  ChannelPlaybackSession? _session;

  Channel get _current => widget.channel ?? widget.channels.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.onBackHandlerChanged?.call(_handlePlayerBack);
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    );
    unawaited(_bootstrapPlayback());
  }

  Future<void> _bootstrapPlayback() async {
    unawaited(
      _storage.getDataSaverEnabled().then((enabled) {
        if (mounted) setState(() => _dataSaverEnabled = enabled);
      }),
    );
    if (!mounted) return;
    await _startPlayback(_current);
  }

  PlaybackQuality get _playbackQuality => _dataSaverEnabled
      ? PlaybackQuality(dataSaverEnabled: true, maxHeight: _qualityMaxHeight)
      : PlaybackQuality.full;

  Future<void> _applyQualityChoice({required bool dataSaver, required int maxHeight}) async {
    if (_dataSaverEnabled == dataSaver && _qualityMaxHeight == maxHeight) return;
    setState(() {
      _dataSaverEnabled = dataSaver;
      _qualityMaxHeight = maxHeight;
    });
    await _storage.setDataSaverEnabled(dataSaver);

    final route = _session?.route;
    final cap = dataSaver ? maxHeight : 0;

    if (_isGatewayChannel(_current) || route == PlaybackRoute.directWebView) {
      await _reloadGatewayWithQualityCap(cap);
      return;
    }

    if (_useWebView && route == PlaybackRoute.shakaWebView && _session?.web != null) {
      await _reloadShakaWithQuality(dataSaver);
      return;
    }

    _restartPlaybackForQuality(dataSaver);
  }

  void _restartPlaybackForQuality(bool dataSaver) {
    _webFallbackTried = false;
    _autoRetryCount = 0;
    final skips = <PlaybackRoute>{};
    if (dataSaver) {
      skips.add(PlaybackRoute.nativeExo);
      skips.add(PlaybackRoute.fastHlsWebView);
    } else {
      skips.add(PlaybackRoute.shakaWebView);
    }
    unawaited(_startPlayback(_current, skipRoutes: skips));
  }

  Future<void> _reloadShakaWithQuality(bool dataSaver) async {
    final web = _session?.web;
    if (web == null) return;

    final resolved = await StreamUrlResolver.resolve(_current.streamUrl.trim());
    final playUrl = resolved.playbackUrl;
    if (playUrl.isEmpty) {
      _restartPlaybackForQuality(dataSaver);
      return;
    }

    _cancelWebPlaybackPoll();
    _webPlaybackReady = false;
    if (mounted) {
      setState(() {
        _streamLoading = true;
        playing = true;
      });
    }

    await web.runJavaScript('window.__washaUserPaused = false; window.__washaPlaying = false;');
    final quality = dataSaver ? PlaybackQuality.okoaBando : PlaybackQuality.full;
    await ChannelPlaybackSession.loadShakaWebView(
      web,
      url: playUrl,
      drm: _current.drm,
      quality: quality,
      headers: resolved.headers,
    );

    if (!mounted) return;
    final token = _loadToken;
    _attachWebViewMonitoring(web, token, PlaybackRoute.shakaWebView);
    _armWebStartupPoll(web, token);
  }

  Future<void> _reloadGatewayWithQualityCap(int maxHeight) async {
    final web = _session?.web;
    if (web == null) return;

    _cancelWebPlaybackPoll();
    await web.runJavaScript(
      'window.__washaUserPaused = false; window.__washaPlaying = false; window.__washaGatewayPassive = false;',
    );
    await web.runJavaScript('window.__washaMaxHeight=$maxHeight;');
    await web.runJavaScript(kWebQualityInstallJs);
    await web.runJavaScript(kWebQualityApplyJs);
    await _injectWebMediaControl(web);
    await web.runJavaScript(kWebMediaEnsurePlayJs);

    if (!mounted) return;
    final token = _loadToken;
    _armGatewayStartupPoll(web, token);
  }

  Future<void> _showLanguageSheet({BuildContext? sheetContext}) async {
    final ctx = sheetContext ?? context;
    if (fullscreen) _showImmersiveControls();
    final choice = await showModalBottomSheet<String>(
      context: ctx,
      backgroundColor: const Color(0xE6202020),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Badili Lugha',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.check,
                  color: _preferredLanguage == 'sw' ? AppTheme.emerald : Colors.transparent,
                  size: 20,
                ),
                title: const Text('Kiswahili', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'sw'),
              ),
              ListTile(
                leading: Icon(
                  Icons.check,
                  color: _preferredLanguage == 'en' ? AppTheme.emerald : Colors.transparent,
                  size: 20,
                ),
                title: const Text('Kiingereza', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'en'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null || choice == _preferredLanguage) return;
    setState(() => _preferredLanguage = choice);
    if (fullscreen) _scheduleControlsHide();
  }

  Future<void> _showQualitySheet() async {
    if (fullscreen) _showImmersiveControls();
    final choice = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: const Color(0xE6202020),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'OKOA BANDO — ubora wa video',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              _qualityTile(ctx, label: 'Auto (360p)', value: kDefaultDataSaverHeight),
              _qualityTile(ctx, label: '480p', value: 480),
              _qualityTile(ctx, label: '720p', value: 720),
              ListTile(
                title: const Text('HD (bora)', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 0),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice == 0) {
      await _applyQualityChoice(dataSaver: false, maxHeight: 0);
    } else {
      await _applyQualityChoice(dataSaver: true, maxHeight: choice);
    }
    if (fullscreen) _scheduleControlsHide();
  }

  Widget _qualityTile(BuildContext ctx, {required String label, required int value}) {
    final selected = _dataSaverEnabled && _qualityMaxHeight == value;
    return ListTile(
      leading: Icon(Icons.check, color: selected ? AppTheme.emerald : Colors.transparent, size: 20),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  Future<void> _showPlayerSettingsSheet({BuildContext? sheetContext}) async {
    final ctx = sheetContext ?? context;
    if (fullscreen) _showImmersiveControls();
    final selection = await showModalBottomSheet<String>(
      context: ctx,
      backgroundColor: const Color(0xE6202020),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'MIPANGILIO YA PLAYER',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              ListTile(
                title: const Text('Ubora wa video', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'quality'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || selection == null) return;
    if (selection == 'quality') {
      await _showQualitySheet();
    }
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
    _cancelNativeErrorGrace();
    _detachVideoListener();
    _cancelControlsHideTimer();
    unawaited(_applyFullscreenSystemUi(enter: false));
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    widget.onFullscreenChanged?.call(false);
    unawaited(_retireSession(_session));
    ChannelPlaybackSession.clearGatewayWeb();
    _session = null;
    _video = null;
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted || !fullscreen) return;
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || !fullscreen) return;
      unawaited(_ensurePlaybackPlaying());
    });
  }

  Future<void> _retireSession(ChannelPlaybackSession? session) async {
    if (session == null) return;
    await session.dispose();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (session.route == PlaybackRoute.directWebView) return;
      await Future<void>.delayed(const Duration(milliseconds: 40));
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
    _webPlaybackReady = false;
    _webHealthErrorStreak = 0;
    _webStartupErrorStreak = 0;
  }

  void _cancelNativeErrorGrace() {
    _nativeErrorGraceTimer?.cancel();
    _nativeErrorGraceTimer = null;
  }

  void _armLoadWatchdog(int token, Channel ch, {required bool forceWebView}) {
    _cancelLoadWatchdog();
    final timeout = forceWebView ? const Duration(seconds: 25) : const Duration(seconds: 6);
    _loadWatchdog = Timer(timeout, () {
      if (!mounted || token != _loadToken || !_streamLoading) return;
      final v = _video;
      if (v != null && v.value.isInitialized && !v.value.hasError) return;
      if (!kIsWeb && !forceWebView && !_webFallbackTried) {
        _webFallbackTried = true;
        _skipRoutes.add(PlaybackRoute.nativeExo);
        unawaited(_startPlayback(ch, forceWebView: true, skipRoutes: _skipRoutes));
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

  bool _isGatewayChannel(Channel ch) =>
      StreamUrlClassifier.isPhpLikeUrl(ch.streamUrl.trim());

  /// Hide WebView only when showing the user-facing error prompt.
  bool get _hideWebPlaybackSurface => _showManualRetry;

  bool _hasMorePlaybackRoutes(Channel ch, {required bool webOnly}) {
    final plan = ChannelPlaybackSession.playbackRoutePlan(
      url: ch.streamUrl.trim(),
      drm: ch.drm,
      quality: _playbackQuality,
      forceWebView: webOnly,
    );
    return plan.any((route) => !_skipRoutes.contains(route));
  }

  void _handlePlaybackFailure({bool forceWebView = false}) {
    if (!mounted || _handlingPlaybackFailure) return;
    _handlingPlaybackFailure = true;

    _cancelLoadWatchdog();
    _cancelWebPlaybackPoll();
    _cancelPlaybackRetry();
    _cancelNativeErrorGrace();
    _detachVideoListener();

    final retiring = _session;
    final failedRoute = retiring?.route;
    if (failedRoute != null) _skipRoutes.add(failedRoute);
    _session = null;
    _video = null;
    setState(() => _useWebView = false);

    unawaited(_retireSession(retiring).then((_) {
      if (!mounted) return;

      final webOnly = forceWebView || _webFallbackTried;
      if (_hasMorePlaybackRoutes(_current, webOnly: webOnly)) {
        _handlingPlaybackFailure = false;
        if (!webOnly && !kIsWeb) _webFallbackTried = true;
        unawaited(_startPlayback(_current, forceWebView: webOnly, skipRoutes: _skipRoutes));
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
          _skipRoutes.clear();
          final gateway = _isGatewayChannel(_current);
          unawaited(_startPlayback(_current, forceWebView: gateway));
        });
        return;
      }

      _handlingPlaybackFailure = false;
      _showRetryPrompt();
    }));
  }

  void _manualRetryPlayback() {
    _autoRetryCount = 0;
    _webFallbackTried = false;
    _skipRoutes.clear();
    unawaited(_startPlayback(_current));
  }

  Future<void> _checkWebPlayback(
    WebViewController web,
    int token, {
    bool healthOnly = false,
  }) async {
    if (!mounted || token != _loadToken || _webPollInFlight) return;
    _webPollInFlight = true;
    try {
      final raw = await web.runJavaScriptReturningResult(
        healthOnly ? kWebPlaybackErrorJs : kWebPlaybackStatusJs,
      );
      final status = raw.toString().replaceAll('"', '');
      if (!healthOnly && status == '1') {
        _cancelLoadWatchdog();
        _autoRetryCount = 0;
        if (!mounted || token != _loadToken) return;
        _markWebPlaybackReady(web, token);
      } else if (status == 'err') {
        if (healthOnly && _webPlaybackReady) {
          _webHealthErrorStreak++;
          if (_isGatewayChannel(_current)) {
            if (_webHealthErrorStreak >= _kWebHealthErrorThreshold) {
              _webHealthErrorStreak = 0;
              unawaited(_nudgeGatewayPlayback(web));
            }
            return;
          }
          if (_webHealthErrorStreak < _kWebHealthErrorThreshold) return;
        } else if (!healthOnly && !_webPlaybackReady) {
          _webStartupErrorStreak++;
          if (_webStartupErrorStreak < _kWebStartupErrorThreshold) return;
        }
        _cancelWebPlaybackPoll();
        _handlePlaybackFailure(forceWebView: _webFallbackTried || _isGatewayChannel(_current));
      } else if (healthOnly) {
        _webHealthErrorStreak = 0;
      } else if (!healthOnly) {
        _webStartupErrorStreak = 0;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Washa web probe: $e');
    } finally {
      _webPollInFlight = false;
    }
  }

  Future<void> _nudgeGatewayPlayback(WebViewController web) async {
    if (!mounted) return;
    await _injectWebMediaControl(web);
    await web.runJavaScript(kWebMediaEnsurePlayJs);
  }

  void _armWebStartupPoll(WebViewController web, int token) {
    _cancelWebPlaybackPoll();
    unawaited(_injectWebMediaControl(web));
    unawaited(_checkWebPlayback(web, token));
    _nudgeAutoplayOnce(web, token);
    var ticks = 0;
    _webPlaybackPollTimer = Timer.periodic(_kWebStartupPollInterval, (timer) async {
      ticks++;
      if (!mounted || token != _loadToken || _webPlaybackReady) {
        timer.cancel();
        return;
      }

      if (ticks > _kWebStartupPollMaxTicks) {
        timer.cancel();
        _handlePlaybackFailure(forceWebView: true);
        return;
      }

      await _checkWebPlayback(web, token);
    });
  }

  void _armWebHealthPoll(WebViewController web, int token) {
    _webPlaybackPollTimer?.cancel();
    _webPlaybackPollTimer = Timer.periodic(_kWebHealthPollInterval, (timer) async {
      if (!mounted || token != _loadToken) {
        timer.cancel();
        return;
      }
      await _checkWebPlayback(web, token, healthOnly: true);
    });
  }

  void _markWebPlaybackReady(WebViewController web, int token) {
    if (!mounted || token != _loadToken || _webPlaybackReady) return;
    _webPlaybackReady = true;
    _webStartupErrorStreak = 0;
    setState(() {
      _streamLoading = false;
      _showManualRetry = false;
      playing = true;
      _durationLabel = 'LIVE';
    });
    _armWebHealthPoll(web, token);
    unawaited(_ensurePlaybackPlaying());
  }

  Future<void> _injectWebMediaControl(WebViewController web) async {
    await web.runJavaScript(kWebMediaControlJs);
    await web.runJavaScript(kWebHidePlayerErrorsJs);
  }

  void _nudgeAutoplayOnce(WebViewController web, int token) {
    for (final delay in const [
      Duration(milliseconds: 0),
      Duration(milliseconds: 150),
      Duration(milliseconds: 400),
    ]) {
      Future<void>.delayed(delay, () async {
        if (!mounted || token != _loadToken || _webPlaybackReady) return;
        await _injectWebMediaControl(web);
        await web.runJavaScript(kWebMediaEnsurePlayJs);
      });
    }
  }

  Future<void> _injectGatewayBootstrap(WebViewController web) async {
    final cap = _dataSaverEnabled ? _qualityMaxHeight : 0;
    await _injectWebMediaControl(web);
    await web.runJavaScript(
      'window.__washaMaxHeight=$cap; window.__washaGatewayPassive=false; window.__washaGatewayRecovery=false;',
    );
    await web.runJavaScript(kWebQualityInstallJs);
  }

  Future<void> _injectGatewayScripts(WebViewController web) async {
    await _injectGatewayBootstrap(web);
    await web.runJavaScript(kPhpGatewayPassiveJs);
    await web.runJavaScript(kWebMediaEnsurePlayJs);
  }

  void _onGatewayPageStarted(WebViewController web, int token) {
    if (!mounted || token != _loadToken) return;
    unawaited(_injectGatewayBootstrap(web));
    _nudgeAutoplayOnce(web, token);
  }

  void _onGatewayPageReady(WebViewController web, int token) {
    if (!mounted || token != _loadToken) return;
    unawaited(_injectGatewayScripts(web).then((_) {
      if (!mounted || token != _loadToken) return;
      unawaited(_checkWebPlayback(web, token));
    }));
  }

  void _attachWebViewMonitoring(WebViewController web, int token, PlaybackRoute route) {
    final useGatewayRecovery = route == PlaybackRoute.directWebView;

    web.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: useGatewayRecovery
            ? (_) => _onGatewayPageStarted(web, token)
            : null,
        onPageFinished: useGatewayRecovery
            ? (_) => _onGatewayPageReady(web, token)
            : null,
        onWebResourceError: useGatewayRecovery
            ? (error) {
                if (_webPlaybackReady) return;
                if (error.isForMainFrame ?? false) {
                  _handlePlaybackFailure(forceWebView: true);
                }
              }
            : null,
      ),
    );

    if (useGatewayRecovery) {
      _armGatewayStartupPoll(web, token);
    } else {
      _armWebStartupPoll(web, token);
    }
  }

  void _armGatewayStartupPoll(WebViewController web, int token) {
    _cancelWebPlaybackPoll();
    unawaited(_checkWebPlayback(web, token));
    var ticks = 0;
    _webPlaybackPollTimer = Timer.periodic(_kGatewayStartupPollInterval, (timer) async {
      ticks++;
      if (!mounted || token != _loadToken || _webPlaybackReady) {
        timer.cancel();
        return;
      }
      if (ticks > _kGatewayStartupPollMaxTicks) {
        timer.cancel();
        _handlePlaybackFailure(forceWebView: true);
        return;
      }
      await _checkWebPlayback(web, token);
    });
  }

  /// `true` = back consumed (e.g. left fullscreen).
  bool _handlePlayerBack() {
    if (fullscreen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
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
      _nativeErrorGraceTimer ??= Timer(_kNativeErrorGrace, () {
        _nativeErrorGraceTimer = null;
        final current = _video;
        if (current == null || !mounted || current.value.hasError != true) return;
        if (kDebugMode) debugPrint('Washa playback error (hidden from user)');
        _handlePlaybackFailure();
      });
      return;
    }

    _cancelNativeErrorGrace();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  Future<void> _startPlayback(
    Channel ch, {
    bool forceWebView = false,
    Set<PlaybackRoute>? skipRoutes,
  }) async {
    final token = ++_loadToken;
    _handlingPlaybackFailure = false;
    final url = ch.streamUrl.trim();

    _cancelLoadWatchdog();
    _cancelPlaybackRetry();
    _cancelWebPlaybackPoll();
    _cancelNativeErrorGrace();
    _detachVideoListener();
    final retiring = _session;
    final sameGatewayWeb = retiring?.route == PlaybackRoute.directWebView &&
        _isGatewayChannel(ch) &&
        retiring?.web != null;

    if (sameGatewayWeb) {
      _video = null;
    } else {
      _session = null;
      _video = null;
      await _retireSession(retiring);
    }

    if (!mounted || token != _loadToken) {
      return;
    }

    if (skipRoutes != null) {
      _skipRoutes
        ..clear()
        ..addAll(skipRoutes);
    } else if (!forceWebView) {
      _skipRoutes.clear();
      _webFallbackTried = false;
      _autoRetryCount = 0;
      if (!sameGatewayWeb) {
        _playerSurfaceEpoch++;
      }
    }

    setState(() {
      _streamLoading = true;
      _showManualRetry = false;
      _useWebView = sameGatewayWeb || retiring?.useWebView == true;
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
        quality: _playbackQuality,
        forceWebView: forceWebView,
        skipRoutes: _skipRoutes,
      );
      if (!mounted || token != _loadToken) {
        await session.dispose();
        return;
      }

      _session = session;
      _useWebView = session.useWebView;

      if (session.useWebView) {
        final web = session.web!;
        if (kDebugMode) debugPrint('Washa playback route: ${session.route.name}');
        setState(() {
          _useWebView = true;
          _streamLoading = true;
          _showManualRetry = false;
          playing = true;
          _durationLabel = 'LIVE';
        });
        _attachWebViewMonitoring(web, token, session.route);
        if (session.route == PlaybackRoute.directWebView) {
          await ChannelPlaybackSession.loadDirectWebView(
            web,
            url: url,
            headers: playbackHttpHeaders(url),
          );
          if (!mounted || token != _loadToken) {
            await session.dispose();
            return;
          }
        }
        _armLoadWatchdog(token, ch, forceWebView: true);
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
      if (kDebugMode) debugPrint('Washa playback route: ${session.route.name}');
      setState(() {
        _video = video;
        _streamLoading = false;
        _showManualRetry = false;
        playing = true;
      });
      if (!video.value.isPlaying) {
        await video.play();
        if (mounted && token == _loadToken) {
          setState(() => playing = video.value.isPlaying);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Washa playback: $e');
      if (!mounted || token != _loadToken) {
        return;
      }
      _handlePlaybackFailure(forceWebView: forceWebView);
    }
  }

  Future<void> _togglePlayPause() async {
    if (_useWebView) {
      final web = _session?.web;
      if (web != null) {
        await _injectWebMediaControl(web);
        if (playing) {
          await web.runJavaScript(kWebMediaPauseJs);
        } else {
          await web.runJavaScript(kWebMediaPlayJs);
        }
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

  Future<void> _ensurePlaybackPlaying() async {
    if (_useWebView) {
      final web = _session?.web;
      if (web != null) {
        await _injectWebMediaControl(web);
        await web.runJavaScript(kWebMediaEnsurePlayJs);
      }
    } else {
      final v = _video;
      if (v != null && v.value.isInitialized && !v.value.isPlaying) {
        await v.play();
      }
    }
    if (mounted) setState(() => playing = true);
  }

  double _portraitBandHeight(BoxConstraints constraints) =>
      (constraints.maxWidth * 9 / 16).clamp(0.0, constraints.maxHeight * 0.52);

  Future<void> _restorePortraitAfterFullscreen() async {
    if (!mounted) return;
    await _applyFullscreenSystemUi(enter: false);
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    widget.onFullscreenChanged?.call(false);
    setState(() {
      fullscreen = false;
      _portraitSurfaceMounted = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (mounted) unawaited(_ensurePlaybackPlaying());
  }

  Future<void> _enterFullscreen() async {
    if (fullscreen || !mounted || _fullscreenBusy) return;
    if (_useWebView && _session?.web == null) return;
    final video = _video;
    if (!_useWebView && (video == null || !video.value.isInitialized)) return;

    _fullscreenBusy = true;
    try {
      setState(() => _portraitSurfaceMounted = false);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;

      await _applyFullscreenSystemUi(enter: true);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;

      widget.onFullscreenChanged?.call(true);
      setState(() => fullscreen = true);

      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: true,
          fullscreenDialog: true,
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) {
            return FullscreenPlayerPage(
              channelName: _current.name,
              useWebView: _useWebView,
              playing: playing,
              progress: progress,
              positionLabel: _positionLabel,
              durationLabel: _durationLabel,
              webController: _session?.web,
              videoController: _video,
              onPlayPause: _togglePlayPause,
              onSeek: _seekTo,
              onOpenLanguage: (ctx) => _showLanguageSheet(sheetContext: ctx),
              onOpenSettings: (ctx) => _showPlayerSettingsSheet(sheetContext: ctx),
            );
          },
        ),
      );

      if (mounted) await _restorePortraitAfterFullscreen();
    } finally {
      _fullscreenBusy = false;
    }
  }

  Future<void> _exitFullscreen({bool silent = false}) async {
    if (!fullscreen && !silent) return;
    if (_fullscreenBusy) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else if (!silent) {
      await _restorePortraitAfterFullscreen();
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_fullscreenBusy) return;
    if (fullscreen) {
      await _exitFullscreen();
    } else {
      await _enterFullscreen();
    }
  }

  String _webViewSurfaceKey(Channel c) {
    if (_isGatewayChannel(c) || _session?.route == PlaybackRoute.directWebView) {
      return 'wv-gateway-$_playerSurfaceEpoch';
    }
    return 'wv-${c.id}-$_playerSurfaceEpoch';
  }

  Widget _buildVideoLayer(Channel c, String heroUrl) {
    if (_useWebView && _session?.web != null) {
      if (!_portraitSurfaceMounted || _hideWebPlaybackSurface) {
        return const ColoredBox(color: Colors.black);
      }
      return ColoredBox(
        color: Colors.black,
        child: PinnedWebView(
          key: ValueKey(_webViewSurfaceKey(c)),
          controller: _session!.web!,
        ),
      );
    }

    final v = _video;
    if (v != null && v.value.isInitialized) {
      if (!_portraitSurfaceMounted) {
        return const ColoredBox(color: Colors.black);
      }
      return PinnedVideoPlayer(
        key: ValueKey('exo-${c.id}-$_playerSurfaceEpoch'),
        controller: v,
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
          _buildVideoLayer(c, heroUrl),
          if (!_showManualRetry && !_streamLoading && _video == null && !_useWebView && !_isGatewayChannel(c))
            Image.network(
              heroUrl,
              fit: BoxFit.cover,
              key: ValueKey('player-poster|${c.id}|$heroUrl'),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (_streamLoading && !_showManualRetry) const _PlaybackLoadingShade(),
          if (_showManualRetry)
            PlaybackUnavailableOverlay(
              onRetry: _manualRetryPlayback,
              onClose: immersive ? widget.onBack : null,
              isRetrying: _handlingPlaybackFailure,
            ),
          _buildPauseOverlay(controlsVisible, immersive),
          if (!_showManualRetry && !_streamLoading)
            _buildPlayerControls(controlsVisible, immersive),
        ],
      ),
    );
  }

  Widget _buildPauseOverlay(bool controlsVisible, bool immersive) {
    if (_showManualRetry || _streamLoading) return const SizedBox.shrink();

    final v = _video;
    if (v != null && v.value.isInitialized && !_useWebView) {
      return ListenableBuilder(
        listenable: v,
        builder: (context, _) {
          final value = v.value;
          final isLive = value.duration.inMilliseconds <= 0;
          if (isLive || value.isPlaying) return const SizedBox.shrink();
          return _pauseOverlayContent(controlsVisible, immersive);
        },
      );
    }

    if (!playing) return _pauseOverlayContent(controlsVisible, immersive);
    return const SizedBox.shrink();
  }

  Widget _pauseOverlayContent(bool controlsVisible, bool immersive) {
    return IgnorePointer(
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
    );
  }

  Widget _buildPlayerControls(bool controlsVisible, bool immersive) {
    final v = _video;
    if (v != null && v.value.isInitialized && !_useWebView) {
      return ListenableBuilder(
        listenable: v,
        builder: (context, _) {
          final value = v.value;
          final durMs = value.duration.inMilliseconds;
          final pos = value.position;
          final prog = durMs > 0 ? (pos.inMilliseconds / durMs).clamp(0.0, 1.0) : 0.0;
          final durLabel = durMs > 0 ? _formatDuration(value.duration) : 'LIVE';
          final posLabel = durMs > 0 ? _formatDuration(pos) : _positionLabel;
          return PlayerControls(
            playing: value.isPlaying,
            progress: prog,
            positionLabel: posLabel,
            durationLabel: durLabel,
            visible: controlsVisible,
            isFullscreen: false,
            onUserInteraction: immersive ? _showImmersiveControls : null,
            onOpenLanguage: () => unawaited(_showLanguageSheet()),
            onOpenSettings: () => unawaited(_showPlayerSettingsSheet()),
            onToggleFullscreen: () => unawaited(_toggleFullscreen()),
            onPlay: () => unawaited(_togglePlayPause()),
            onSeek: (seek) => unawaited(_seekTo(seek)),
          );
        },
      );
    }

    return PlayerControls(
      playing: playing,
      progress: progress,
      positionLabel: _positionLabel,
      durationLabel: _durationLabel,
      visible: controlsVisible,
      isFullscreen: false,
      onUserInteraction: immersive ? _showImmersiveControls : null,
      onOpenLanguage: () => unawaited(_showLanguageSheet()),
      onOpenSettings: () => unawaited(_showPlayerSettingsSheet()),
      onToggleFullscreen: () => unawaited(_toggleFullscreen()),
      onPlay: () => unawaited(_togglePlayPause()),
      onSeek: (seek) => unawaited(_seekTo(seek)),
    );
  }

  Widget _buildHostedPlayerStack(Channel c, String heroUrl, {required bool immersive}) {
    return KeyedSubtree(
      key: _playerHostKey,
      child: _buildPlayerStack(c, heroUrl, immersive: immersive),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final bandHeight = _portraitBandHeight(constraints);
        final playerHost = _buildHostedPlayerStack(c, heroUrl, immersive: false);

        return PopScope(
          canPop: !fullscreen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && fullscreen) Navigator.of(context).pop();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: fullscreen,
                child: Column(
                  children: [
                    SizedBox(height: bandHeight),
                      Container(
                        color: const Color(0xE6000000),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  text: 'Unaangalia: ',
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
                              onTap: () =>
                                  cc.premium && !widget.premium ? widget.onOpenSubscription() : widget.onOpenPlayer(cc),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: bandHeight,
                child: RepaintBoundary(
                  child: Material(
                    color: Colors.black,
                    child: playerHost,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaybackLoadingShade extends StatelessWidget {
  const _PlaybackLoadingShade();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFEF4444)),
      ),
    );
  }
}
