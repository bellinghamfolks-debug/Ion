package com.bellinghamfolks.docconverter

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Downloads the on-device model files (with precise progress) to the SAME paths
 * the reader already reads from, so pre-downloading here means the service finds
 * them ready and skips its own fetch. Tesseract lives in filesDir/tessdata/;
 * PaddleOCR download is handled by PaddleOcr itself (same generic downloader).
 */
object ModelStore {
    const val TESS_VARIANT = "best"
    private val TESS_LANGS = listOf("ara", "eng")

    fun tessDir(ctx: Context) = File(ctx.filesDir, "tessdata")

    fun tessPresent(ctx: Context): Boolean {
        val tess = tessDir(ctx)
        val marker = File(tess, ".variant")
        val variant = if (marker.exists()) marker.runCatching { readText().trim() }.getOrDefault("") else ""
        if (variant != TESS_VARIANT) return false
        return TESS_LANGS.all { File(tess, "$it.traineddata").let { f -> f.exists() && f.length() > 0 } }
    }

    /** Download tessdata_best (ara+eng). onProgress reports 0..100. null = success. */
    fun downloadTess(ctx: Context, onProgress: (Int) -> Unit): String? {
        return try {
            val tess = tessDir(ctx).apply { mkdirs() }
            val marker = File(tess, ".variant")
            val variant = if (marker.exists()) marker.runCatching { readText().trim() }.getOrDefault("") else ""
            if (variant != TESS_VARIANT) TESS_LANGS.forEach { File(tess, "$it.traineddata").delete() }
            val n = TESS_LANGS.size
            for ((i, lang) in TESS_LANGS.withIndex()) {
                val f = File(tess, "$lang.traineddata")
                if (f.exists() && f.length() > 0) { onProgress(((i + 1) * 100) / n); continue }
                val url = "https://github.com/tesseract-ocr/tessdata_best/raw/main/$lang.traineddata"
                DiagLog.log("DL", "tess $lang start")
                val ok = download(url, f) { p -> onProgress(((i * 100) + p) / n) }
                if (!ok) { DiagLog.log("DL", "tess $lang FAILED"); return "tess_${lang}_download" }
                DiagLog.log("DL", "tess $lang done ${f.length()}B")
            }
            marker.runCatching { writeText(TESS_VARIANT) }
            onProgress(100)
            null
        } catch (e: Exception) { DiagLog.err("DL", e); "tess:" + (e.message ?: "err").take(40) }
    }

    /** Generic download-to-file with 0..100 progress derived from Content-Length. */
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
