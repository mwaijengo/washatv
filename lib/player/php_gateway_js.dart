/// Injected after gateway pages load to recover HTML5 video playback.
const String kPhpGatewayRecoveryJs = '''
(function () {
  var lastProgressAt = Date.now();
  var waitingSince = 0;
  var monitorStarted = false;

  function getVideo() {
    return document.querySelector('video');
  }

  function tryPlay(video) {
    try {
      var p = video.play && video.play();
      if (p && typeof p.catch === 'function') p.catch(function(){});
    } catch (e) {}
  }

  function bindVideo(video) {
    if (!video || video.__washaBound) return;
    video.__washaBound = true;
    video.setAttribute('playsinline', 'true');
    video.setAttribute('webkit-playsinline', 'true');
    try { video.muted = false; } catch (e) {}
    video.controls = true;

    video.addEventListener('timeupdate', function () {
      lastProgressAt = Date.now();
      waitingSince = 0;
    });

    video.addEventListener('playing', function () {
      lastProgressAt = Date.now();
      waitingSince = 0;
    });

    video.addEventListener('waiting', function () {
      waitingSince = waitingSince || Date.now();
    });

    tryPlay(video);
  }

  function startMonitor() {
    if (monitorStarted) return;
    monitorStarted = true;
    var ticks = 0;
    setInterval(function () {
      ticks++;
      var video = getVideo();
      if (!video) return;
      bindVideo(video);

      var now = Date.now();
      var noProgressMs = now - lastProgressAt;
      if (video.paused && !video.ended) {
        tryPlay(video);
      }

      if (ticks <= 8 && (video.readyState < 2 || video.paused)) {
        tryPlay(video);
      }

      if ((video.readyState < 3 || video.seeking) && waitingSince === 0) {
        waitingSince = now;
      }

      var stallLimit = ticks <= 12 ? 3500 : 8000;
      if (waitingSince > 0 && noProgressMs > stallLimit) {
        try {
          if (isFinite(video.currentTime) && video.currentTime > 0.15) {
            video.currentTime = Math.max(0, video.currentTime - 0.1);
          }
        } catch (e) {}
        tryPlay(video);
        waitingSince = now;
      }
    }, 600);
  }

  try {
    var observer = new MutationObserver(function () {
      var v = getVideo();
      if (v) bindVideo(v);
    });
    observer.observe(document.documentElement || document.body, { childList: true, subtree: true });
  } catch (e) {}

  bindVideo(getVideo());
  startMonitor();
  true;
})();
''';
