package com.washatv.player

import android.content.Context
import android.graphics.Color
import android.os.Message
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout

/** WebView settings tuned for PHP gateways and Google reCAPTCHA challenges. */
object GatewayWebViewHelper {

    /** Chrome-like UA without the WebView `; wv` token — reCAPTCHA often blocks WebView UAs. */
    fun browserUserAgent(context: Context): String {
        val default = WebSettings.getDefaultUserAgent(context)
        return when {
            default.contains("; wv") -> default.replace("; wv", "")
            default.contains(" wv ") -> default.replace(" wv ", " ")
            else -> default
        }
    }

    fun applySettings(webView: WebView, context: Context, userAgent: String? = null) {
        webView.setBackgroundColor(Color.BLACK)
        webView.settings.apply {
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
            loadsImagesAutomatically = true
            blockNetworkImage = false
            cacheMode = WebSettings.LOAD_DEFAULT
            setSupportZoom(true)
            builtInZoomControls = false
            displayZoomControls = false
            userAgentString = userAgent?.takeIf { it.isNotBlank() } ?: browserUserAgent(context)
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
    }

    /**
     * Handles reCAPTCHA popups (`window.open`) by hosting a child WebView over the player container.
     */
    fun createChromeClient(
        hostWebView: WebView,
        onConsoleMessage: ((android.webkit.ConsoleMessage?) -> Unit)? = null,
    ): WebChromeClient {
        return object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message,
            ): Boolean {
                val popup = WebView(view.context)
                applySettings(popup, view.context, view.settings.userAgentString)
                popup.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        w: WebView,
                        request: android.webkit.WebResourceRequest,
                    ): Boolean = false
                }
                popup.webChromeClient = object : WebChromeClient() {
                    override fun onCloseWindow(window: WebView) {
                        dismissPopup(window)
                    }
                }
                val parent = view.parent as? ViewGroup
                    ?: (hostWebView.parent as? ViewGroup)
                    ?: return false
                parent.addView(
                    popup,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    ),
                )
                val transport = resultMsg.obj as? WebView.WebViewTransport ?: return false
                transport.webView = popup
                resultMsg.sendToTarget()
                return true
            }

            override fun onCloseWindow(window: WebView) {
                dismissPopup(window)
            }

            override fun onPermissionRequest(request: android.webkit.PermissionRequest?) {
                request?.grant(request.resources)
            }

            override fun onConsoleMessage(
                consoleMessage: android.webkit.ConsoleMessage?,
            ): Boolean {
                onConsoleMessage?.invoke(consoleMessage)
                return true
            }
        }
    }

    private fun dismissPopup(window: WebView) {
        (window.parent as? ViewGroup)?.removeView(window)
        window.stopLoading()
        window.destroy()
    }

    /** Returns `video` when a player element exists, `captcha` while reCAPTCHA is on screen. */
    const val PAGE_PROBE_JS = """
        (function(){
          try{
            if(document.querySelector('video')) return 'video';
            if(document.querySelector('iframe[src*="recaptcha"], iframe[src*="google.com/recaptcha"], .g-recaptcha, [data-sitekey]')) return 'captcha';
          }catch(e){}
          return 'waiting';
        })();
    """
}
