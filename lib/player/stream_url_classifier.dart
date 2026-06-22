/// Stream URL hints for player routing (HLS / DASH / MP4 / PHP gateways).
class StreamUrlClassifier {
  StreamUrlClassifier._();

  static bool isPhpLikeUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.toLowerCase();
    return RegExp(r'\.php($|[/?#])', caseSensitive: false).hasMatch(u);
  }

  static bool hasObviousM3u8(String url) {
    final u = url.toLowerCase();
    return u.contains('.m3u8');
  }

  static bool hasObviousMpd(String url) {
    final u = url.toLowerCase();
    return u.contains('.mpd');
  }

  static bool hasObviousMp4(String url) {
    final u = url.toLowerCase();
    return u.contains('.mp4') || u.contains('.m4v') || u.contains('.mov');
  }

  static bool hasObviousTs(String url) {
    final u = url.toLowerCase();
    return u.contains('.ts?') || u.endsWith('.ts');
  }

  /// HLS manifests — including tokenized URLs without a `.m3u8` suffix.
  static bool isLikelyHls(String url) {
    if (hasObviousM3u8(url)) return true;
    final u = url.toLowerCase();
    return u.contains('m3u8') ||
        u.contains('/hls/') ||
        u.contains('mpegurl') ||
        u.contains('application/vnd.apple.mpegurl');
  }

  /// DASH manifests — including `/dash/` style paths.
  static bool isLikelyDash(String url) {
    if (hasObviousMpd(url)) return true;
    final u = url.toLowerCase();
    return u.contains('/dash/') || u.contains('application/dash+xml');
  }

  /// Progressive or transport streams for native ExoPlayer / AVPlayer.
  static bool isNativeFriendly(String url) {
    if (url.trim().isEmpty || isPhpLikeUrl(url)) return false;
    return isLikelyHls(url) || isLikelyDash(url) || hasObviousMp4(url) || hasObviousTs(url);
  }

  /// Direct media endpoints — safe for native ExoPlayer / AVPlayer (no PHP gateway).
  static bool isDirectStreamUrl(String url) {
    if (url.trim().isEmpty) return false;
    if (isPhpLikeUrl(url)) return false;
    return isLikelyHls(url) || isLikelyDash(url) || hasObviousMp4(url) || hasObviousTs(url);
  }
}

const String kBrowserPlaybackUserAgent =
    'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Mobile Safari/537.36';
