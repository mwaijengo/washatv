import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../player/playback_http_headers.dart';
import '../player/flutter_playback_mode.dart';
import '../player/stream_url_utils.dart';
import '../services/player_engine.dart';
import '../services/remote_config_service.dart';

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

String extractClearKeyPayload(Map<String, dynamic>? channelData) {
  if (channelData == null) return '';
  final dynamic raw = channelData['drmClearKey'] ??
      channelData['drm_clear_key'] ??
      channelData['clearKeyHex'] ??
      channelData['clear_keys'] ??
      channelData['clearKeys'];
  if (raw == null) return '';
  if (raw is String) return raw.trim();
  try {
    return jsonEncode(raw);
  } catch (_) {
    return raw.toString();
  }
}

String normalizedDrmType(
  Map<String, dynamic>? channelData,
  String clearPayload,
  String playbackUrl,
) {
  var d = (channelData?['drmType'] ?? channelData?['drm_type'] ?? 'NONE').toString().trim();
  if (d.isEmpty) d = 'NONE';
  var u = d.toUpperCase().replaceAll(RegExp(r'[\s\-]+'), '_');
  if (u == 'CLEAR_KEY') u = 'CLEARKEY';
  if (u != 'NONE') return u;
  final ul = playbackUrl.toLowerCase();
  if (clearPayload.isNotEmpty &&
      (ul.contains('.mpd') || ul.contains('.m3u8') || ul.contains('.m3u'))) {
    return 'CLEARKEY';
  }
  return 'NONE';
}

String extractPlaybackToken(Map<String, dynamic>? channelData) {
  if (channelData == null) return '';
  final raw = channelData['token'] ??
      channelData['streamToken'] ??
      channelData['stream_token'] ??
      channelData['authToken'] ??
      channelData['auth_token'];
  return raw?.toString().trim() ?? '';
}

Map<String, String> extractPlaybackHeaders(Map<String, dynamic>? channelData, String url) {
  final fromApi = _headersFromChannelData(channelData);
  if (fromApi.isNotEmpty) return fromApi;
  return playbackHttpHeaders(url);
}

Map<String, String> _headersFromChannelData(Map<String, dynamic>? channelData) {
  if (channelData == null) return const {};
  final candidates = <Object?>[
    channelData['headers'],
    channelData['streamHeaders'],
    channelData['stream_headers'],
    channelData['drmHeaders'],
    channelData['drm_headers'],
  ];
  for (final candidate in candidates) {
    final parsed = _toStringMap(candidate);
    if (parsed.isNotEmpty) return parsed;
  }
  return const {};
}

Map<String, String> _toStringMap(Object? raw) {
  if (raw == null) return const {};
  if (raw is Map) {
    final out = <String, String>{};
    raw.forEach((key, value) {
      final k = key.toString().trim();
      final v = value?.toString().trim() ?? '';
      if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
    });
    return out;
  }
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty) return const {};
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) return _toStringMap(decoded);
    } catch (_) {}
  }
  return const {};
}

String extractAudioLanguage(Map<String, dynamic>? channelData) {
  if (channelData == null) return 'sw';
  final raw = channelData['audioLanguage'] ?? channelData['audio_language'];
  final lang = raw?.toString().trim().toLowerCase() ?? '';
  if (lang.isEmpty || lang == 'auto' || lang == 'default') return 'sw';
  const allowed = {'sw', 'en', 'ar', 'fr', 'multi'};
  if (allowed.contains(lang)) return lang;
  if (lang.startsWith('en')) return 'en';
  if (lang.startsWith('ar')) return 'ar';
  if (lang.startsWith('fr')) return 'fr';
  return 'sw';
}

Map<String, String> mergedPlaybackHeaders({
  required String url,
  required Map<String, dynamic>? channelData,
}) {
  final headers = extractPlaybackHeaders(channelData, url);
  final token = extractPlaybackToken(channelData);
  final merged = Map<String, String>.from(headers);
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
