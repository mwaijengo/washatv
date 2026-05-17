/// Stream URL hints for fast player setup (HLS / DASH / PHP gateways).
class StreamUrlClassifier {
  StreamUrlClassifier._();

  static bool isPhpLikeUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.toLowerCase();
    return RegExp(r'\.php(\$|[/?#])', caseSensitive: false).hasMatch(u);
  }

  static bool hasObviousM3u8(String url) {
    final u = url.toLowerCase();
    return u.contains('.m3u8');
  }

  static bool hasObviousMpd(String url) {
    final u = url.toLowerCase();
    return u.contains('.mpd');
  }

  static bool hasObviousTs(String url) {
    final u = url.toLowerCase();
    return u.contains('.ts?') || u.endsWith('.ts') || u.contains('.mp4?') || u.endsWith('.mp4');
  }

  /// Direct media endpoints — safe for native ExoPlayer / AVPlayer (no PHP gateway).
  static bool isDirectStreamUrl(String url) {
    if (url.trim().isEmpty) return false;
    if (isPhpLikeUrl(url)) return false;
    return hasObviousM3u8(url) || hasObviousMpd(url) || hasObviousTs(url);
  }
}

const String kBrowserPlaybackUserAgent =
    'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Mobile Safari/537.36';
