package com.washatv.player

import android.net.Uri

/** Mirrors Dart [playback_http_headers.dart]. */
object PlaybackHttpHeaders {

    private val BROWSER_ONLY_HEADERS = setOf(
        "sec-fetch-dest",
        "sec-fetch-mode",
        "sec-fetch-site",
        "sec-fetch-user",
        "upgrade-insecure-requests",
        "sec-ch-ua",
        "sec-ch-ua-mobile",
        "sec-ch-ua-platform",
    )

    /**
     * Direct playlists, files, IPTV live paths, and plain HTTP streams.
     * Page headers (Origin, Referer of the stream host) make these servers return 403.
     * `.php` gateways and `tok_<jwt>` CDNs are not direct media.
     */
    fun isDirectMediaUrl(rawUrl: String): Boolean {
        val trimmed = rawUrl.trim()
        if (trimmed.isEmpty()) return false
        if (trimmed.contains(".php", ignoreCase = true)) return false
        if (CdnTokenHeaders.isTokenizedCdnUrl(trimmed)) return false
        val uri = runCatching { Uri.parse(trimmed) }.getOrNull() ?: return false
        val path = uri.path?.lowercase().orEmpty()
        if (path.endsWith(".m3u8") ||
            path.endsWith(".m3u") ||
            path.endsWith(".mpd") ||
            path.endsWith(".mp4") ||
            path.endsWith(".m4v") ||
            path.endsWith(".ts") ||
            path.endsWith(".mkv") ||
            path.endsWith(".webm")
        ) {
            return true
        }
        if (StreamUrlClassifier.isLikelyIptvLiveUrl(trimmed)) return true
        val scheme = uri.scheme?.lowercase().orEmpty()
        if (scheme == "http" && !isDocumentPath(path)) return true
        return false
    }

    fun defaultsForUrl(rawUrl: String): Map<String, String> {
        val trimmed = rawUrl.trim()
        if (trimmed.isEmpty()) return emptyMap()
        val uri = runCatching { Uri.parse(trimmed) }.getOrNull() ?: return emptyMap()
        if (uri.scheme.isNullOrBlank() || uri.host.isNullOrBlank()) return emptyMap()
        if (!uri.scheme.equals("http", ignoreCase = true) &&
            !uri.scheme.equals("https", ignoreCase = true)
        ) return emptyMap()

        if (isDirectMediaUrl(trimmed)) {
            return linkedMapOf(
                "User-Agent" to OrizonStreamClient.USER_AGENT,
                "Accept" to "*/*",
                "Accept-Language" to "en-US,en;q=0.9,sw;q=0.8",
                "Connection" to "keep-alive",
            )
        }

        val port = when (uri.port) {
            -1, 80, 443 -> ""
            else -> ":${uri.port}"
        }
        val cdnOrigin = "${uri.scheme}://${uri.host}$port"
        val tokenPair = CdnTokenHeaders.refererOriginForUrl(trimmed)
        val referer = tokenPair?.first ?: "$cdnOrigin/"
        val origin = tokenPair?.second ?: cdnOrigin

        val headers = linkedMapOf(
            "Referer" to referer,
            "Origin" to origin,
            "User-Agent" to OrizonStreamClient.USER_AGENT,
            "Connection" to "keep-alive",
            "Accept-Language" to "en-US,en;q=0.9,sw;q=0.8",
            "Accept" to
                "text/html,application/xhtml+xml,application/xml;q=0.9," +
                "application/dash+xml,application/vnd.apple.mpegurl;q=0.8,*/*;q=0.7",
        )
        if (trimmed.contains(".php", ignoreCase = true)) {
            headers["X-Requested-With"] = "com.washatv"
        }
        return headers
    }

    fun merge(sessionHeaders: Map<String, String>, streamUrl: String): LinkedHashMap<String, String> {
        val merged = LinkedHashMap<String, String>()
        fun putHeader(rawName: String, rawValue: String) {
            val name = canonicalName(rawName.trim())
            val value = rawValue.trim()
            if (name.isEmpty() || value.isEmpty()) return
            merged.keys.firstOrNull { it.equals(name, ignoreCase = true) }?.let(merged::remove)
            merged[name] = value
        }
        defaultsForUrl(streamUrl).forEach(::putHeader)
        sessionHeaders.forEach(::putHeader)
        putHeader("User-Agent", merged["User-Agent"] ?: OrizonStreamClient.USER_AGENT)
        putHeader("Accept", merged["Accept"] ?: "*/*")
        putHeader("Connection", merged["Connection"] ?: "keep-alive")
        if (isDirectMediaUrl(streamUrl)) {
            val drop = merged.keys.filter { it.lowercase() in BROWSER_ONLY_HEADERS }
            drop.forEach { merged.remove(it) }
            val host = runCatching { Uri.parse(streamUrl.trim()).host }.getOrNull()
                ?.lowercase()
                .orEmpty()
            if (host.isNotEmpty()) {
                val originKey = merged.keys.firstOrNull { it.equals("Origin", ignoreCase = true) }
                val refererKey = merged.keys.firstOrNull { it.equals("Referer", ignoreCase = true) }
                if (originKey != null && merged[originKey].orEmpty().lowercase().contains(host)) {
                    merged.remove(originKey)
                }
                if (refererKey != null && merged[refererKey].orEmpty().lowercase().contains(host)) {
                    merged.remove(refererKey)
                }
            }
            merged["Accept"] = "*/*"
        }
        return merged
    }

    private fun isDocumentPath(path: String): Boolean {
        return path.endsWith(".html") ||
            path.endsWith(".htm") ||
            path.endsWith(".asp") ||
            path.endsWith(".aspx") ||
            path.endsWith(".cgi") ||
            path.endsWith(".jsp")
    }

    private fun canonicalName(name: String): String = when (name.lowercase()) {
        "referer" -> "Referer"
        "origin" -> "Origin"
        "user-agent" -> "User-Agent"
        "accept" -> "Accept"
        "accept-language" -> "Accept-Language"
        "authorization" -> "Authorization"
        "content-type" -> "Content-Type"
        "connection" -> "Connection"
        "x-requested-with" -> "X-Requested-With"
        else -> name
    }
}
