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
