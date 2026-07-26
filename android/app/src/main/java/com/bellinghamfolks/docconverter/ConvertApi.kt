package com.bellinghamfolks.docconverter

import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection

/** Talks to the shared Ion backend (same server as the iOS app). */
object ConvertApi {
    const val BASE = "https://ion-production-da28.up.railway.app"

    data class JobStatus(val status: String, val done: Int, val total: Int, val failed: Int)

    suspend fun createJob(pdf: ByteArray, filename: String, model: String): String = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("filename", filename)
            .put("model", model)
            .put("mode", "accessible")
            .put("options", JSONObject())
            .put("pdfBase64", Base64.encodeToString(pdf, Base64.NO_WRAP))
        JSONObject(postJson("$BASE/convert/jobs", body.toString())).getString("jobId")
    }

    suspend fun status(jobId: String): JobStatus = withContext(Dispatchers.IO) {
        val o = JSONObject(getText("$BASE/convert/jobs/$jobId"))
        JobStatus(o.getString("status"), o.optInt("donePages"), o.optInt("totalPages"), o.optInt("failedPages"))
    }

    suspend fun downloadDocx(jobId: String): ByteArray = withContext(Dispatchers.IO) {
        getBytes("$BASE/convert/jobs/$jobId/result.docx")
    }

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

    private fun getText(urlStr: String): String {
        val conn = NetManager.open(urlStr)
        try {
            conn.connectTimeout = 20000
            conn.readTimeout = 60000
            return readResponse(conn)
        } finally { conn.disconnect() }
    }

    private fun getBytes(urlStr: String): ByteArray {
        val conn = NetManager.open(urlStr)
        try {
            conn.connectTimeout = 20000
            conn.readTimeout = 120000
            val code = conn.responseCode
            if (code !in 200..299) throw RuntimeException("HTTP $code")
            return conn.inputStream.readBytes()
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
