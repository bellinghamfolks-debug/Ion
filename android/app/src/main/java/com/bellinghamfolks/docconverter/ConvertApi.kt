package com.bellinghamfolks.docconverter

import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection

/** Talks to the shared Ion backend for live-reader OCR/description. */
object ConvertApi {
    const val BASE = "https://ion-production-da28.up.railway.app"

    /**
     * Live analysis of one camera frame -> text (Arabic + English).
     * mode = "ocr" reads visible text verbatim; mode = "describe" returns a rich
     * live scene narration for a blind user.
     */
    suspend fun liveOcr(jpeg: ByteArray, model: String, mode: String = "ocr"): String = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("imageBase64", Base64.encodeToString(jpeg, Base64.NO_WRAP))
            .put("model", model)
            .put("mode", mode)
        // Short read timeout for the live reader: if Gemini is having a latency
        // spike, abandon at 20s and let the next frame retry rather than freezing.
        JSONObject(postJson("$BASE/convert/live-ocr", body.toString(), 20000)).optString("text", "")
    }

    /**
     * Streaming live OCR/description. Streams the recognized text as Gemini
     * generates it; `onSentence` is invoked with each COMPLETE sentence (the app
     * buffers words until a sentence boundary so TTS gets natural intonation).
     * Returns the full text when the stream ends.
     */
    suspend fun liveOcrStream(
        jpeg: ByteArray, model: String, mode: String, onSentence: (String) -> Unit,
    ): String = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("imageBase64", Base64.encodeToString(jpeg, Base64.NO_WRAP))
            .put("model", model)
            .put("mode", mode)
        val conn = NetManager.open("$BASE/convert/live-ocr-stream")
        val t0 = System.currentTimeMillis()
        try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 20000
            // Bound how old a camera result can become. The service continues
            // observing frames and will discard stale output, but a live reader
            // must not remain blocked on one request for half a minute.
            conn.readTimeout = 12000
            conn.setRequestProperty("Content-Type", "application/json")
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            if (code !in 200..299) {
                val err = conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                DiagLog.log("HTTP", "STREAM live-ocr -> $code in ${System.currentTimeMillis() - t0}ms")
                throw RuntimeException("HTTP $code: ${err.take(200)}")
            }
            val full = StringBuilder()
            val sent = StringBuilder()
            conn.inputStream.bufferedReader(Charsets.UTF_8).use { r ->
                val cbuf = CharArray(512)
                while (true) {
                    val n = r.read(cbuf)
                    if (n < 0) break
                    for (i in 0 until n) {
                        val c = cbuf[i]
                        full.append(c); sent.append(c)
                        // Flush a complete sentence to TTS at a natural boundary.
                        if (isSentenceEnd(c) && sent.toString().trim().length >= 2) {
                            val s = sent.toString().trim(); sent.setLength(0)
                            if (s.isNotEmpty()) onSentence(s)
                        }
                    }
                }
            }
            val rem = sent.toString().trim()
            if (rem.isNotEmpty()) onSentence(rem)
            DiagLog.log("HTTP", "STREAM live-ocr done ${full.length} chars in ${System.currentTimeMillis() - t0}ms")
            full.toString().trim()
        } finally { conn.disconnect() }
    }

    /** Sentence terminators (Arabic + Latin) that end a TTS chunk. */
    private fun isSentenceEnd(c: Char): Boolean =
        c == '.' || c == '!' || c == '?' || c == '\n' ||
        c == '،' || c == '؛' || c == '؟' || c == ':' || c == '؍'

    // ---- HTTP helpers (no third-party deps) --------------------------------
    private fun postJson(urlStr: String, json: String, readTimeoutMs: Int = 90000): String {
        val t0 = System.currentTimeMillis()
        val conn = NetManager.open(urlStr)
        try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 20000
            conn.readTimeout = readTimeoutMs
            conn.setRequestProperty("Content-Type", "application/json")
            conn.outputStream.use { it.write(json.toByteArray(Charsets.UTF_8)) }
            val out = readResponse(conn)
            DiagLog.log("HTTP", "POST ${urlStr.substringAfterLast('/')} -> ${conn.responseCode} in ${System.currentTimeMillis() - t0}ms")
            return out
        } catch (e: Exception) {
            DiagLog.log("HTTP", "POST ${urlStr.substringAfterLast('/')} FAILED in ${System.currentTimeMillis() - t0}ms: ${e.message}")
            throw e
        } finally { conn.disconnect() }
    }

    private fun readResponse(conn: HttpURLConnection): String {
        val code = conn.responseCode
        val stream = if (code in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() } ?: ""
        if (code !in 200..299) throw RuntimeException("HTTP $code: ${text.take(200)}")
        return text
    }
}
