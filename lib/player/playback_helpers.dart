import 'dart:convert';

Map<String, String> playbackHeadersFromData(Map<String, dynamic>? channelData) {
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

String playbackTokenFromData(Map<String, dynamic>? channelData) {
  if (channelData == null) return '';
  final raw = channelData['token'] ??
      channelData['streamToken'] ??
      channelData['stream_token'] ??
      channelData['authToken'] ??
      channelData['auth_token'];
  return raw?.toString().trim() ?? '';
}

String playbackAudioLanguageFromData(Map<String, dynamic>? channelData) {
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

String clearKeyPayloadFromData(Map<String, dynamic>? channelData) {
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
