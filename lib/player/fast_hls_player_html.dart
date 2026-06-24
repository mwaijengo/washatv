import 'dart:convert';

/// Lightweight HLS player — hls.js when headers are required, native `<video>` otherwise.
String buildFastHlsPlayerHtml({
  required String streamUrl,
  Map<String, String> requestHeaders = const {},
}) {
  final config = jsonEncode({
    'url': streamUrl.trim(),
    'headers': requestHeaders,
  });

  return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
  <style>
    html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
    video { width: 100%; height: 100%; object-fit: contain; background: #000; }
    pre, code, .error-display { display: none !important; visibility: hidden !important; }
  </style>
  <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.17/dist/hls.min.js"></script>
</head>
<body>
  <video id="video" playsinline webkit-playsinline autoplay muted></video>
  <script>
    (function () {
      var cfg = $config;
      window.__washaPlaying = false;
      window.__washaPlaybackLocked = false;
      window.__washaError = null;
      var video = document.getElementById('video');
      var headers = cfg.headers || {};

      function needsCustomHeaders() {
        return Object.keys(headers).some(function (k) {
          var lk = k.toLowerCase();
          return lk === 'referer' || lk === 'origin' || lk === 'authorization';
        });
      }

      function markPlaying() {
        window.__washaPlaying = true;
        window.__washaPlaybackLocked = true;
        window.__washaError = null;
      }

      function markError() {
        window.__washaPlaying = false;
        window.__washaPlaybackLocked = false;
        window.__washaError = 'playback_error';
      }

      function tryPlay() {
        if (window.__washaUserPaused) return;
        try {
          var p = video.play();
          if (p && typeof p.catch === 'function') p.catch(function () {});
        } catch (e) {}
      }

      function applyHeaders(xhr) {
        for (var key in headers) {
          if (Object.prototype.hasOwnProperty.call(headers, key)) {
            try { xhr.setRequestHeader(key, headers[key]); } catch (e) {}
          }
        }
      }

      function unmuteSoon() {
        setTimeout(function () {
          if (window.__washaUserPaused) return;
          try { video.muted = false; } catch (e) {}
        }, 120);
      }

      video.addEventListener('playing', function () {
        if (window.__washaUserPaused) return;
        markPlaying();
        unmuteSoon();
      });
      video.addEventListener('waiting', function () { tryPlay(); });
      video.addEventListener('error', function () { markError(); });

      function attachDirect() {
        video.src = cfg.url;
        tryPlay();
      }

      function attachHlsJs() {
        if (!window.Hls || !Hls.isSupported()) {
          attachDirect();
          return;
        }
        var hls = new Hls({
          enableWorker: true,
          lowLatencyMode: true,
          maxBufferLength: 20,
          maxMaxBufferLength: 40,
          xhrSetup: function (xhr) { applyHeaders(xhr); }
        });
        hls.on(Hls.Events.ERROR, function (evt, data) {
          if (data.fatal) markError();
        });
        hls.on(Hls.Events.MANIFEST_PARSED, tryPlay);
        hls.loadSource(cfg.url);
        hls.attachMedia(video);
        window.__washaHls = hls;
      }

      if (needsCustomHeaders()) {
        attachHlsJs();
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        attachDirect();
      } else if (window.Hls && Hls.isSupported()) {
        attachHlsJs();
      } else {
        attachDirect();
      }
    })();
  </script>
</body>
</html>
''';
}
