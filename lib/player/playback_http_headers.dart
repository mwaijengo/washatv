import 'package:washa/player/cdn_token_headers.dart';

const _chromeMobileUa =
    'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

const _browserOnlyHeaders = {
  'sec-fetch-dest',
  'sec-fetch-mode',
  'sec-fetch-site',
  'sec-fetch-user',
  'upgrade-insecure-requests',
  'sec-ch-ua',
  'sec-ch-ua-mobile',
  'sec-ch-ua-platform',
};

final _iptvPortPath = RegExp(
  r'^https?://[^/]+:\d{2,5}/(live|stream|play|hls|iptv|channel|ch)/',
  caseSensitive: false,
);
final _iptvPortTriple = RegExp(
  r'^https?://[^/]+:\d{2,5}/[^/]+/[^/]+/[^/?#]+$',
  caseSensitive: false,
);
final _iptvHostPath = RegExp(
  r'^https?://[^/]+/(live|stream|play|hls|iptv|channel|ch)/[^/?#]+',
  caseSensitive: false,
);

/// Direct HLS/DASH/file URLs and plain HTTP streams.
/// Browser page headers (`Origin`, `Referer` of the stream host) make these
/// servers answer 403. Token CDNs and `.php` gateways still need those headers.
bool isDirectMediaUrl(String rawUrl) {
  final u = rawUrl.trim();
  if (u.isEmpty) return false;
  if (u.toLowerCase().contains('.php')) return false;
  if (CdnTokenHeaders.isTokenizedCdnUrl(u)) return false;
  final uri = Uri.tryParse(u);
  if (uri == null) return false;
  final path = uri.path.toLowerCase();
  if (path.endsWith('.m3u8') ||
      path.endsWith('.m3u') ||
      path.endsWith('.mpd') ||
      path.endsWith('.mp4') ||
      path.endsWith('.m4v') ||
      path.endsWith('.ts') ||
      path.endsWith('.mkv') ||
      path.endsWith('.webm')) {
    return true;
  }
  if (_isLikelyIptvLiveUrl(u)) return true;
  // Extension-less HTTP (Xtream / raw TS). HTTPS pages still use browser headers.
  if (uri.scheme == 'http' && !_isDocumentPath(path)) return true;
  return false;
}

bool _isDocumentPath(String path) {
  return path.endsWith('.html') ||
      path.endsWith('.htm') ||
      path.endsWith('.asp') ||
      path.endsWith('.aspx') ||
      path.endsWith('.cgi') ||
      path.endsWith('.jsp');
}

bool _isLikelyIptvLiveUrl(String url) {
  final base = url.split('#').first;
  return _iptvPortPath.hasMatch(base) ||
      _iptvPortTriple.hasMatch(base) ||
      _iptvHostPath.hasMatch(base);
}

/// CDNs / `.php` gateways often reject players without browser-like headers.
/// Tokenized Azam/Nagra URLs (`tok_<jwt>`) require Referer/Origin from the JWT `url` field.
/// Direct media (HTTP and HTTPS `.m3u8` / `.mpd` / files, and plain HTTP streams)
/// uses player headers only.
Map<String, String> playbackHttpHeaders(String rawUrl) {
  final u = rawUrl.trim();
  if (u.isEmpty) return const {};
  Uri parsed;
  try {
    parsed = Uri.parse(u);
  } catch (_) {
    return const {};
  }
  if (!parsed.hasScheme || !parsed.hasAuthority) return const {};
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return const {};

  if (isDirectMediaUrl(u)) {
    return const {
      'User-Agent': _chromeMobileUa,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9,sw;q=0.8',
      'Connection': 'keep-alive',
    };
  }

  final cdnOrigin = '${parsed.scheme}://${parsed.authority}';
  final tokenHeaders = CdnTokenHeaders.refererOriginForUrl(u);
  final referer = tokenHeaders?['referer'] ?? '$cdnOrigin/';
  final origin = tokenHeaders?['origin'] ?? cdnOrigin;

  final headers = <String, String>{
    'Referer': referer,
    'Origin': origin,
    'User-Agent': _chromeMobileUa,
    'Connection': 'keep-alive',
    'Accept-Language': 'en-US,en;q=0.9,sw;q=0.8',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,application/dash+xml,application/vnd.apple.mpegurl;q=0.8,*/*;q=0.7',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-User': '?1',
    'Upgrade-Insecure-Requests': '1',
  };
  if (u.toLowerCase().contains('.php')) {
    headers['X-Requested-With'] = 'com.washatv';
  }
  return headers;
}

/// Merges API-provided headers over URL-derived defaults (playback API wins).
Map<String, String> mergePlaybackHeaders(
  String streamUrl, [
  Map<String, dynamic>? fromApi,
]) {
  final merged = <String, String>{};
  void putHeader(String rawName, String rawValue) {
    final name = _canonicalHeaderName(rawName.trim());
    final value = rawValue.trim();
    if (name.isEmpty || value.isEmpty) return;
    merged.removeWhere((key, _) => key.toLowerCase() == name.toLowerCase());
    merged[name] = value;
  }

  playbackHttpHeaders(streamUrl).forEach(putHeader);
  if (fromApi != null) {
    fromApi.forEach((key, value) {
      putHeader(key.toString(), value?.toString() ?? '');
    });
  }
  if (isDirectMediaUrl(streamUrl)) {
    merged.removeWhere((key, _) => _browserOnlyHeaders.contains(key.toLowerCase()));
    final host = Uri.tryParse(streamUrl.trim())?.host.toLowerCase() ?? '';
    if (host.isNotEmpty) {
      final origin = _headerIgnoreCase(merged, 'origin');
      final referer = _headerIgnoreCase(merged, 'referer');
      if (origin != null && origin.toLowerCase().contains(host)) {
        merged.removeWhere((key, _) => key.toLowerCase() == 'origin');
      }
      if (referer != null && referer.toLowerCase().contains(host)) {
        merged.removeWhere((key, _) => key.toLowerCase() == 'referer');
      }
    }
    merged['Accept'] = '*/*';
  }
  return merged;
}

String? _headerIgnoreCase(Map<String, String> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}

String _canonicalHeaderName(String name) {
  switch (name.toLowerCase()) {
    case 'referer':
      return 'Referer';
    case 'origin':
      return 'Origin';
    case 'user-agent':
      return 'User-Agent';
    case 'accept':
      return 'Accept';
    case 'accept-language':
      return 'Accept-Language';
    case 'authorization':
      return 'Authorization';
    case 'content-type':
      return 'Content-Type';
    case 'connection':
      return 'Connection';
    case 'x-requested-with':
      return 'X-Requested-With';
    default:
      return name;
  }
}
