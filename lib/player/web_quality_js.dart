/// Patches Shaka when it loads and tracks player instances for live quality toggles.
const String kWebQualityInstallJs = '''
(function () {
  function patchShaka() {
    if (!window.shaka || !shaka.Player || window.__washaShakaCtorPatched) return;
    window.__washaShakaCtorPatched = true;
    if (!window.__washaShakaPlayers) window.__washaShakaPlayers = [];

    var Orig = shaka.Player;
    function WrappedPlayer() {
      var instance = Reflect.construct
        ? Reflect.construct(Orig, arguments, new.target)
        : Object.create(Orig.prototype);
      if (!Reflect.construct) {
        var ret = Orig.apply(instance, arguments);
        if (ret) instance = ret;
      }
      window.__washaShakaPlayers.push(instance);
      try {
        var maxH = window.__washaMaxHeight || 0;
        if (maxH > 0 && instance.configure) {
          instance.configure({ abr: { enabled: true, restrictions: { maxHeight: maxH } } });
        }
      } catch (e) {}
      return instance;
    }
    WrappedPlayer.prototype = Orig.prototype;
    Object.setPrototypeOf(WrappedPlayer, Orig);
    shaka.Player = WrappedPlayer;
  }

  patchShaka();
  var tries = 0;
  var timer = setInterval(function () {
    patchShaka();
    if (++tries >= 60) clearInterval(timer);
  }, 100);
  true;
})();
''';

/// Applies or clears the 360p cap on every Shaka player found in the page.
/// Returns the number of players updated (for Dart probe).
const String kWebQualityApplyJs = '''
(function () {
  var maxH = window.__washaMaxHeight || 0;

  function collectPlayers() {
    var out = [];
    var seen = new Set();
    function add(p) {
      if (p && typeof p.configure === 'function' && !seen.has(p)) {
        seen.add(p);
        out.push(p);
      }
    }

    [window.player, window.shakaPlayer, window._player, window.__washaShakaPlayer].forEach(add);
    if (window.__washaShakaPlayers) {
      for (var i = 0; i < window.__washaShakaPlayers.length; i++) add(window.__washaShakaPlayers[i]);
    }

    try {
      var videos = document.querySelectorAll('video');
      for (var v = 0; v < videos.length; v++) {
        var video = videos[v];
        if (video && video.__shaka) add(video.__shaka);
      }
    } catch (e) {}

    return out;
  }

  function restrictionsForCap() {
    if (maxH > 0) return { maxHeight: maxH };
    return { maxHeight: 100000, maxBandwidth: 100000000 };
  }

  function pickTrack(tracks, maxHeight) {
    if (!tracks || !tracks.length) return null;
    var sorted = tracks.slice().sort(function (a, b) { return (a.height || 0) - (b.height || 0); });
    if (maxHeight > 0) {
      for (var i = sorted.length - 1; i >= 0; i--) {
        if ((sorted[i].height || 0) <= maxHeight) return sorted[i];
      }
      return sorted[0];
    }
    return sorted[sorted.length - 1];
  }

  async function applyToPlayer(player) {
    try {
      var restrictions = restrictionsForCap();
      player.configure({ abr: { enabled: true, restrictions: restrictions } });
      if (typeof player.getVariantTracks === 'function' && typeof player.selectVariantTrack === 'function') {
        var tracks = player.getVariantTracks();
        var pick = pickTrack(tracks, maxH);
        if (pick) await player.selectVariantTrack(pick, true);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  function applyAll() {
    var players = collectPlayers();
    var updated = 0;
    for (var i = 0; i < players.length; i++) {
      try {
        var restrictions = restrictionsForCap();
        players[i].configure({ abr: { enabled: true, restrictions: restrictions } });
        updated++;
        if (typeof players[i].getVariantTracks === 'function' &&
            typeof players[i].selectVariantTrack === 'function') {
          (function (player) {
            try {
              var tracks = player.getVariantTracks();
              var pick = pickTrack(tracks, maxH);
              if (pick) {
                var selected = player.selectVariantTrack(pick, true);
                if (selected && typeof selected.catch === 'function') selected.catch(function () {});
              }
            } catch (e) {}
          })(players[i]);
        }
      } catch (e) {}
    }
    return updated;
  }

  window.__washaApplyQualityCap = applyAll;
  return applyAll();
})();
''';
