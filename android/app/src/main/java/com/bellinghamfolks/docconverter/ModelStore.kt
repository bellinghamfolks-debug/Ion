package com.bellinghamfolks.docconverter

import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Generic download-to-file helper (with precise progress) used to pre-fetch the
 * on-device PaddleOCR models before starting, so the reader finds them ready and
 * works offline.
 */
object ModelStore {

    /** Download url -> f with 0..100 progress derived from Content-Length. */
    fun download(url: String, f: File, onProgress: (Int) -> Unit): Boolean {
        var conn: HttpURLConnection? = null
        return try {
            conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 20000
            conn.readTimeout = 240000
            conn.instanceFollowRedirects = true
            if (conn.responseCode !in 200..299) return false
            val total = conn.contentLengthLong
            conn.inputStream.use { input ->
                f.outputStream().use { out ->
                    val buf = ByteArray(64 * 1024)
                    var read = 0L
                    var got: Int
                    while (input.read(buf).also { got = it } >= 0) {
                        out.write(buf, 0, got)
                        read += got
                        if (total > 0) onProgress(((read * 100) / total).toInt().coerceIn(0, 100))
                    }
                }
            }
            f.exists() && f.length() > 0
        } catch (e: Exception) { false } finally { conn?.disconnect() }
    }
}
