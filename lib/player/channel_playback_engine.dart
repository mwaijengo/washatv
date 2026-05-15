import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'playback_http_headers.dart';
import 'php_gateway_js.dart';
import 'stream_url_classifier.dart';

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
    bool forceWebView = false,
  }) async {
    final url = streamUrl.trim();
    if (url.isEmpty) {
      throw StateError('empty_stream');
    }

    final preferWeb = forceWebView || _shouldUseWebView(url);
    if (preferWeb) {
      final web = await _openWebView(url);
      return ChannelPlaybackSession._(web: web, useWebView: true);
    }

    try {
      final video = await _openNativeVideo(url);
      return ChannelPlaybackSession._(video: video, useWebView: false);
    } catch (e) {
      if (kIsWeb && !forceWebView) {
        final web = await _openWebView(url);
        return ChannelPlaybackSession._(web: web, useWebView: true);
      }
      rethrow;
    }
  }

  static bool _shouldUseWebView(String url) {
    if (!StreamUrlClassifier.isPhpLikeUrl(url)) return false;
    return !StreamUrlClassifier.hasObviousM3u8(url) &&
        !StreamUrlClassifier.hasObviousMpd(url) &&
        !StreamUrlClassifier.hasObviousTs(url);
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
    await controller.initialize();
    await controller.setLooping(false);
    return controller;
  }

  static Future<WebViewController> _openWebView(String url) async {
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setUserAgent(kBrowserPlaybackUserAgent);
    await controller.setBackgroundColor(Colors.black);
    await controller.enableZoom(false);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) => controller.runJavaScript(kPhpGatewayRecoveryJs),
      ),
    );
    final headers = playbackHttpHeaders(url);
    await controller.loadRequest(
      Uri.parse(url),
      headers: Map<String, String>.from(headers),
    );
    return controller;
  }

  Future<void> dispose() async {
    await video?.dispose();
  }
}