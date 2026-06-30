package com.washatv.player

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.washatv.domain.model.StreamSession
import com.washatv.domain.model.DrmData
import com.washatv.domain.model.DrmType
import com.washatv.domain.model.PlaybackState
import com.washatv.domain.model.PlayerMode
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONObject

/** Embeds [WebViewEngine] inside Flutter [PlayerScreen] for gateway / PHP streams. */
class GatewayWebPlayerPlatformView(
    context: Context,
    private val viewId: Int,
    args: Map<String, Any?>,
    messenger: BinaryMessenger,
) : PlatformView {

    private val appContext: Context = context.applicationContext
    private val webViewEngine: WebViewEngine
    private val container = FrameLayout(context)
    private val channel = MethodChannel(messenger, "com.washatv/gateway_web_player")

    init {
        val url = args["url"]?.toString().orEmpty().trim()
        val headersJson = args["headersJson"]?.toString().orEmpty()
        val session = StreamSession(
            mpdUrl = url,
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

        val embedded = args["embedded"] as? Boolean ?: true

        webViewEngine = WebViewEngine(
            context = context,
            onPlaybackStateChanged = { state ->
                if (state == PlaybackState.PLAYING) {
                    channel.invokeMethod("onPlaying", mapOf("viewId" to viewId))
                }
            },
            onError = {
                channel.invokeMethod("onError", mapOf("viewId" to viewId))
            },
            embeddedInPlatformView = embedded,
        )
        webViewEngine.initialize(session)
        webViewEngine.getWebView()?.let { wv ->
            (wv.parent as? ViewGroup)?.removeView(wv)
            container.addView(
                wv,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        GatewayWebPlayerRegistry.register(viewId, this)
    }

    fun pauseForHandoff() {
        webViewEngine.pauseForHandoff()
    }

    fun resumeAfterHandoff() {
        webViewEngine.resumeAfterHandoff()
    }

    override fun getView(): View = container

    override fun dispose() {
        GatewayWebPlayerRegistry.unregister(viewId)
        webViewEngine.release()
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
