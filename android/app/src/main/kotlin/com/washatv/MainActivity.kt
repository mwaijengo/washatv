package com.washatv

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import com.washatv.player.EmbeddedPlayerHost
import com.washatv.player.GatewayWebPlayerFactory
import com.washatv.player.GatewayWebPlayerRegistry
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val NATIVE_PLAYER_REQUEST = 48291
    }

    private val secureChannel = "com.washatv/secure"
    private val nativePlayerChannel = "com.washatv/native_player"
    private val gatewayPlayerChannel = "com.washatv/gateway_web_player"
    private val embeddedPlayerChannel = "com.washatv/embedded_player"

    private var nativeOpenResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        Handler(Looper.getMainLooper()).post {
            try {
                WebView(applicationContext).apply {
                    settings.javaScriptEnabled = true
                    loadUrl("about:blank")
                    destroy()
                }
            } catch (_: Exception) {
            }
        }
    }

    override fun onDestroy() {
        EmbeddedPlayerHost.detach()
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        flutterEngine?.let { registerEmbeddedPlayerChannel(it) }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == NATIVE_PLAYER_REQUEST) {
            nativeOpenResult?.success(null)
            nativeOpenResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "com.washatv/gateway_web_player",
                GatewayWebPlayerFactory(flutterEngine.dartExecutor.binaryMessenger),
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: true
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativePlayerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any?>
                        if (args == null) {
                            result.error("bad_args", "Expected map", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(this, WashaNativePlayerActivity::class.java)
                            intent.putExtra("url", args["url"]?.toString().orEmpty())
                            intent.putExtra("licenseUrl", args["licenseUrl"]?.toString().orEmpty())
                            intent.putExtra("token", args["token"]?.toString().orEmpty())
                            intent.putExtra(
                                "drmType",
                                args["drmType"]?.toString().orEmpty().ifEmpty { "NONE" },
                            )
                            val mergedClearKey = sequenceOf(
                                args["clearKeyHex"]?.toString(),
                                args["drmClearKey"]?.toString(),
                                args["drm_clear_key"]?.toString(),
                            ).firstOrNull { !it.isNullOrBlank() }.orEmpty()
                            intent.putExtra("clearKeyHex", mergedClearKey)
                            intent.putExtra("headersJson", args["headersJson"]?.toString().orEmpty())
                            intent.putExtra(
                                "audioLanguage",
                                args["audioLanguage"]?.toString().orEmpty().ifEmpty { "sw" },
                            )
                            nativeOpenResult = result
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, NATIVE_PLAYER_REQUEST)
                        } catch (e: Exception) {
                            nativeOpenResult = null
                            result.error(
                                "native_open_failed",
                                e.message ?: "Failed to open player",
                                null,
                            )
                        }
                    }
                    "updatePlayerConfig" -> result.success(null)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, gatewayPlayerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pause" -> {
                        val viewId = call.argument<Int>("viewId") ?: return@setMethodCallHandler result.success(null)
                        GatewayWebPlayerRegistry.pause(viewId)
                        result.success(null)
                    }
                    "resume" -> {
                        val viewId = call.argument<Int>("viewId") ?: return@setMethodCallHandler result.success(null)
                        GatewayWebPlayerRegistry.resume(viewId)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        registerEmbeddedPlayerChannel(flutterEngine)
    }

    private fun registerEmbeddedPlayerChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, embeddedPlayerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "attach" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any?>
                        if (args == null) {
                            result.error("bad_args", "Expected map", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val left = (args["left"] as? Number)?.toInt() ?: 0
                            val top = (args["top"] as? Number)?.toInt() ?: 0
                            val width = (args["width"] as? Number)?.toInt() ?: 0
                            val height = (args["height"] as? Number)?.toInt() ?: 0
                            EmbeddedPlayerHost.attach(
                                activity = this,
                                messenger = flutterEngine.dartExecutor.binaryMessenger,
                                url = args["url"]?.toString().orEmpty(),
                                headersJson = args["headersJson"]?.toString().orEmpty(),
                                bounds = Rect(left, top, left + width, top + height),
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("attach_failed", e.message, null)
                        }
                    }
                    "updateBounds" -> {
                        val args = call.arguments as? Map<String, Any?>
                        if (args == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val left = (args["left"] as? Number)?.toInt() ?: 0
                        val top = (args["top"] as? Number)?.toInt() ?: 0
                        val width = (args["width"] as? Number)?.toInt() ?: 0
                        val height = (args["height"] as? Number)?.toInt() ?: 0
                        EmbeddedPlayerHost.updateBounds(Rect(left, top, left + width, top + height))
                        result.success(null)
                    }
                    "detach" -> {
                        EmbeddedPlayerHost.detach()
                        result.success(null)
                    }
                    "pause" -> {
                        EmbeddedPlayerHost.pauseForHandoff()
                        result.success(null)
                    }
                    "resume" -> {
                        EmbeddedPlayerHost.resumeAfterHandoff()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
