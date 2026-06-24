import 'package:http/http.dart' as http;

import 'gateway_stream_extractor.dart';
import 'manifest_url_extractor.dart';
import 'playback_http_headers.dart';
import 'stream_url_classifier.dart';

/// Result of probing a gateway or stream URL (aligned with EaMax [WebStreamProbe]).
class ResolvedStream {
  const ResolvedStream({
    required this.gatewayUrl,
    required this.playbackUrl,
    required this.isGatewayEmbed,
    this.headers = const {},
  });

  final String gatewayUrl;
  final String playbackUrl;
  final bool isGatewayEmbed;
  final Map<String, String> headers;

  bool get hasDirectManifest => !isGatewayEmbed && StreamUrlClassifier.isDirectStreamUrl(playbackUrl);
}

/// Resolves gateway / PHP URLs to a direct HLS/DASH endpoint when possible.
class StreamUrlResolver {
  StreamUrlResolver._();

  static Future<ResolvedStream> resolve(String rawUrl) async {
    final gatewayUrl = rawUrl.trim();
    if (gatewayUrl.isEmpty) {
      return ResolvedStream(gatewayUrl: '', playbackUrl: '', isGatewayEmbed: true);
    }

    if (StreamUrlClassifier.isDirectStreamUrl(gatewayUrl)) {
      return ResolvedStream(
        gatewayUrl: gatewayUrl,
        playbackUrl: gatewayUrl,
        isGatewayEmbed: false,
        headers: playbackHttpHeaders(gatewayUrl),
      );
    }

    final headers = playbackHttpHeaders(gatewayUrl);

    if (StreamUrlClassifier.isPhpLikeUrl(gatewayUrl)) {
      // Quick manifest probe — enables native Exo when extractable (much faster than WebView).
      try {
        final extracted = await _resolveGateway(gatewayUrl, headers).timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
        if (extracted != null) return extracted;
      } catch (_) {}
      return ResolvedStream(
        gatewayUrl: gatewayUrl,
        playbackUrl: gatewayUrl,
        isGatewayEmbed: true,
        headers: headers,
      );
    }

    final redirected = await _followRedirects(gatewayUrl, headers);
    if (redirected != null) return redirected;

    return ResolvedStream(
      gatewayUrl: gatewayUrl,
      playbackUrl: gatewayUrl,
      isGatewayEmbed: StreamUrlClassifier.isPhpLikeUrl(gatewayUrl),
      headers: headers,
    );
  }

  static Future<ResolvedStream?> _resolveGateway(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final html = await _fetchBody(url, headers);
      if (html.isEmpty) return null;

      final extracted = GatewayStreamExtractor.extract(html) ??
          GatewayStreamExtractor.extractDrmFromHtml(html);
      if (extracted != null && extracted.streamUrl.startsWith('http')) {
        final merged = Map<String, String>.from(headers);
        if (extracted.authToken.isNotEmpty &&
            !merged.keys.any((k) => k.toLowerCase() == 'authorization')) {
          merged['Authorization'] = 'Bearer ${extracted.authToken}';
        }
        return ResolvedStream(
          gatewayUrl: url,
          playbackUrl: extracted.streamUrl,
          isGatewayEmbed: false,
          headers: merged,
        );
      }

      final manifest = ManifestUrlExtractor.extract(html, url);
      if (manifest != null) {
        return ResolvedStream(
          gatewayUrl: url,
          playbackUrl: manifest.url,
          isGatewayEmbed: false,
          headers: headers,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<ResolvedStream?> _followRedirects(
    String url,
    Map<String, String> headers,
  ) async {
    final client = http.Client();
    try {
      var uri = Uri.parse(url);
      for (var hop = 0; hop < 6; hop++) {
        final res = await client.get(uri, headers: headers).timeout(const Duration(seconds: 5));
        if (res.statusCode >= 300 && res.statusCode < 400) {
          final loc = res.headers['location'];
          if (loc == null || loc.isEmpty) break;
          uri = uri.resolve(loc);
          final next = uri.toString();
          if (StreamUrlClassifier.isDirectStreamUrl(next)) {
            return ResolvedStream(
              gatewayUrl: url,
              playbackUrl: next,
              isGatewayEmbed: false,
              headers: headers,
            );
          }
          continue;
        }
        if (res.statusCode < 200 || res.statusCode >= 400) break;

        final finalUrl = uri.toString();
        if (StreamUrlClassifier.isDirectStreamUrl(finalUrl)) {
          return ResolvedStream(
            gatewayUrl: url,
            playbackUrl: finalUrl,
            isGatewayEmbed: false,
            headers: headers,
          );
        }

        final fromBody = _extractManifestUrl(res.body, uri);
        if (fromBody != null) {
          return ResolvedStream(
            gatewayUrl: url,
            playbackUrl: fromBody,
            isGatewayEmbed: false,
            headers: headers,
          );
        }
        break;
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }

  static Future<String> _fetchBody(String url, Map<String, String> headers) async {
    final client = http.Client();
    try {
      final res = await client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 400) return res.body;
    } finally {
      client.close();
    }
    return '';
  }

  static final RegExp _absoluteM3u8 = RegExp(
    r'''https?://[^\s"'<>]+\.m3u8[^\s"'<>]*''',
    caseSensitive: false,
  );
  static final RegExp _absoluteMpd = RegExp(
    r'''https?://[^\s"'<>]+\.mpd[^\s"'<>]*''',
    caseSensitive: false,
  );
  static final RegExp _quotedManifest = RegExp(
    r'''["']([^"']+\.(?:m3u8|mpd)[^"']*)["']''',
    caseSensitive: false,
  );

  static String? _extractManifestUrl(String body, Uri base) {
    if (body.isEmpty) return null;
    final m3u8 = _absoluteM3u8.firstMatch(body);
    if (m3u8 != null) return m3u8.group(0);
    final mpd = _absoluteMpd.firstMatch(body);
    if (mpd != null) return mpd.group(0);
    final quoted = _quotedManifest.firstMatch(body);
    if (quoted != null) return base.resolve(quoted.group(1)!).toString();
    return null;
  }
}
