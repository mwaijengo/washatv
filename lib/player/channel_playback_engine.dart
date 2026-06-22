import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/channel.dart';
import '../register_webview_stub.dart'
    if (dart.library.js_interop) '../register_webview_web.dart' as wv_platform;
import 'playback_http_headers.dart';
import 'playback_quality.dart';
import 'php_gateway_js.dart';
import 'shaka_player_html.dart';
import 'stream_url_classifier.dart';

/// Thrown when native player setup exceeds [kNativeInitTimeout].
class PlaybackInitTimeout implements Exception {
  const PlaybackInitTimeout();
}

/// Native HLS/DASH init budget before WebView fallback.
const Duration kNativeInitTimeout = Duration(seconds: 10);

/// Which playback stack handles a stream.
enum PlaybackRoute {
  /// ExoPlayer (Android) / AVPlayer (iOS) via `video_player`.
  nativeExo,

  /// Shaka Player inside WebView — DASH, DRM, Okoa bando HLS.
  shakaWebView,

  /// Load gateway URL directly — `.php` embed pages.
  directWebView,
}

/// Result of starting playback for one channel stream URL.
class ChannelPlaybackSession {
  ChannelPlaybackSession._({
    this.video,
    this.web,
    required this.route,
  });

  final VideoPlayerController? video;
  final WebViewController? web;
  final PlaybackRoute route;

  bool get useWebView => route != PlaybackRoute.nativeExo;

  bool get isReady => useWebView ? web != null : (video?.value.isInitialized ?? false);

  static Future<ChannelPlaybackSession> open({
    required String streamUrl,
    ChannelDrm drm = ChannelDrm.none,
    PlaybackQuality quality = PlaybackQuality.okoaBando,
    bool forceWebView = false,
  }) async {
    final url = streamUrl.trim();
    if (url.isEmpty) {
      throw StateError('empty_stream');
    }

    final routes = _playbackRoutePlan(
      url: url,
      drm: drm,
      quality: quality,
      forceWebView: forceWebView,
    );

    Object? lastError;
    for (final route in routes) {
      try {
        switch (route) {
          case PlaybackRoute.shakaWebView:
            if (!_canUseWebView) continue;
            final web = await _openShakaWebView(url, drm: drm, quality: quality);
            return ChannelPlaybackSession._(web: web, route: route);
          case PlaybackRoute.directWebView:
            if (!_canUseWebView) continue;
            final web = await _openDirectWebView(url);
            return ChannelPlaybackSession._(web: web, route: route);
          case PlaybackRoute.nativeExo:
            final video = await _openNativeVideo(url);
            return ChannelPlaybackSession._(video: video, route: route);
        }
      } catch (e) {
        lastError = e;
        if (kDebugMode) debugPrint('Washa route $route failed: $e');
      }
    }

    if (lastError != null) throw lastError;
    throw StateError('no_playback_route');
  }

  /// Ordered routes to try for a stream URL.
  @visibleForTesting
  static List<PlaybackRoute> playbackRoutePlan({
    required String url,
    ChannelDrm drm = ChannelDrm.none,
    PlaybackQuality quality = PlaybackQuality.okoaBando,
    bool forceWebView = false,
  }) =>
      _playbackRoutePlan(url: url, drm: drm, quality: quality, forceWebView: forceWebView);

  static List<PlaybackRoute> _playbackRoutePlan({
    required String url,
    ChannelDrm drm = ChannelDrm.none,
    required PlaybackQuality quality,
    required bool forceWebView,
  }) {
    if (forceWebView) {
      return _webViewFallbackChain(url, drm, quality);
    }

    if (drm != ChannelDrm.none) {
      return [PlaybackRoute.shakaWebView, PlaybackRoute.directWebView];
    }

    if (StreamUrlClassifier.isPhpLikeUrl(url)) {
      return [PlaybackRoute.directWebView, PlaybackRoute.shakaWebView];
    }

    if (StreamUrlClassifier.isLikelyDash(url)) {
      return [PlaybackRoute.shakaWebView, PlaybackRoute.directWebView];
    }

    if (quality.dataSaverEnabled && StreamUrlClassifier.isLikelyHls(url)) {
      return [
        PlaybackRoute.shakaWebView,
        PlaybackRoute.nativeExo,
        PlaybackRoute.directWebView,
      ];
    }

    if (StreamUrlClassifier.isLikelyHls(url) ||
        StreamUrlClassifier.hasObviousMp4(url) ||
        StreamUrlClassifier.hasObviousTs(url)) {
      return [
        PlaybackRoute.nativeExo,
        PlaybackRoute.shakaWebView,
        PlaybackRoute.directWebView,
      ];
    }

    return [
      PlaybackRoute.nativeExo,
      PlaybackRoute.shakaWebView,
      PlaybackRoute.directWebView,
    ];
  }

  static List<PlaybackRoute> _webViewFallbackChain(
    String url,
    ChannelDrm drm,
    PlaybackQuality quality,
  ) {
    if (StreamUrlClassifier.isPhpLikeUrl(url)) {
      return [PlaybackRoute.directWebView, PlaybackRoute.shakaWebView];
    }
    if (drm != ChannelDrm.none || StreamUrlClassifier.isLikelyDash(url)) {
      return [PlaybackRoute.shakaWebView, PlaybackRoute.directWebView];
    }
    if (quality.dataSaverEnabled && StreamUrlClassifier.isLikelyHls(url)) {
      return [PlaybackRoute.shakaWebView, PlaybackRoute.directWebView];
    }
    return [PlaybackRoute.shakaWebView, PlaybackRoute.directWebView, PlaybackRoute.nativeExo];
  }

  static bool get _canUseWebView => wv_platform.isWebViewPlatformReady;

  static VideoFormat? _formatHint(String url) {
    if (StreamUrlClassifier.isLikelyHls(url)) return VideoFormat.hls;
    if (StreamUrlClassifier.isLikelyDash(url)) return VideoFormat.dash;
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

  static Future<WebViewController> _openShakaWebView(
    String url, {
    required ChannelDrm drm,
    required PlaybackQuality quality,
  }) async {
    final controller = WebViewController();
    final headers = playbackHttpHeaders(url);
    final parsed = Uri.parse(url);
    final baseUrl = '${parsed.scheme}://${parsed.authority}/';

    await Future.wait([
      controller.setJavaScriptMode(JavaScriptMode.unrestricted),
      controller.setUserAgent(kBrowserPlaybackUserAgent),
      controller.setBackgroundColor(Colors.black),
      controller.enableZoom(false),
    ]);

    final html = buildShakaPlayerHtml(
      streamUrl: url,
      drm: drm,
      maxHeight: quality.effectiveMaxHeight,
      requestHeaders: headers,
    );

    await controller.loadHtmlString(html, baseUrl: baseUrl);
    return controller;
  }

  static Future<WebViewController> _openDirectWebView(String url) async {
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
