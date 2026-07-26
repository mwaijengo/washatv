import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../player/playback_helpers.dart';
import '../player/playback_http_headers.dart';
import '../player/flutter_playback_mode.dart';
import '../player/stream_url_utils.dart';
import '../services/player_engine.dart';
import '../services/remote_config_service.dart';

export 'playback_helpers.dart';

Map<String, dynamic> channelDataFor(Channel channel) {
  final ck = channel.drmClearKey?.trim() ?? '';
  return {
    'streamUrl': channel.streamUrl,
    'stream_url': channel.streamUrl,
    'drmType': _drmLabel(channel.drm),
    'drm_type': _drmLabel(channel.drm),
    if (ck.isNotEmpty) ...{
      'drmClearKey': ck,
      'drm_clear_key': ck,
      'clearKeyHex': ck,
    },
    'audioLanguage': 'sw',
    'audio_language': 'sw',
  };
}

String _drmLabel(ChannelDrm drm) {
  switch (drm) {
    case ChannelDrm.clearkey:
      return 'CLEARKEY';
    case ChannelDrm.widevine:
      return 'WIDEVINE';
    case ChannelDrm.none:
      return 'NONE';
  }
}

/// Backward-compatible aliases used by [PlayerScreen].
String extractClearKeyPayload(Map<String, dynamic>? channelData) =>
    clearKeyPayloadFromData(channelData);

String extractPlaybackToken(Map<String, dynamic>? channelData) =>
    playbackTokenFromData(channelData);

String extractAudioLanguage(Map<String, dynamic>? channelData) =>
    playbackAudioLanguageFromData(channelData);

Map<String, String> extractPlaybackHeaders(
  Map<String, dynamic>? channelData,
  String url,
) {
  final fromApi = playbackHeadersFromData(channelData);
  if (fromApi.isNotEmpty) {
    return mergePlaybackHeaders(url, fromApi);
  }
  return playbackHttpHeaders(url);
}

Map<String, String> mergedPlaybackHeaders({
  required String url,
  required Map<String, dynamic>? channelData,
}) {
  final fromApi = playbackHeadersFromData(channelData);
  final merged = mergePlaybackHeaders(url, fromApi.isEmpty ? null : fromApi);
  final token = extractPlaybackToken(channelData);
  if (token.isNotEmpty && !merged.keys.any((k) => k.toLowerCase() == 'authorization')) {
    merged['Authorization'] = 'Bearer $token';
  }
  return merged;
}

FlutterPlaybackMode resolveFlutterPlaybackMode(String url, {ChannelDrm drm = ChannelDrm.none}) {
  final gatewayPage = isGatewayUrl(url) || useWebViewForUrl(url);
  final directManifest = RegExp(r'\.(m3u8?|mpd)(\?|#|$)', caseSensitive: false).hasMatch(url);

  // PHP/HTML gateways on mobile use native WebView — not Shaka (avoids error 6001).
  if (gatewayPage && !directManifest && !kIsWeb) {
    return FlutterPlaybackMode.mediaKit;
  }

  final engine = PlayerEngine.resolveInAppEngine(
    RemoteConfigService.playerConfig.preferredEngine,
    gatewayPage: gatewayPage,
  );
  final mode = PlayerEngine.flutterModeFor(engine);
  if (mode != null) {
    if (gatewayPage &&
        mode != FlutterPlaybackMode.webEmbedded &&
        mode != FlutterPlaybackMode.shaka) {
      return kIsWeb ? FlutterPlaybackMode.webEmbedded : FlutterPlaybackMode.shaka;
    }
    if (gatewayPage && mode == FlutterPlaybackMode.webEmbedded && !kIsWeb) {
      return FlutterPlaybackMode.shaka;
    }
    return mode;
  }
  if (kIsWeb) return FlutterPlaybackMode.webEmbedded;
  if (gatewayPage) return FlutterPlaybackMode.shaka;
  if (drm == ChannelDrm.clearkey || drm == ChannelDrm.widevine) {
    return FlutterPlaybackMode.shaka;
  }
  return FlutterPlaybackMode.mediaKit;
}
