package com.washatv.player

import android.app.Activity
import android.graphics.Rect
import android.view.ViewGroup
import android.widget.FrameLayout
import com.washatv.domain.model.DrmData
import com.washatv.domain.model.DrmType
import com.washatv.domain.model.PlaybackState
import com.washatv.domain.model.PlayerMode
import com.washatv.domain.model.StreamSession
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.lang.ref.WeakReference

/**
 * Hosts gateway [WebViewEngine] on the Activity decor (not Flutter PlatformView).
 * Required on HiSilicon — PlatformView WebView plays audio but shows a blank surface.
 */
object EmbeddedPlayerHost {
    private const val EVENTS_CHANNEL = "com.washatv/embedded_player_events"

    private var container: FrameLayout? = null
    private var webViewEngine: WebViewEngine? = null
    private var activityRef: WeakReference<Activity>? = null
    private var eventsChannel: MethodChannel? = null
    private var generation = 0

    fun attach(
        activity: Activity,
        messenger: BinaryMessenger,
        url: String,
        headersJson: String,
        bounds: Rect,
    ) {
        detach()
        val gen = ++generation
        activityRef = WeakReference(activity)
        eventsChannel = MethodChannel(messenger, EVENTS_CHANNEL)

        val session = StreamSession(
            mpdUrl = url.trim(),
            licenseUrl = "",
            token = "",
            expiresAt = (System.currentTimeMillis() / 1000) + 86400,
            playerMode = PlayerMode.EXO,
            drmType = DrmType.NONE,
            drmData = DrmData(headers = null),
            trialRemaining = 999_999,
            channelIsPremium = false,
            headers = parseHeaders(headersJson),
        )

        webViewEngine = WebViewEngine(
            context = activity,
            onPlaybackStateChanged = { state ->
                if (gen != generation) return@WebViewEngine
                if (state == PlaybackState.PLAYING) {
                    eventsChannel?.invokeMethod("onPlaying", null)
                }
            },
            onError = {
                if (gen != generation) return@WebViewEngine
                eventsChannel?.invokeMethod("onError", null)
            },
            embeddedInPlatformView = false,
        )
        webViewEngine?.initialize(session)

        val wv = webViewEngine?.getWebView() ?: return
        (wv.parent as? ViewGroup)?.removeView(wv)

        val frame = FrameLayout(activity).apply {
            layoutParams = FrameLayout.LayoutParams(bounds.width(), bounds.height()).apply {
                leftMargin = bounds.left
                topMargin = bounds.top
            }
            addView(
                wv,
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        container = frame
        val root = activity.window.decorView.findViewById<ViewGroup>(android.R.id.content)
        root.addView(frame)
        frame.isClickable = false
        frame.isFocusable = false
        frame.setOnTouchListener { _, _ -> false }
        wv.isClickable = false
        wv.isFocusable = false
    }

    fun updateBounds(bounds: Rect) {
        val c = container ?: return
        val lp = (c.layoutParams as? FrameLayout.LayoutParams)
            ?: FrameLayout.LayoutParams(bounds.width(), bounds.height())
        lp.width = bounds.width()
        lp.height = bounds.height()
        lp.leftMargin = bounds.left
        lp.topMargin = bounds.top
        c.layoutParams = lp
    }

    fun pauseForHandoff() {
        webViewEngine?.pauseForHandoff()
        container?.visibility = android.view.View.GONE
    }

    fun resumeAfterHandoff() {
        container?.visibility = android.view.View.VISIBLE
        webViewEngine?.resumeAfterHandoff()
    }

    fun detach() {
        generation++
        webViewEngine?.release()
        webViewEngine = null
        val root = activityRef?.get()?.window?.decorView?.findViewById<ViewGroup>(android.R.id.content)
        container?.let { root?.removeView(it) }
        container = null
        activityRef = null
    }

    private fun parseHeaders(json: String): Map<String, String> {
        if (json.isEmpty()) return emptyMap()
        return try {
            val o = JSONObject(json)
            buildMap {
                val it = o.keys()
                while (it.hasNext()) {
                    val k = it.next()
                    put(k, o.optString(k))
                }
            }
        } catch (_: Exception) {
            emptyMap()
        }
    }
}
