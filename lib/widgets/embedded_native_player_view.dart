import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gateway player on Android portrait — WebView on Activity overlay (not PlatformView).
class EmbeddedNativePlayerView extends StatefulWidget {
  const EmbeddedNativePlayerView({
    super.key,
    required this.url,
    required this.headers,
    this.onPlaybackError,
    this.onPlaybackStarted,
    this.onAttached,
  });

  final String url;
  final Map<String, String> headers;
  final VoidCallback? onPlaybackError;
  final VoidCallback? onPlaybackStarted;
  final VoidCallback? onAttached;

  @override
  State<EmbeddedNativePlayerView> createState() => EmbeddedNativePlayerViewState();
}

class EmbeddedNativePlayerViewState extends State<EmbeddedNativePlayerView>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.washatv/embedded_player');
  static const _eventsChannel = MethodChannel('com.washatv/embedded_player_events');

  final _hostKey = GlobalKey();
  bool _attached = false;
  int _attachAttempts = 0;
  bool _attachFailed = false;
  Timer? _attachRetryTimer;
  static const _maxAttachAttempts = 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _eventsChannel.setMethodCallHandler(_onNativeEvent);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncAttach());
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _syncBounds();
  }

  Future<void> _onNativeEvent(MethodCall call) async {
    switch (call.method) {
      case 'onPlaying':
        widget.onPlaybackStarted?.call();
      case 'onError':
        widget.onPlaybackError?.call();
    }
  }

  static const _controlBarReserve = 48.0;

  Map<String, int>? _boundsPx() {
    final box = _hostKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final reservePx = (_controlBarReserve * dpr).round();
    final heightPx = (box.size.height * dpr).round() - reservePx;
    if (heightPx < 2) return null;
    return {
      'left': (offset.dx * dpr).round(),
      'top': (offset.dy * dpr).round(),
      'width': (box.size.width * dpr).round(),
      'height': heightPx,
    };
  }

  void _scheduleAttachRetry() {
    if (_attachFailed || _attachAttempts >= _maxAttachAttempts) return;
    _attachRetryTimer?.cancel();
    _attachRetryTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && !_attached && !_attachFailed) _syncAttach();
    });
  }

  Future<void> _syncAttach() async {
    if (!mounted || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_attachFailed) return;
    final bounds = _boundsPx();
    if (bounds == null || bounds['width']! < 2 || bounds['height']! < 2) {
      _scheduleAttachRetry();
      return;
    }
    try {
      if (_attached) {
        await _channel.invokeMethod<void>('updateBounds', bounds);
      } else {
        _attachAttempts++;
        await _channel.invokeMethod<void>('attach', <String, dynamic>{
          'url': widget.url,
          'headersJson': widget.headers.isEmpty ? '' : jsonEncode(widget.headers),
          ...bounds,
        });
        _attached = true;
        widget.onAttached?.call();
      }
    } on MissingPluginException catch (e) {
      debugPrint('EmbeddedNativePlayer: native plugin missing ($e). Stop app and run flutter run again.');
      if (_attachAttempts >= _maxAttachAttempts) {
        _attachFailed = true;
        widget.onPlaybackError?.call();
      } else {
        _scheduleAttachRetry();
      }
    } catch (e, st) {
      debugPrint('EmbeddedNativePlayer attach failed: $e\n$st');
      if (_attachAttempts >= _maxAttachAttempts) {
        _attachFailed = true;
        widget.onPlaybackError?.call();
      } else {
        _scheduleAttachRetry();
      }
    }
  }

  Future<void> _syncBounds() async {
    if (!_attached || !mounted) return;
    final bounds = _boundsPx();
    if (bounds == null) return;
    try {
      await _channel.invokeMethod<void>('updateBounds', bounds);
    } catch (_) {}
  }

  Future<void> pauseForHandoff() async {
    if (!_attached) return;
    try {
      await _channel.invokeMethod<void>('pause');
    } catch (_) {}
  }

  Future<void> resumeAfterHandoff() async {
    if (!_attached) return;
    try {
      await _channel.invokeMethod<void>('resume');
      await _syncBounds();
    } catch (_) {}
  }

  @override
  void dispose() {
    _attachRetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _eventsChannel.setMethodCallHandler(null);
    if (_attached) {
      _attached = false;
      unawaited(_channel.invokeMethod<void>('detach'));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(key: _hostKey),
    );
  }
}
