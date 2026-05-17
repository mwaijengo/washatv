import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/channel.dart';
import '../register_webview_stub.dart'
    if (dart.library.js_interop) '../register_webview_web.dart' as wv_platform;
import 'playback_http_headers.dart';
import 'php_gateway_js.dart';
import 'stream_url_classifier.dart';

/// Thrown when native player setup exceeds [kNativeInitTimeout].
class PlaybackInitTimeout implements Exception {
  const PlaybackInitTimeout();
}

/// Native HLS/DASH init budget before WebView fallback.
const Duration kNativeInitTimeout = Duration(seconds: 8);

/// Result of starting playback for one channel stream URL.
class ChannelPlaybackSession {
  ChannelPlaybackSession._({
    this.video,
    this.web,
    required this.useWebView,
  });

  final VideoPlayerController? video;
  final WebViewController? web;
  final bool useWebView;

  bool get isReady => useWebView ? web != null : (video?.value.isInitialized ?? false);

  static Future<ChannelPlaybackSession> open({
    required String streamUrl,
    ChannelDrm drm = ChannelDrm.none,
    bool forceWebView = false,
  }) async {
    final url = streamUrl.trim();
    if (url.isEmpty) {
      throw StateError('empty_stream');
    }

    final preferWeb = _canUseWebView && (forceWebView || _shouldUseWebView(url, drm));
    if (preferWeb) {
      final web = await _openWebView(url);
      return ChannelPlaybackSession._(web: web, useWebView: true);
    }

    try {
      final video = await _openNativeVideo(url);
      return ChannelPlaybackSession._(video: video, useWebView: false);
    } catch (e) {
      if (_canUseWebView && !forceWebView) {
        final web = await _openWebView(url);
        return ChannelPlaybackSession._(web: web, useWebView: true);
      }
      rethrow;
    }
  }

  static bool get _canUseWebView => wv_platform.isWebViewPlatformReady;

  static bool _shouldUseWebView(String url, ChannelDrm drm) {
    if (drm == ChannelDrm.clearkey || drm == ChannelDrm.widevine) return true;
    if (StreamUrlClassifier.hasObviousMpd(url)) return true;
    // PHP gateways need the browser player (tokens, redirects, embedded players).
    if (StreamUrlClassifier.isPhpLikeUrl(url)) return true;
    return false;
  }

  static VideoFormat? _formatHint(String url) {
    if (StreamUrlClassifier.hasObviousM3u8(url)) return VideoFormat.hls;
    if (StreamUrlClassifier.hasObviousMpd(url)) return VideoFormat.dash;
    return null;
  }

  static Future<VideoPlayerController> _openNativeVideo(String url) async {
    final uri = Uri.parse(url);
    final headers = playbackHttpHeaders(url);
    final hint = _formatHint(url);
    final controller = hint != null
        ? VideoPlayerController.networkUrl(uri, formatHint: hint, httpHeaders: headers)
        : VideoPlayerController.networkUrl(uri, httpHeaders: headers);

    await controller.initialize().timeout(
      kNativeInitTimeout,
      onTimeout: () {
        controller.dispose();
        throw const PlaybackInitTimeout();
      },
    );
    unawaited(controller.setLooping(false));
    return controller;
  }

  static Future<WebViewController> _openWebView(String url) async {
    final controller = WebViewController();
    final headers = playbackHttpHeaders(url);

    await Future.wait([
      controller.setJavaScriptMode(JavaScriptMode.unrestricted),
      controller.setUserAgent(kBrowserPlaybackUserAgent),
      controller.setBackgroundColor(Colors.black),
      controller.enableZoom(false),
    ]);

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) => controller.runJavaScript(kPhpGatewayRecoveryJs),
        onPageFinished: (_) => controller.runJavaScript(kPhpGatewayRecoveryJs),
      ),
    );

    unawaited(
      controller.loadRequest(
        Uri.parse(url),
        headers: Map<String, String>.from(headers),
      ),
    );
    return controller;
  }

  Future<void> dispose() async {
    await video?.dispose();
  }
}
