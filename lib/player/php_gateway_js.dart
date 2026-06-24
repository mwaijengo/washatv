export 'web_quality_js.dart' show kWebQualityApplyJs, kWebQualityInstallJs;

/// Passive observer for external Shaka gateway pages (sp1.php, sp2.php).
const String kPhpGatewayPassiveJs = '''
(function () {
  if (window.__washaGatewayPassive) return true;
  window.__washaGatewayPassive = true;

  function styleVideo() {
    try {
      if (!document.getElementById('washa-style')) {
        var style = document.createElement('style');
        style.id = 'washa-style';
        style.textContent =
          'html, body { margin: 0 !important; padding: 0 !important; width: 100% !important; height: 100% !important; background: #000 !important; overflow: hidden !important; }' +
          'video { width: 100% !important; height: 100% !important; object-fit: contain !important; background: #000 !important; }' +
          'body > img, body > div > img { display: none !important; }' +
          '.shaka-text-container, .shaka-error-container, .shaka-errors, #shaka-player-ui-error-container, ' +
          '.shaka-message-container, #error-container, #error-display, .error-display, pre, code, ' +
          '.alert, .alert-danger, .error-message { display: none !important; visibility: hidden !important; opacity: 0 !important; }';
        (document.head || document.documentElement).appendChild(style);
      }
      document.documentElement.style.background = '#000';
      document.body.style.background = '#000';
      var v = document.querySelector('video');
      if (v) {
        v.removeAttribute('poster');
        v.style.background = '#000';
      }
    } catch (e) {}
  }

  function nudgePlayOn(video) {
    if (!video || window.__washaUserPaused) return;
    if (!video.paused && video.readyState >= 2) return;
    try {
      video.muted = true;
      var p = video.play && video.play();
      if (p && typeof p.then === 'function') {
        p.then(function () { try { video.muted = false; } catch (e) {} });
      } else {
        try { video.muted = false; } catch (e) {}
      }
    } catch (e) {}
  }

  function nudgePlayOnce() {
    nudgePlayOn(document.querySelector('video'));
  }

  function observeVideo(video) {
    if (!video || video.__washaObserved) return;
    video.__washaObserved = true;
    video.setAttribute('playsinline', 'true');
    video.setAttribute('webkit-playsinline', 'true');
    video.setAttribute('autoplay', 'true');
    nudgePlayOn(video);
    video.addEventListener('playing', function () {
      if (window.__washaUserPaused) return;
      window.__washaPlaying = true;
      window.__washaPlaybackLocked = true;
      window.__washaError = null;
      try { video.muted = false; } catch (e) {}
    });
    video.addEventListener('timeupdate', function () {
      if (window.__washaUserPaused) return;
      if (video.currentTime > 0.05 || video.videoWidth > 0) {
        window.__washaPlaying = true;
        window.__washaPlaybackLocked = true;
        window.__washaError = null;
      }
    });
    video.addEventListener('pause', function () {
      if (window.__washaUserPaused) {
        window.__washaPlaying = false;
        window.__washaPlaybackLocked = false;
      }
    });
  }

  function hideTechMessages() {
    try {
      var kids = document.body ? document.body.children : [];
      for (var i = 0; i < kids.length; i++) {
        var el = kids[i];
        if (!el || el.tagName === 'VIDEO' || el.tagName === 'STYLE' || el.tagName === 'SCRIPT') continue;
        if (el.id === 'washa-style' || el.id === 'washa-hide-errors') continue;
        if (el.querySelector && el.querySelector('video')) continue;
        var txt = (el.textContent || '').trim().toLowerCase();
        if (!txt) continue;
        if (txt.indexOf('error') >= 0 || txt.indexOf('shaka') >= 0 || txt.indexOf('http') >= 0 || /\\b\\d{4}\\b/.test(txt)) {
          el.style.display = 'none';
        }
      }
    } catch (e) {}
  }

  function tick() {
    styleVideo();
    hideTechMessages();
    var v = document.querySelector('video');
    if (v) observeVideo(v);
  }

  try {
    var observer = new MutationObserver(tick);
    observer.observe(document.documentElement || document.body, { childList: true, subtree: true });
  } catch (e) {}

  tick();
  nudgePlayOnce();
  setTimeout(nudgePlayOnce, 80);
  setTimeout(nudgePlayOnce, 250);
  setTimeout(nudgePlayOnce, 600);
  setInterval(tick, 1500);
  true;
})();
''';

const String kPhpGatewayRecoveryJs = kPhpGatewayPassiveJs;
