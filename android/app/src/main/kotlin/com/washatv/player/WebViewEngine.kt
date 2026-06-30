package com.washatv.player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import com.washatv.domain.model.PlaybackState
import com.washatv.domain.model.StreamQuality
import com.washatv.domain.model.StreamSession

/**
 * WebView engine for PHP / gateway pages. Quality and audio are applied via
 * [GatewayPlaybackJs] against in-page Shaka / hls.js players.
 */
class WebViewEngine(
    private val context: Context,
    private val onPlaybackStateChanged: (PlaybackState) -> Unit,
    private val onError: (String) -> Unit,
    private val embeddedInPlatformView: Boolean = false,
) {
    private var webView: WebView? = null
    private var currentSession: StreamSession? = null
    private var jsInterface: WebViewJsInterface? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var playbackStarted = false
    private var playbackApisInjected = false
    private var userPickedQuality = false
    private var selectedQuality: StreamQuality = StreamQuality.QUALITY_360P
    private var preferredAudioLanguage = "sw"
    private var lastLoadedAudioLanguage = ""
    private var audioLanguageConfirmed = false
    private var pageLoadGeneration = 0
    private var pageReadyHandled = false
    private var qualityApplied = false
    private var lastActiveHeight = 0
    private var lastPolledVideoTime = -1.0
    private var revealPollGeneration = 0
    private var pageFinishRunnable: Runnable? = null
    private val pendingRunnables = mutableListOf<Runnable>()

    private val DESKTOP_USER_AGENT =
        "ReactNativeVideo/3.0 (Linux;Android 11) ExoPlayerLib/2.10.4"

    companion object {
        private const val TAG = "EaMaxAudio"
        private const val QUALITY_TAG = "EaMaxQuality"
        private const val REVEAL_TAG = "EaMaxReveal"
    }

    private fun shouldUseWebView(url: String): Boolean {
        val u = url.trim().lowercase()
        return u.contains(".php") || u.contains(".html") ||
            (u.startsWith("http") && !u.contains(".mpd") && !u.contains(".m3u8"))
    }

    private fun acceptLanguageFor(lang: String): String =
        if (lang == "en") "en-US,en;q=0.9,sw;q=0.8" else "sw-TZ,sw;q=0.9,en;q=0.8"

    private fun buildLoadHeaders(
        session: StreamSession,
        audioLang: String = preferredAudioLanguage,
    ): Map<String, String> {
        val lang = normalizeAudioLanguage(audioLang)
        val h = LinkedHashMap(session.headers)
        if (session.token.isNotBlank() &&
            !h.keys.any { it.equals("Authorization", ignoreCase = true) }
        ) {
            h["Authorization"] = "Bearer ${session.token}"
        }
        h["Accept"] = "text/html,application/xhtml+xml,*/*;q=0.8"
        h["Accept-Language"] = acceptLanguageFor(lang)
        return h
    }

    fun initialize(streamSession: StreamSession) {
        currentSession = streamSession
        playbackStarted = false
        playbackApisInjected = false
        userPickedQuality = false
        preferredAudioLanguage = normalizeAudioLanguage(streamSession.preferredAudioLanguage)
        lastLoadedAudioLanguage = preferredAudioLanguage
        cancelPendingRunnables()

        val url = streamSession.mpdUrl
        val headers = buildLoadHeaders(streamSession, preferredAudioLanguage)
        val isExternalWebPage = shouldUseWebView(url)

        Log.d(TAG, "initialize url=${url.take(60)} audio=$preferredAudioLanguage " +
            "Accept-Language=${headers["Accept-Language"]}")

        try {
            webView = WebView(context).apply {
                setBackgroundColor(android.graphics.Color.BLACK)
                setLayerType(View.LAYER_TYPE_HARDWARE, null)
                visibility = View.INVISIBLE

                settings.apply {
                    javaScriptEnabled = true
                    domStorageEnabled = true
                    databaseEnabled = true
                    allowFileAccess = true
                    allowContentAccess = true
                    allowFileAccessFromFileURLs = true
                    allowUniversalAccessFromFileURLs = true
                    mediaPlaybackRequiresUserGesture = false
                    mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                    setSupportMultipleWindows(true)
                    javaScriptCanOpenWindowsAutomatically = true
                    loadWithOverviewMode = true
                    useWideViewPort = true
                    cacheMode = WebSettings.LOAD_DEFAULT
                    userAgentString = DESKTOP_USER_AGENT
                }

                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(
                        view: WebView?,
                        startedUrl: String?,
                        favicon: android.graphics.Bitmap?,
                    ) {
                        pageLoadGeneration++
                        pageFinishRunnable?.let { mainHandler.removeCallbacks(it) }
                        pageFinishRunnable = null
                        pageReadyHandled = false
                        qualityApplied = false
                        lastActiveHeight = 0
                        lastPolledVideoTime = -1.0
                        revealPollGeneration++
                        playbackStarted = false
                        playbackApisInjected = false
                        audioLanguageConfirmed = false
                        injectHideChromeJs()
                        onPlaybackStateChanged(PlaybackState.BUFFERING)
                    }

                    override fun onPageCommitVisible(view: WebView?, url: String?) {
                        injectHideChromeJs()
                    }

                    override fun onPageFinished(view: WebView?, finishedUrl: String?) {
                        super.onPageFinished(view, finishedUrl)
                        if (!isExternalWebPage) return
                        injectHideChromeJs()
                        schedulePageReady(pageLoadGeneration, delayMs = 0L)
                    }

                    override fun onReceivedError(
                        view: WebView?,
                        request: android.webkit.WebResourceRequest?,
                        error: android.webkit.WebResourceError?,
                    ) {
                        if (request?.isForMainFrame == true) {
                            onError("WebView Error: ${error?.description}")
                        }
                    }
                }

                webChromeClient = object : WebChromeClient() {
                    override fun onProgressChanged(view: WebView?, newProgress: Int) {
                        if (!isExternalWebPage || pageReadyHandled) return
                        if (newProgress >= 10) injectHideChromeJs()
                        if (newProgress >= 25) {
                            ensurePlaybackApisInjected()
                            nudgeVideoPlay()
                        }
                        if (newProgress >= 30) {
                            schedulePageReady(pageLoadGeneration, delayMs = 0L)
                        }
                    }

                    override fun onConsoleMessage(
                        consoleMessage: android.webkit.ConsoleMessage?,
                    ): Boolean {
                        Log.d(
                            "ShakaConsole",
                            "[${consoleMessage?.messageLevel()}] ${consoleMessage?.message()}",
                        )
                        return true
                    }
                }

                jsInterface = WebViewJsInterface(
                    onPlaybackStateChanged = onPlaybackStateChanged,
                    onError = onError,
                    onAudioProbe = { wanted, applied ->
                        if (applied && wanted == preferredAudioLanguage) {
                            audioLanguageConfirmed = true
                        }
                    },
                    onQualityProbe = { wanted, maxH, activeH, applied ->
                        if (applied) {
                            qualityApplied = true
                            if (activeH > 0) lastActiveHeight = activeH
                            if (userPickedQuality) {
                                Log.d(
                                    QUALITY_TAG,
                                    "quality confirmed wanted=$wanted maxH=$maxH activeH=$activeH",
                                )
                            }
                            tryRevealPlayback("quality-probe")
                        }
                    },
                )
                addJavascriptInterface(jsInterface!!, "ShakaPlayerBridge")
            }

            val wv = webView ?: return
            headers["User-Agent"]?.let { wv.settings.userAgentString = it }
            if (isExternalWebPage) {
                wv.loadUrl(url, headers)
                onPlaybackStateChanged(PlaybackState.BUFFERING)
            } else {
                wv.loadUrl("about:blank")
            }
        } catch (e: Exception) {
            onError("Failed to initialize WebView: ${e.message}")
        }
    }

    private fun schedulePageReady(generation: Int, delayMs: Long) {
        pageFinishRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable {
            if (generation != pageLoadGeneration || pageReadyHandled) return@Runnable
            handlePageReady()
        }
        pageFinishRunnable = r
        mainHandler.postDelayed(r, delayMs)
    }

    private fun handlePageReady() {
        if (pageReadyHandled) return
        pageReadyHandled = true
        pageFinishRunnable?.let { mainHandler.removeCallbacks(it) }
        pageFinishRunnable = null
        Log.d(TAG, "page ready audio=$preferredAudioLanguage")
        injectHideChromeJs()
        ensurePlaybackApisInjected()
        nudgeVideoPlay()
        nudgeVideoSurface()
        scheduleQualityWhenManifestReady()
        listOf(30L, 80L, 180L, 350L).forEach { delayMs ->
            postDelayed({
                injectHideChromeJs()
                nudgeVideoPlay()
                nudgeVideoSurface()
            }, delayMs)
        }
        if (embeddedInPlatformView) {
            postDelayed({ nudgeVideoSurface() }, 200L)
        }
    }

    private fun injectHideChromeJs() {
        webView?.evaluateJavascript(GatewayPlaybackJs.hidePageChromeScript(), null)
    }

    private fun applyPlaybackBootstrap() {
        // HW video decode needs a visible surface; spinner overlay hides gateway chrome.
        webView?.visibility = View.VISIBLE
        applyQualityAfterPageLoad()
        audioLanguageConfirmed = false
        applyAudioLanguageJs(preferredAudioLanguage, scheduleRetries = true)
        tryRevealPlayback("bootstrap")
    }

    private fun scheduleQualityWhenManifestReady(attempt: Int = 0) {
        val w = webView ?: return
        if (attempt % 3 == 0) nudgeVideoPlay()
        w.evaluateJavascript(
            "(function(){try{return window.__eaMaxManifestReady&&window.__eaMaxManifestReady();" +
                "}catch(e){return false;}})();",
        ) { raw ->
            val ready = raw == "true"
            if (ready || attempt >= 50) {
                applyPlaybackBootstrap()
                scheduleRevealWhenVideoReady()
                return@evaluateJavascript
            }
            postDelayed({ scheduleQualityWhenManifestReady(attempt + 1) }, 50L)
        }
    }

    private fun tryRevealPlayback(reason: String, attempt: Int = 0) {
        if (playbackStarted) return
        val generation = revealPollGeneration
        val w = webView ?: return
        if (attempt % 2 == 0) {
            nudgeVideoPlay()
            nudgeVideoSurface()
        }
        w.evaluateJavascript(
            "(function(){try{" +
                "var ready=window.__eaMaxPlaybackReady&&window.__eaMaxPlaybackReady();" +
                "var frame=window.__eaMaxVideoFrameReady&&window.__eaMaxVideoFrameReady();" +
                "var t=window.__eaMaxVideoTime?window.__eaMaxVideoTime():-1;" +
                "return JSON.stringify({ready:!!ready,frame:!!frame,time:t});" +
                "}catch(e){return JSON.stringify({ready:false,frame:false,time:-1});}})();",
        ) { raw ->
            if (generation != revealPollGeneration || playbackStarted) return@evaluateJavascript

            val playbackReady = raw?.contains("\"ready\":true") == true
            val frameReady = raw?.contains("\"frame\":true") == true
            val time = parseVideoTimeFromProbe(raw)
            val timeAdvancing = time > 0 && (
                lastPolledVideoTime < 0 || time > lastPolledVideoTime + 0.01
            )
            if (time >= 0) lastPolledVideoTime = time

            val trackReady = qualityApplied && lastActiveHeight > 0
            val shouldReveal = frameReady || (trackReady && (playbackReady || timeAdvancing || attempt >= 3))
            val forceReveal = attempt >= 30 && trackReady

            if (shouldReveal || forceReveal) {
                Log.d(
                    REVEAL_TAG,
                    "reveal reason=$reason attempt=$attempt track=$trackReady " +
                        "ready=$playbackReady frame=$frameReady time=$time",
                )
                markPlaybackPlaying()
                return@evaluateJavascript
            }
            postDelayed({ tryRevealPlayback(reason, attempt + 1) }, 40L)
        }
    }

    private fun scheduleRevealWhenVideoReady() {
        tryRevealPlayback("manifest-ready")
    }

    private fun parseVideoTimeFromProbe(raw: String?): Double {
        if (raw.isNullOrBlank()) return -1.0
        val m = Regex("""\"time\":(-?\d+(?:\.\d+)?)""").find(raw) ?: return -1.0
        return m.groupValues[1].toDoubleOrNull() ?: -1.0
    }

    private fun markPlaybackPlaying() {
        if (playbackStarted) return
        playbackStarted = true
        injectHideChromeJs()
        webView?.visibility = View.VISIBLE
        onPlaybackStateChanged(PlaybackState.PLAYING)
    }

    fun play() = nudgeVideoPlay()

    fun pauseForHandoff() {
        pause()
        webView?.onPause()
        webView?.pauseTimers()
    }

    fun resumeAfterHandoff() {
        val wv = webView ?: return
        wv.onResume()
        wv.resumeTimers()
        if (playbackStarted) {
            listOf(120L, 450L, 1200L).forEach { delayMs ->
                mainHandler.postDelayed({
                    nudgeVideoPlay()
                    nudgeVideoSurface()
                }, delayMs)
            }
            applyQualityAfterPageLoad()
            applyAudioLanguageJs(preferredAudioLanguage, scheduleRetries = true)
        }
    }

    fun pause() {
        webView?.evaluateJavascript(
            "(function(){try{var v=document.querySelector('video');if(v)v.pause();}catch(e){}})();",
            null,
        )
    }

    fun isPlaying(): Boolean = playbackStarted

    private fun nudgeVideoPlay() {
        webView?.evaluateJavascript(
            "(function(){" +
                "function playIn(doc){" +
                "try{var v=doc.querySelector('video');if(v){var p=v.play();if(p&&p.catch)p.catch(function(){});return true;}}catch(e){}" +
                "var iframes=doc.querySelectorAll('iframe');" +
                "for(var i=0;i<iframes.length;i++){try{var d=iframes[i].contentDocument||iframes[i].contentWindow.document;if(d&&playIn(d))return true;}catch(e){}}" +
                "return false;" +
                "}" +
                "playIn(document);" +
                "})();",
            null,
        )
    }

    private fun nudgeVideoSurface() {
        webView?.evaluateJavascript(
            "(function(){" +
                "function fixIn(doc){" +
                "try{" +
                "var v=doc.querySelector('video');" +
                "if(!v)return false;" +
                "v.removeAttribute('poster');" +
                "v.controls=false;" +
                "v.setAttribute('playsinline','');" +
                "v.setAttribute('webkit-playsinline','');" +
                "v.style.width='100%';" +
                "v.style.height='100%';" +
                "v.style.objectFit='contain';" +
                "v.style.background='#000';" +
                "return true;" +
                "}catch(e){return false;}" +
                "}" +
                "if(fixIn(document))return;" +
                "var iframes=document.querySelectorAll('iframe');" +
                "for(var i=0;i<iframes.length;i++){" +
                "try{var d=iframes[i].contentDocument||iframes[i].contentWindow.document;if(d&&fixIn(d))return;}catch(e){}" +
                "}" +
                "})();",
            null,
        )
    }

    fun stop() {
        webView?.stopLoading()
        webView?.loadUrl("about:blank")
    }

    fun setQuality(quality: StreamQuality, fromUser: Boolean = true) {
        if (!fromUser && userPickedQuality) return
        selectedQuality = quality
        if (fromUser) {
            userPickedQuality = true
            qualityApplied = false
        }
        val mode = qualityModeFor(quality)
        Log.d(QUALITY_TAG, "setQuality $quality mode=$mode fromUser=$fromUser")
        if (fromUser || pageReadyHandled) {
            applyQualityJs(mode, fromUser, scheduleRetries = fromUser)
        }
    }

    private fun qualityModeFor(quality: StreamQuality): String = when (quality) {
        StreamQuality.AUTO -> "auto"
        else -> quality.height.toString()
    }

    private fun applyQualityAfterPageLoad() {
        val mode = if (userPickedQuality) qualityModeFor(selectedQuality) else "360"
        val fromUser = userPickedQuality
        Log.d(QUALITY_TAG, "applyQualityAfterPageLoad mode=$mode fromUser=$fromUser")
        applyQualityJs(mode, fromUser, scheduleRetries = true)
    }

    private fun applyQualityJs(mode: String, fromUser: Boolean, scheduleRetries: Boolean) {
        if (!fromUser && qualityApplied) return
        injectQuality(mode, fromUser)
        if (!scheduleRetries || qualityApplied) return
        val delays = if (fromUser) {
            listOf(400L, 1000L)
        } else {
            listOf(100L, 250L, 500L, 900L)
        }
        delays.forEach { delayMs ->
            postDelayed({
                if (qualityApplied) return@postDelayed
                if (!fromUser && userPickedQuality) return@postDelayed
                injectQuality(mode, fromUser)
            }, delayMs)
        }
    }

    fun setAudioLanguage(language: String) {
        val lang = normalizeAudioLanguage(language)
        val session = currentSession
        val w = webView
        if (session == null || w == null) {
            Log.w(TAG, "setAudioLanguage($lang) ignored — no session/webView")
            return
        }

        Log.d(TAG, "setAudioLanguage request=$lang (loaded=$lastLoadedAudioLanguage)")
        preferredAudioLanguage = lang

        if (shouldUseWebView(session.mpdUrl) && lang != lastLoadedAudioLanguage) {
            cancelPendingRunnables()
            playbackStarted = false
            playbackApisInjected = false
            audioLanguageConfirmed = false
            lastLoadedAudioLanguage = lang
            val headers = buildLoadHeaders(session, lang)
            headers["User-Agent"]?.let { w.settings.userAgentString = it }
            Log.d(TAG, "Reloading gateway for audio=$lang Accept-Language=${headers["Accept-Language"]}")
            w.loadUrl(session.mpdUrl, headers)
            return
        }

        applyAudioLanguageJs(lang, scheduleRetries = true)
    }

    fun release() {
        cancelPendingRunnables()
        pageFinishRunnable?.let { mainHandler.removeCallbacks(it) }
        pageFinishRunnable = null
        webView?.apply {
            onPause()
            pauseTimers()
            stopLoading()
            loadUrl("about:blank")
            (parent as? ViewGroup)?.removeView(this)
            clearHistory()
            removeJavascriptInterface("ShakaPlayerBridge")
            destroy()
        }
        webView = null
        playbackApisInjected = false
        playbackStarted = false
    }

    fun getWebView(): WebView? = webView

    fun refreshSession(newSession: StreamSession) {
        currentSession = newSession
        playbackStarted = false
        playbackApisInjected = false
        preferredAudioLanguage = normalizeAudioLanguage(newSession.preferredAudioLanguage)
        lastLoadedAudioLanguage = preferredAudioLanguage
        val wv = webView ?: return
        val headers = buildLoadHeaders(newSession, preferredAudioLanguage)
        headers["User-Agent"]?.let { wv.settings.userAgentString = it }
        if (shouldUseWebView(newSession.mpdUrl)) {
            wv.loadUrl(newSession.mpdUrl, headers)
        }
    }

    private fun ensurePlaybackApisInjected() {
        val w = webView ?: return
        if (playbackApisInjected) return
        playbackApisInjected = true
        w.evaluateJavascript(GatewayPlaybackJs.eaMaxOkoaQualityApiScript(), null)
        w.evaluateJavascript(GatewayPlaybackJs.eaMaxAudioLanguageApiScript(), null)
    }

    private fun injectQuality(mode: String, fromUser: Boolean) {
        val w = webView ?: return
        ensurePlaybackApisInjected()
        val safeMode = mode.filter { it.isDigit() || it == 'a' || it == 'u' || it == 't' || it == 'o' }
        w.evaluateJavascript(GatewayPlaybackJs.eaMaxOkoaQualityApiScript(), null)
        w.evaluateJavascript(
            "try{window.__eaMaxPreferredAudioLang='${normalizeAudioLanguage(preferredAudioLanguage)}';" +
                "window.__eaMaxOkoaSetQuality&&window.__eaMaxOkoaSetQuality('$safeMode',${if (fromUser) "true" else "false"});}catch(e){}",
            null,
        )
    }

    private fun applyAudioLanguageJs(language: String, scheduleRetries: Boolean) {
        val w = webView ?: return
        val lang = normalizeAudioLanguage(language)
        if (audioLanguageConfirmed && lang == preferredAudioLanguage) return
        ensurePlaybackApisInjected()
        Log.d(TAG, "applyAudioLanguageJs lang=$lang scheduleRetries=$scheduleRetries")
        w.evaluateJavascript(GatewayPlaybackJs.eaMaxAudioLanguageApiScript(), null)
        w.evaluateJavascript(
            "(function(){" +
                "try{" +
                "window.__eaMaxPreferredAudioLang='$lang';" +
                "if(window.__eaMaxSetAudioLanguage){window.__eaMaxSetAudioLanguage('$lang');}" +
                "}catch(e){}" +
                "})();",
            null,
        )
        if (scheduleRetries) {
            listOf(200L, 500L, 1000L, 2000L).forEach { delayMs ->
                postDelayed({
                    if (audioLanguageConfirmed) return@postDelayed
                    applyAudioLanguageJs(lang, scheduleRetries = false)
                }, delayMs)
            }
        }
    }

    private fun postDelayed(block: () -> Unit, delayMs: Long) {
        val r = Runnable { block() }
        pendingRunnables.add(r)
        mainHandler.postDelayed(r, delayMs)
    }

    private fun cancelPendingRunnables() {
        pendingRunnables.forEach { mainHandler.removeCallbacks(it) }
        pendingRunnables.clear()
    }

    private fun normalizeAudioLanguage(raw: String): String {
        val v = raw.trim().lowercase()
        return if (v == "en" || v.startsWith("en-") || v == "eng") "en" else "sw"
    }
}

class WebViewJsInterface(
    private val onPlaybackStateChanged: (PlaybackState) -> Unit,
    private val onError: (String) -> Unit,
    private val onAudioProbe: (wanted: String, applied: Boolean) -> Unit = { _, _ -> },
    private val onQualityProbe: (wanted: String, maxH: Int, activeH: Int, applied: Boolean) -> Unit =
        { _, _, _, _ -> },
) {
    @android.webkit.JavascriptInterface
    fun onPlaybackStarted() { onPlaybackStateChanged(PlaybackState.PLAYING) }

    @android.webkit.JavascriptInterface
    fun onPlaybackPaused() { onPlaybackStateChanged(PlaybackState.PAUSED) }

    @android.webkit.JavascriptInterface
    fun onPlaybackTick(seconds: Int) {}

    @android.webkit.JavascriptInterface
    fun onPlaybackError(errorMessage: String) {
        onError("WebView Playback Error: $errorMessage")
    }

    @android.webkit.JavascriptInterface
    fun onPlaybackEnded() { onPlaybackStateChanged(PlaybackState.ENDED) }

    @android.webkit.JavascriptInterface
    fun onAudioLanguageProbe(json: String) {
        Log.d("EaMaxAudio", "probe: $json")
        try {
            val wanted = Regex(""""wanted"\s*:\s*"([^"]+)"""").find(json)?.groupValues?.get(1) ?: ""
            val applied = """"applied"\s*:\s*true""".toRegex().containsMatchIn(json)
            onAudioProbe(wanted, applied)
        } catch (_: Exception) { }
    }

    @android.webkit.JavascriptInterface
    fun onQualityProbe(json: String) {
        try {
            val players = Regex(""""players"\s*:\s*(\d+)""").find(json)?.groupValues?.get(1)?.toIntOrNull() ?: 0
            val applied = """"applied"\s*:\s*true""".toRegex().containsMatchIn(json)
            if (players > 0 || applied) {
                Log.d("EaMaxQuality", "probe: $json")
            }
            fun num(key: String) =
                Regex(""""$key"\s*:\s*(\d+)""").find(json)?.groupValues?.get(1)?.toIntOrNull() ?: 0
            val wanted = Regex(""""wanted"\s*:\s*"([^"]+)"""").find(json)?.groupValues?.get(1) ?: ""
            onQualityProbe(wanted, num("maxH"), num("activeH"), applied)
        } catch (_: Exception) { }
    }
}
