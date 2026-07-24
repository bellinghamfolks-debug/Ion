package com.bellinghamfolks.docconverter

import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

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

    /** Live OCR of one camera frame -> visible text (Arabic + English). */
    suspend fun liveOcr(jpeg: ByteArray, model: String): String = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("imageBase64", Base64.encodeToString(jpeg, Base64.NO_WRAP))
            .put("model", model)
        JSONObject(postJson("$BASE/convert/live-ocr", body.toString())).optString("text", "")
    }

    // ---- HTTP helpers (no third-party deps) --------------------------------
    private fun postJson(urlStr: String, json: String): String {
        val conn = URL(urlStr).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 20000
            conn.readTimeout = 90000
            conn.setRequestProperty("Content-Type", "application/json")
            conn.outputStream.use { it.write(json.toByteArray(Charsets.UTF_8)) }
            return readResponse(conn)
        } finally { conn.disconnect() }
    }

    private fun getText(urlStr: String): String {
        val conn = URL(urlStr).openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 20000
            conn.readTimeout = 60000
            return readResponse(conn)
        } finally { conn.disconnect() }
    }

    private fun getBytes(urlStr: String): ByteArray {
        val conn = URL(urlStr).openConnection() as HttpURLConnection
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
