/// Shared play/pause/autoplay helpers for all WebView players.
const String kWebMediaControlJs = '''
(function () {
  if (window.__washaMediaInstalled) return true;
  window.__washaMediaInstalled = true;
  window.__washaUserPaused = false;

  function mainVideo() {
    return document.querySelector('video');
  }

  function collectPlayers() {
    var out = [];
    var seen = new Set();
    function add(p) {
      if (p && typeof p.pause === 'function' && !seen.has(p)) {
        seen.add(p);
        out.push(p);
      }
    }
    [window.player, window.shakaPlayer, window._player, window.__washaShakaPlayer].forEach(add);
    if (window.__washaShakaPlayers) {
      for (var i = 0; i < window.__washaShakaPlayers.length; i++) add(window.__washaShakaPlayers[i]);
    }
    return out;
  }

  window.__washaPauseAll = function () {
    window.__washaUserPaused = true;
    window.__washaPlaying = false;
    window.__washaPlaybackLocked = false;
    try {
      document.querySelectorAll('video, audio').forEach(function (el) {
        try { el.pause(); } catch (e) {}
      });
    } catch (e) {}
    collectPlayers().forEach(function (p) {
      try { p.pause(); } catch (e) {}
    });
  };

  window.__washaPlayAll = function () {
    window.__washaUserPaused = false;
    var v = mainVideo();
    if (!v) return;
    try {
      v.muted = true;
      var prom = v.play && v.play();
      if (prom && typeof prom.then === 'function') {
        prom.then(function () { try { v.muted = false; } catch (e) {} });
      } else {
        try { v.muted = false; } catch (e) {}
      }
    } catch (e) {}
  };

  window.__washaEnsurePlaying = function () {
    if (window.__washaUserPaused) return;
    var v = mainVideo();
    if (v && !v.paused && v.readyState >= 2) return;
    if (window.__washaEnsureTimer) return;
    window.__washaEnsureTimer = setTimeout(function () {
      window.__washaEnsureTimer = null;
      if (window.__washaUserPaused) return;
      var video = mainVideo();
      if (!video || video.paused) window.__washaPlayAll();
    }, 200);
  };

  true;
})();
''';

const String kWebMediaPauseJs = 'window.__washaPauseAll && window.__washaPauseAll(); true;';

const String kWebMediaPlayJs = 'window.__washaPlayAll && window.__washaPlayAll(); true;';

const String kWebMediaEnsurePlayJs = 'window.__washaEnsurePlaying && window.__washaEnsurePlaying(); true;';
