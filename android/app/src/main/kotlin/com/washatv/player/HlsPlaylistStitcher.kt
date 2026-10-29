package com.washatv.player

import android.net.Uri
import android.util.Log
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody

/**
 * Live bridges often restart `#EXT-X-MEDIA-SEQUENCE` when they rotate CDN hosts.
 * ExoPlayer treats that jump as a playlist reset and tears the decoder down.
 * Rewriting the sequence so it keeps increasing lets the same player continue.
 */
object HlsPlaylistStitcher {
    private const val TAG = "HlsPlaylistStitcher"
    private const val MAX_PLAYLIST_CHARS = 1_500_000

    private val mediaSequencePattern = Regex("""#EXT-X-MEDIA-SEQUENCE:(\d+)""")
    private val discontinuitySequencePattern = Regex("""#EXT-X-DISCONTINUITY-SEQUENCE:(\d+)""")
    private val extInfPattern = Regex("""#EXTINF:""")

    private data class Snapshot(
        val serverSequence: Long,
        val publishedSequence: Long,
        val segmentCount: Int,
        val discontinuitySequence: Int,
    )

    private val lock = Any()
    private val lastByPlaylist = HashMap<String, Snapshot>()

    fun reset() {
        synchronized(lock) {
            lastByPlaylist.clear()
        }
    }

    fun maybeRewrite(response: Response): Response {
        val body = response.body ?: return response
        val contentLength = body.contentLength()
        if (contentLength > MAX_PLAYLIST_CHARS) return response
        val prefix = try {
            val peeked = body.source().peek()
            peeked.request(48)
            val size = minOf(peeked.buffer.size, 48)
            if (size <= 0L) return response
            peeked.buffer.clone().readUtf8(size)
        } catch (_: Exception) {
            return response
        }
        if (!prefix.contains("#EXTM3U")) return response

        val mediaType = body.contentType()
        val raw = try {
            body.string()
        } catch (_: Exception) {
            return response
        }
        val rewritten = rewrite(response.request.url.toString(), raw)
        val bytes = rewritten.toByteArray(Charsets.UTF_8)
        return response.newBuilder()
            .body(bytes.toResponseBody(mediaType))
            .header("Content-Length", bytes.size.toString())
            .build()
    }

    internal fun rewrite(rawUrl: String, playlist: String): String {
        if (playlist.length > MAX_PLAYLIST_CHARS) return playlist
        if (!playlist.contains("#EXT-X-MEDIA-SEQUENCE:")) return playlist
        val sequenceMatch = mediaSequencePattern.find(playlist) ?: return playlist
        val sequence = sequenceMatch.groupValues[1].toLongOrNull() ?: return playlist
        val segmentCount = extInfPattern.findAll(playlist).count()
        if (segmentCount <= 0) return playlist
        val discontinuityMatch = discontinuitySequencePattern.find(playlist)
        val discontinuity = discontinuityMatch?.groupValues?.get(1)?.toIntOrNull() ?: 0
        val key = playlistKey(rawUrl)

        synchronized(lock) {
            val previous = lastByPlaylist[key]
            if (previous == null) {
                lastByPlaylist[key] = Snapshot(sequence, sequence, segmentCount, discontinuity)
                return playlist
            }
            val rawOverlaps = sequence + segmentCount >= previous.publishedSequence &&
                sequence >= previous.publishedSequence - previous.segmentCount
            if (rawOverlaps) {
                if (sequence >= previous.publishedSequence) {
                    lastByPlaylist[key] = Snapshot(
                        serverSequence = sequence,
                        publishedSequence = sequence,
                        segmentCount = segmentCount,
                        discontinuitySequence = previous.discontinuitySequence,
                    )
                }
                return playlist
            }
            val offset = previous.publishedSequence - previous.serverSequence
            val projected = sequence + offset
            val overlaps = projected + segmentCount >= previous.publishedSequence
            if (overlaps) {
                if (sequence >= previous.serverSequence) {
                    lastByPlaylist[key] = previous.copy(
                        serverSequence = sequence,
                        publishedSequence = projected,
                        segmentCount = segmentCount,
                    )
                }
                if (projected == sequence) return playlist
                return replaceMediaSequence(playlist, sequenceMatch.value, projected)
            }
            val nextSequence = previous.publishedSequence + previous.segmentCount
            val nextDiscontinuity = previous.discontinuitySequence + 1
            var updated = replaceMediaSequence(playlist, sequenceMatch.value, nextSequence)
            val rewrittenDisc = discontinuitySequencePattern.find(updated)
            updated = if (rewrittenDisc != null) {
                updated.replace(
                    rewrittenDisc.value,
                    "#EXT-X-DISCONTINUITY-SEQUENCE:$nextDiscontinuity",
                )
            } else {
                updated.replace(
                    "#EXT-X-MEDIA-SEQUENCE:$nextSequence",
                    "#EXT-X-DISCONTINUITY-SEQUENCE:$nextDiscontinuity\n#EXT-X-MEDIA-SEQUENCE:$nextSequence",
                )
            }
            val firstSegment = updated.indexOf("#EXTINF:")
            if (firstSegment >= 0) {
                val before = updated.substring(0, firstSegment).trimEnd()
                if (!before.endsWith("#EXT-X-DISCONTINUITY")) {
                    updated = updated.replaceFirst("#EXTINF:", "#EXT-X-DISCONTINUITY\n#EXTINF:")
                }
            }
            lastByPlaylist[key] = Snapshot(
                serverSequence = sequence,
                publishedSequence = nextSequence,
                segmentCount = segmentCount,
                discontinuitySequence = nextDiscontinuity,
            )
            Log.i(
                TAG,
                "stitched media sequence $sequence -> $nextSequence segments=$segmentCount",
            )
            return updated
        }
    }

    private fun replaceMediaSequence(playlist: String, currentTag: String, sequence: Long): String {
        return playlist.replace(currentTag, "#EXT-X-MEDIA-SEQUENCE:$sequence")
    }

    private fun playlistKey(rawUrl: String): String {
        val uri = Uri.parse(rawUrl)
        val scheme = uri.scheme ?: "http"
        val host = uri.host ?: rawUrl
        val port = if (uri.port > 0) ":${uri.port}" else ""
        return "$scheme://$host$port${uri.path.orEmpty()}"
    }
}
