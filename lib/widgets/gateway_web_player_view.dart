import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'stable_gateway_host.dart';

/// Android gateway web player — native WebView with headers for PHP/HTML gateways.
class GatewayWebPlayerView extends StatefulWidget {
  const GatewayWebPlayerView({
    super.key,
    required this.url,
    required this.headers,
    this.canvasSize,
    this.onPlaybackError,
    this.onPlaybackStarted,
  });

  final String url;
  final Map<String, String> headers;
  final Size? canvasSize;
  final VoidCallback? onPlaybackError;
  final VoidCallback? onPlaybackStarted;

  @override
  State<GatewayWebPlayerView> createState() => GatewayWebPlayerViewState();
}

class GatewayWebPlayerViewState extends State<GatewayWebPlayerView>
    with AutomaticKeepAliveClientMixin {
  static const _viewType = 'com.washatv/gateway_web_player';
  static const _channel = MethodChannel('com.washatv/gateway_web_player');

  static const _gestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{};

  int? _viewId;
  late final Widget _platformView = AndroidView(
    viewType: _viewType,
    layoutDirection: TextDirection.ltr,
    gestureRecognizers: _gestureRecognizers,
    creationParams: <String, dynamic>{
      'url': widget.url,
      'headersJson': widget.headers.isEmpty ? '' : jsonEncode(widget.headers),
      'embedded': true,
    },
    creationParamsCodec: const StandardMessageCodec(),
    onPlatformViewCreated: _onPlatformViewCreated,
  );

  @override
  bool get wantKeepAlive => true;

  void _onPlatformViewCreated(int id) {
    _viewId = id;
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _channel.setMethodCallHandler(_onNativeCall);
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map) return;
    final errViewId = args['viewId'];
    if (_viewId != null && errViewId != _viewId) return;

    switch (call.method) {
      case 'onPlaying':
        widget.onPlaybackStarted?.call();
      case 'onError':
        widget.onPlaybackError?.call();
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> pauseForHandoff() async {
    final id = _viewId;
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>('pause', {'viewId': id});
    } catch (_) {}
  }

  Future<void> resumeAfterHandoff() async {
    final id = _viewId;
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>('resume', {'viewId': id});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }

    return StableGatewayHost(
      canvasSize: widget.canvasSize,
      child: _platformView,
    );
  }
}
