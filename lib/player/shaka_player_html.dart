import 'dart:convert';

import '../models/channel.dart';

/// Builds a self-contained Shaka Player page for DASH/HLS + DRM inside WebView.
String buildShakaPlayerHtml({
  required String streamUrl,
  ChannelDrm drm = ChannelDrm.none,
  int maxHeight = 0,
  Map<String, String> requestHeaders = const {},
}) {
  final config = jsonEncode({
    'url': streamUrl.trim(),
    'drm': drm.name,
    'maxHeight': maxHeight,
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
  </style>
  <script src="https://cdn.jsdelivr.net/npm/shaka-player@4.12.5/dist/shaka-player.compiled.js"></script>
</head>
<body>
  <video id="video" playsinline webkit-playsinline autoplay></video>
  <script>
    (function () {
      var cfg = $config;
      window.__washaPlaying = false;
      window.__washaError = null;

      function markPlaying() {
        window.__washaPlaying = true;
        window.__washaError = null;
      }

      function markError(msg) {
        window.__washaPlaying = false;
        window.__washaError = msg || 'playback_error';
      }

      function tryPlay(video) {
        try {
          var p = video.play();
          if (p && typeof p.catch === 'function') p.catch(function () {});
        } catch (e) {}
      }

      async function start() {
        if (!window.shaka || !shaka.Player.isBrowserSupported()) {
          markError('shaka_unsupported');
          return;
        }

        shaka.polyfill.installAll();
        var video = document.getElementById('video');
        var player = new shaka.Player(video);

        player.addEventListener('error', function (evt) {
          markError((evt.detail && evt.detail.message) || 'shaka_error');
        });

        video.addEventListener('playing', markPlaying);
        video.addEventListener('timeupdate', function () {
          if (!video.paused && video.readyState >= 2) markPlaying();
        });

        var playerConfig = {
          streaming: {
            bufferingGoal: 12,
            rebufferingGoal: 4,
            retryParameters: { timeout: 15000, maxAttempts: 4, baseDelay: 500 }
          },
          abr: { enabled: true }
        };

        if (cfg.maxHeight > 0) {
          playerConfig.abr.restrictions = { maxHeight: cfg.maxHeight };
        }

        if (cfg.drm === 'clearkey' || cfg.drm === 'widevine') {
          playerConfig.drm = { servers: {} };
        }

        player.configure(playerConfig);

        var headers = cfg.headers || {};
        if (headers && Object.keys(headers).length > 0) {
          player.getNetworkingEngine().registerRequestFilter(function (type, request) {
            if (
              type === shaka.net.NetworkingEngine.RequestType.MANIFEST ||
              type === shaka.net.NetworkingEngine.RequestType.SEGMENT ||
              type === shaka.net.NetworkingEngine.RequestType.LICENSE
            ) {
              for (var key in headers) {
                if (Object.prototype.hasOwnProperty.call(headers, key)) {
                  request.headers[key] = headers[key];
                }
              }
            }
          });
        }

        try {
          await player.load(cfg.url);
          tryPlay(video);
        } catch (e) {
          markError((e && e.message) || 'load_failed');
        }
      }

      start();
    })();
  </script>
</body>
</html>
''';
}
