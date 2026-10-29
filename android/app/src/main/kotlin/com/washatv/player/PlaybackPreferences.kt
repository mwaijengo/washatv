package com.washatv.player

/** Viewer playback prefs pushed from Flutter settings (quality, zoom, data saver). */
data class PlaybackPreferences(
    val dataSaver: Boolean = false,
    val defaultQuality: String = "",
    val videoZoomMode: String = "zoom",
) {
    fun maxVideoHeight(): Int {
        if (dataSaver) return 360
        return when (defaultQuality.lowercase().trim()) {
            "240p", "240" -> 240
            "360p", "360" -> 360
            "480p", "480" -> 480
            "720p", "720" -> 720
            "1080p", "1080" -> 1080
            "auto", "" -> Int.MAX_VALUE
            else -> Int.MAX_VALUE
        }
    }

    companion object {
        private var cached = PlaybackPreferences()

        fun update(
            dataSaver: Boolean,
            defaultQuality: String,
            videoZoomMode: String,
        ) {
            cached = PlaybackPreferences(
                dataSaver = dataSaver,
                defaultQuality = defaultQuality,
                videoZoomMode = videoZoomMode,
            )
        }

        fun current(): PlaybackPreferences = cached
    }
}
