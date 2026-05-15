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
}

const String kBrowserPlaybackUserAgent =
    'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Mobile Safari/537.36';
