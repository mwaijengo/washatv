/// Hides Shaka / gateway error text, URLs, and codes inside WebView — users only see Flutter overlay.
const String kWebHidePlayerErrorsJs = '''
(function () {
  if (window.__washaHideErrorsInstalled) return true;
  window.__washaHideErrorsInstalled = true;

  var css =
    '.shaka-text-container, .shaka-error-container, .shaka-errors, ' +
    '#shaka-player-ui-error-container, .shaka-message-container, ' +
    '#error-container, #error-display, .error-display, .vjs-error-display, ' +
    'pre, code, .alert, .alert-danger, .error-message, .playback-error { ' +
    'display: none !important; visibility: hidden !important; opacity: 0 !important; ' +
    'height: 0 !important; overflow: hidden !important; pointer-events: none !important; }';

  function ensureStyle() {
    if (document.getElementById('washa-hide-errors')) return;
    var style = document.createElement('style');
    style.id = 'washa-hide-errors';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }

  function looksLikeTechError(text) {
    if (!text) return false;
    var t = text.toLowerCase();
    return (
      t.indexOf('error') >= 0 ||
      t.indexOf('shaka') >= 0 ||
      t.indexOf('http://') >= 0 ||
      t.indexOf('https://') >= 0 ||
      t.indexOf('.m3u8') >= 0 ||
      t.indexOf('.mpd') >= 0 ||
      t.indexOf('.php') >= 0 ||
      /\\b\\d{4}\\b/.test(t)
    );
  }

  function hideErrorNodes() {
    ensureStyle();
    try {
      var selectors = [
        '.shaka-text-container',
        '.shaka-error-container',
        '#shaka-player-ui-error-container',
        '.shaka-message-container',
        '#error-container',
        '#error-display',
        '.error-display',
        '.vjs-error-display',
        'pre',
        'code'
      ];
      for (var s = 0; s < selectors.length; s++) {
        var nodes = document.querySelectorAll(selectors[s]);
        for (var i = 0; i < nodes.length; i++) {
          nodes[i].style.display = 'none';
        }
      }
      var bodyKids = document.body ? document.body.children : [];
      for (var j = 0; j < bodyKids.length; j++) {
        var el = bodyKids[j];
        if (!el || el.tagName === 'VIDEO' || el.tagName === 'STYLE' || el.tagName === 'SCRIPT') continue;
        if (el.id === 'washa-style' || el.id === 'washa-hide-errors') continue;
        if (el.querySelector && el.querySelector('video')) continue;
        var txt = (el.textContent || '').trim();
        if (txt.length > 0 && looksLikeTechError(txt)) {
          el.style.display = 'none';
        }
      }
    } catch (e) {}
  }

  hideErrorNodes();
  try {
    var obs = new MutationObserver(hideErrorNodes);
    obs.observe(document.documentElement || document.body, { childList: true, subtree: true, characterData: true });
  } catch (e) {}
  setInterval(hideErrorNodes, 800);
  true;
})()
''';
