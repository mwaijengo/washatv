import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/channel.dart';
import '../register_webview_stub.dart'
    if (dart.library.js_interop) '../register_webview_web.dart' as wv_platform;
import 'fast_hls_player_html.dart';
import 'playback_http_headers.dart';
import 'playback_quality.dart';
import 'shaka_player_html.dart';
import 'stream_url_classifier.dart';
import 'stream_url_resolver.dart';

/// Thrown when native player setup exceeds [kNativeInitTimeout].
class PlaybackInitTimeout implements Exception {
  const PlaybackInitTimeout();
}

/// Native HLS init budget before WebView fallback.
const Duration kNativeInitTimeout = Duration(seconds: 5);

/// Which playback stack handles a stream.
enum PlaybackRoute {
  /// ExoPlayer (Android) / AVPlayer (iOS) via `video_player`.
  nativeExo,

  /// Native `<video src>` for HLS — fast WebView fallback without Shaka CDN.
  fastHlsWebView,

  /// Shaka Player inside WebView — DASH, DRM, 360p cap fallback.
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
    Set<PlaybackRoute> skipRoutes = const {},
  }) async {
    final gatewayUrl = streamUrl.trim();
    if (gatewayUrl.isEmpty) {
      throw StateError('empty_stream');
    }

    final resolved = await StreamUrlResolver.resolve(gatewayUrl);
    if (kDebugMode) {
      debugPrint(
        'Washa resolve: embed=${resolved.isGatewayEmbed} '
        'play=${resolved.playbackUrl}',
      );
    }

    final routes = _playbackRoutePlan(
      resolved: resolved,
      drm: drm,
      quality: quality,
      forceWebView: forceWebView,
    ).where((route) => !skipRoutes.contains(route));

    Object? lastError;
    for (final route in routes) {
      final playUrl = route == PlaybackRoute.directWebView ? gatewayUrl : resolved.playbackUrl;
      final headers = resolved.headers.isNotEmpty
          ? resolved.headers
          : playbackHttpHeaders(playUrl);
      try {
        switch (route) {
          case PlaybackRoute.shakaWebView:
            if (!_canUseWebView) continue;
            final web = await _openShakaWebView(playUrl, drm: drm, quality: quality, headers: headers);
            return ChannelPlaybackSession._(web: web, route: route);
          case PlaybackRoute.fastHlsWebView:
            if (!_canUseWebView) continue;
            final web = await _openFastHlsWebView(playUrl, headers: headers);
            return ChannelPlaybackSession._(web: web, route: route);
          case PlaybackRoute.directWebView:
            if (!_canUseWebView) continue;
            final web = await _openDirectWebView(gatewayUrl, headers: headers);
            return ChannelPlaybackSession._(web: web, route: route);
          case PlaybackRoute.nativeExo:
            final video = await _openNativeVideo(playUrl, headers: headers);
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

  /// Ordered routes to try for a stream URL (before [StreamUrlResolver] probing).
  static List<PlaybackRoute> playbackRoutePlan({
    required String url,
    ChannelDrm drm = ChannelDrm.none,
    PlaybackQuality quality = PlaybackQuality.okoaBando,
    bool forceWebView = false,
  }) =>
      _playbackRoutePlan(
        resolved: ResolvedStream(
          gatewayUrl: url,
          playbackUrl: url,
          isGatewayEmbed: StreamUrlClassifier.isPhpLikeUrl(url),
        ),
        drm: drm,
        quality: quality,
        forceWebView: forceWebView,
      );

  /// ExoPlayer first; gateway embed only when manifest cannot be extracted.
  static List<PlaybackRoute> _playbackRoutePlan({
    required ResolvedStream resolved,
    ChannelDrm drm = ChannelDrm.none,
    required PlaybackQuality quality,
    required bool forceWebView,
  }) {
    final mediaUrl = resolved.playbackUrl;
    final isEmbed = resolved.isGatewayEmbed;

    if (forceWebView) {
      return _webViewFallbackChain(resolved, drm, quality);
    }

    if (drm != ChannelDrm.none) {
      if (isEmbed) return [PlaybackRoute.shakaWebView, PlaybackRoute.directWebView];
      return [
        PlaybackRoute.shakaWebView,
        PlaybackRoute.fastHlsWebView,
        PlaybackRoute.directWebView,
      ];
    }

    // Unresolved PHP gateway — WebView embed only (Exo cannot play .php / 403).
    if (isEmbed) {
      return [PlaybackRoute.directWebView];
    }

    if (StreamUrlClassifier.isLikelyDash(mediaUrl)) {
      return [
        PlaybackRoute.nativeExo,
        PlaybackRoute.shakaWebView,
        PlaybackRoute.directWebView,
      ];
    }

    if (StreamUrlClassifier.isLikelyHls(mediaUrl) ||
        StreamUrlClassifier.hasObviousMp4(mediaUrl) ||
        StreamUrlClassifier.hasObviousTs(mediaUrl)) {
      return [
        PlaybackRoute.nativeExo,
        PlaybackRoute.fastHlsWebView,
        if (quality.dataSaverEnabled) PlaybackRoute.shakaWebView,
        PlaybackRoute.directWebView,
      ];
    }

    return [
      PlaybackRoute.nativeExo,
      PlaybackRoute.fastHlsWebView,
      PlaybackRoute.shakaWebView,
      PlaybackRoute.directWebView,
    ];
  }

  static List<PlaybackRoute> _webViewFallbackChain(
    ResolvedStream resolved,
    ChannelDrm drm,
    PlaybackQuality quality,
  ) {
    if (resolved.isGatewayEmbed) {
      return [PlaybackRoute.directWebView];
    }
    if (drm != ChannelDrm.none || StreamUrlClassifier.isLikelyDash(resolved.playbackUrl)) {
      return [PlaybackRoute.shakaWebView, PlaybackRoute.directWebView];
    }
    if (StreamUrlClassifier.isLikelyHls(resolved.playbackUrl)) {
      return [
        PlaybackRoute.fastHlsWebView,
        if (quality.dataSaverEnabled) PlaybackRoute.shakaWebView,
        PlaybackRoute.directWebView,
      ];
    }
    return [
      PlaybackRoute.fastHlsWebView,
      PlaybackRoute.shakaWebView,
      PlaybackRoute.directWebView,
    ];
  }

  static bool get _canUseWebView => wv_platform.isWebViewPlatformReady;

  /// Reused for PHP gateway channel switches — avoids new PlatformViews on Huawei.
  static WebViewController? _gatewayWeb;

  /// Drop cached gateway WebView when leaving the player.
  static void clearGatewayWeb() {
    _gatewayWeb = null;
  }

  static VideoFormat? _formatHint(String url) {
    if (StreamUrlClassifier.isLikelyHls(url)) return VideoFormat.hls;
    if (StreamUrlClassifier.isLikelyDash(url)) return VideoFormat.dash;
    return null;
  }

  static Future<VideoPlayerController> _openNativeVideo(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    clearGatewayWeb();
    final uri = Uri.parse(url);
    final requestHeaders = headers.isNotEmpty ? headers : playbackHttpHeaders(url);
    final hint = _formatHint(url);
    final controller = hint != null
        ? VideoPlayerController.networkUrl(uri, formatHint: hint, httpHeaders: requestHeaders)
        : VideoPlayerController.networkUrl(uri, httpHeaders: requestHeaders);

    await controller.initialize().timeout(
      kNativeInitTimeout,
      onTimeout: () {
        controller.dispose();
        throw const PlaybackInitTimeout();
      },
    );
    await controller.setLooping(false);
    await controller.play();
    return controller;
  }

  static Future<WebViewController> _createWebView() async {
    final controller = WebViewController();
    await Future.wait([
      controller.setJavaScriptMode(JavaScriptMode.unrestricted),
      controller.setUserAgent(kBrowserPlaybackUserAgent),
      controller.setBackgroundColor(Colors.black),
      controller.enableZoom(false),
    ]);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final android = controller.platform;
      if (android is AndroidWebViewController) {
        await android.setMediaPlaybackRequiresUserGesture(false);
      }
    }
    return controller;
  }

  static Future<WebViewController> _openFastHlsWebView(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    clearGatewayWeb();
    final controller = await _createWebView();
    final requestHeaders = headers.isNotEmpty ? headers : playbackHttpHeaders(url);
    final parsed = Uri.parse(url);
    final baseUrl = '${parsed.scheme}://${parsed.authority}/';
    final html = buildFastHlsPlayerHtml(streamUrl: url, requestHeaders: requestHeaders);
    await controller.loadHtmlString(html, baseUrl: baseUrl);
    return controller;
  }

  static Future<WebViewController> _openShakaWebView(
    String url, {
    required ChannelDrm drm,
    required PlaybackQuality quality,
    Map<String, String> headers = const {},
  }) async {
    clearGatewayWeb();
    final controller = await _createWebView();
    await loadShakaWebView(
      controller,
      url: url,
      drm: drm,
      quality: quality,
      headers: headers,
    );
    return controller;
  }

  /// Reload Shaka HTML on an existing controller (quality toggle).
  static Future<void> loadShakaWebView(
    WebViewController web, {
    required String url,
    required ChannelDrm drm,
    required PlaybackQuality quality,
    Map<String, String> headers = const {},
  }) async {
    final requestHeaders = headers.isNotEmpty ? headers : playbackHttpHeaders(url);
    final parsed = Uri.parse(url);
    final baseUrl = '${parsed.scheme}://${parsed.authority}/';

    final html = buildShakaPlayerHtml(
      streamUrl: url,
      drm: drm,
      maxHeight: quality.effectiveMaxHeight,
      requestHeaders: requestHeaders,
    );

    await web.loadHtmlString(html, baseUrl: baseUrl);
  }

  static Future<WebViewController> _openDirectWebView(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final controller = _gatewayWeb ?? await _createWebView();
    _gatewayWeb = controller;
    return controller;
  }

  /// Load a PHP gateway page after [NavigationDelegate] is attached.
  static Future<void> loadDirectWebView(
    WebViewController web, {
    required String url,
    Map<String, String> headers = const {},
  }) async {
    final requestHeaders = headers.isNotEmpty ? headers : playbackHttpHeaders(url);
    await web.loadRequest(
      Uri.parse(url),
      headers: Map<String, String>.from(requestHeaders),
    );
  }

  Future<void> dispose() async {
    await video?.dispose();
  }
}
