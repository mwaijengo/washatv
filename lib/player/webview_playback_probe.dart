/// JS that reports whether WebView playback has started.
///
/// Returns `'1'` playing, `'err'` on video error, `'0'` still loading.
const String kWebPlaybackStatusJs = '''
(() => {
  if (window.__washaUserPaused === true) return '0';
  if (window.__washaPlaybackLocked === true) return '1';
  if (window.__washaError) return 'err';
  const v = document.querySelector('video');
  if (!v) return '0';
  if (v.error && v.error.code > 0 && v.networkState === v.NETWORK_NO_SOURCE) return 'err';
  if (window.__washaPlaying === true) return '1';
  if (v.videoWidth > 0 && v.readyState >= 2) return '1';
  if (!v.paused && v.readyState >= 2 && (v.currentTime > 0.05 || v.videoWidth > 0)) return '1';
  if (!v.paused && !isFinite(v.duration) && v.readyState >= 2 && v.videoWidth > 0) return '1';
  if (!v.paused && v.readyState >= 1 && v.videoWidth > 0) return '1';
  if (v.networkState === v.NETWORK_LOADING && v.readyState >= 1 && v.buffered.length > 0) return '1';
  return '0';
})()
''';

/// Lightweight health check after playback has started — errors only.
const String kWebPlaybackErrorJs = '''
(() => {
  if (window.__washaUserPaused === true) return '0';
  if (window.__washaPlaybackLocked === true) return '0';
  if (window.__washaError) return 'err';
  const v = document.querySelector('video');
  if (v && v.error && v.error.code > 0 && v.networkState === v.NETWORK_NO_SOURCE) return 'err';
  return '0';
})()
''';
