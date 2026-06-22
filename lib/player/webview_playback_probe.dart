/// JS that reports whether WebView / Shaka / gateway playback is active.
///
/// Returns `'1'` playing, `'err'` on video error, `'0'` still loading.
const String kWebPlaybackStatusJs = '''
(() => {
  if (window.__washaPlaying === true) return '1';
  if (window.__washaError) return 'err';
  const v = document.querySelector('video');
  if (!v) return '0';
  if (v.error) return 'err';
  if (!v.paused && v.readyState >= 2) {
    if (v.currentTime > 0 || v.videoWidth > 0 || !isFinite(v.duration)) return '1';
  }
  return '0';
})()
''';
