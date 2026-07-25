package com.bellinghamfolks.docconverter

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.FloatBuffer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * EXPERIMENTAL on-device Arabic OCR via PaddleOCR (PP-OCR) on ONNX Runtime.
 *
 * Pipeline: DB text detection -> per-box CRNN recognition with CTC decoding.
 * Models + the Arabic dictionary are downloaded once at runtime. This is
 * UNVERIFIED — the URLs and tensor plumbing are expected to need on-device
 * iteration; every failure point returns a tag the caller can speak aloud.
 */
class PaddleOcr(private val ctx: Context) {

    // Best-guess public ONNX model URLs. If the first run fails to download or
    // load, these are what to adjust (the service announces the failing stage).
    private val detUrl = "https://huggingface.co/SWHL/RapidOCR/resolve/main/PP-OCRv4/ch_PP-OCRv4_det_infer.onnx"
    private val recUrl = "https://huggingface.co/SWHL/RapidOCR/resolve/main/PP-OCRv3/multi_language/arabic_PP-OCRv3_rec_infer.onnx"
    private val dictUrl = "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/dict/arabic_dict.txt"

    private var env: OrtEnvironment? = null
    private var det: OrtSession? = null
    private var rec: OrtSession? = null
    private var dict: List<String> = emptyList()
    @Volatile private var isReady = false

    fun ready(): Boolean = isReady

    /** Download models + init sessions. Returns null on success, else an error tag. */
    fun setup(): String? {
        return try {
            val dir = File(ctx.filesDir, "paddle").apply { mkdirs() }
            ensure(dir, "det.onnx", detUrl) ?: return "det_download"
            ensure(dir, "rec.onnx", recUrl) ?: return "rec_download"
            val dictFile = ensure(dir, "arabic_dict.txt", dictUrl) ?: return "dict_download"
            dict = dictFile.readLines().map { it.trimEnd('\n', '\r') }
            val e = OrtEnvironment.getEnvironment()
            env = e
            det = e.createSession(File(dir, "det.onnx").absolutePath, OrtSession.SessionOptions())
            rec = e.createSession(File(dir, "rec.onnx").absolutePath, OrtSession.SessionOptions())
            isReady = true
            null
        } catch (ex: Exception) {
            "init:" + (ex.message ?: "err").take(40)
        }
    }

    private fun ensure(dir: File, name: String, url: String): File? {
        val f = File(dir, name)
        if (f.exists() && f.length() > 0) return f
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 20000
            conn.readTimeout = 240000
            conn.instanceFollowRedirects = true
            conn.inputStream.use { i -> f.outputStream().use { o -> i.copyTo(o) } }
            conn.disconnect()
            if (f.exists() && f.length() > 0) f else null
        } catch (e: Exception) { null }
    }

    fun close() {
        try { det?.close() } catch (_: Exception) {}
        try { rec?.close() } catch (_: Exception) {}
        isReady = false
    }

    fun recognize(src: Bitmap): String {
        val e = env ?: return ""
        val d = det ?: return ""
        val r = rec ?: return ""
        val boxes = try { detect(e, d, src) } catch (ex: Exception) { emptyList() }
        if (boxes.isEmpty()) return ""
        val sb = StringBuilder()
        for (b in boxes) {
            val line = try { recognizeBox(e, r, src, b) } catch (ex: Exception) { "" }
            if (line.isNotBlank()) sb.append(line).append('\n')
        }
        return sb.toString().trim()
    }

    // ---- Detection (DB) -----------------------------------------------------
    private data class Box(val x0: Int, val y0: Int, val x1: Int, val y1: Int)

    private fun detect(e: OrtEnvironment, sess: OrtSession, src: Bitmap): List<Box> {
        val maxSide = 960
        val scale = min(1f, maxSide.toFloat() / max(src.width, src.height))
        var tw = (src.width * scale).roundToInt().coerceAtLeast(32)
        var th = (src.height * scale).roundToInt().coerceAtLeast(32)
        tw -= tw % 32; if (tw < 32) tw = 32
        th -= th % 32; if (th < 32) th = 32
        val resized = Bitmap.createScaledBitmap(src, tw, th, true)
        val mean = floatArrayOf(0.485f, 0.456f, 0.406f)
        val std = floatArrayOf(0.229f, 0.224f, 0.225f)
        val area = tw * th
        val chw = FloatArray(3 * area)
        val px = IntArray(area)
        resized.getPixels(px, 0, tw, 0, 0, tw, th)
        for (i in px.indices) {
            val c = px[i]
            chw[i] = (((c shr 16) and 0xFF) / 255f - mean[0]) / std[0]
            chw[area + i] = (((c shr 8) and 0xFF) / 255f - mean[1]) / std[1]
            chw[2 * area + i] = ((c and 0xFF) / 255f - mean[2]) / std[2]
        }
        if (resized !== src) resized.recycle()
        val input = OnnxTensor.createTensor(e, FloatBuffer.wrap(chw), longArrayOf(1, 3, th.toLong(), tw.toLong()))
        val name = sess.inputNames.iterator().next()
        val out = sess.run(mapOf(name to input))
        val v = out[0].value
        @Suppress("UNCHECKED_CAST")
        val map = (((v as Array<*>)[0] as Array<*>)[0] as Array<FloatArray>)  // [th][tw]
        input.close(); out.close()

        val thr = 0.3f
        val bin = BooleanArray(area)
        for (y in 0 until th) {
            val row = map[y]
            for (x in 0 until tw) bin[y * tw + x] = row[x] > thr
        }
        val invScale = 1f / scale
        val unclip = 1.6f
        return connectedBoxes(bin, tw, th).mapNotNull { bx ->
            var x0 = bx.x0; var y0 = bx.y0; var x1 = bx.x1; var y1 = bx.y1
            val bw = x1 - x0; val bh = y1 - y0
            if (bw < 3 || bh < 3) return@mapNotNull null
            val exX = ((bw * (unclip - 1)) / 2).toInt()
            val exY = ((bh * (unclip - 1)) / 2).toInt()
            x0 -= exX; x1 += exX; y0 -= exY; y1 += exY
            Box(
                (x0 * invScale).toInt().coerceIn(0, src.width - 1),
                (y0 * invScale).toInt().coerceIn(0, src.height - 1),
                (x1 * invScale).toInt().coerceIn(1, src.width),
                (y1 * invScale).toInt().coerceIn(1, src.height))
        }.filter { it.x1 - it.x0 > 6 && it.y1 - it.y0 > 6 }
            .sortedBy { it.y0 }
    }

    private fun connectedBoxes(bin: BooleanArray, w: Int, h: Int): List<Box> {
        val parent = IntArray(w * h) { it }
        fun find(a: Int): Int { var x = a; while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        fun union(a: Int, b: Int) { val ra = find(a); val rb = find(b); if (ra != rb) parent[ra] = rb }
        for (y in 0 until h) for (x in 0 until w) {
            if (!bin[y * w + x]) continue
            val i = y * w + x
            if (x + 1 < w && bin[i + 1]) union(i, i + 1)
            if (y + 1 < h && bin[i + w]) union(i, i + w)
        }
        val minx = HashMap<Int, Int>(); val miny = HashMap<Int, Int>()
        val maxx = HashMap<Int, Int>(); val maxy = HashMap<Int, Int>()
        for (y in 0 until h) for (x in 0 until w) {
            if (!bin[y * w + x]) continue
            val root = find(y * w + x)
            minx[root] = min(minx[root] ?: x, x); maxx[root] = max(maxx[root] ?: x, x)
            miny[root] = min(miny[root] ?: y, y); maxy[root] = max(maxy[root] ?: y, y)
        }
        val boxes = ArrayList<Box>()
        for (root in minx.keys) {
            val x0 = minx[root]!!; val y0 = miny[root]!!; val x1 = maxx[root]!!; val y1 = maxy[root]!!
            if ((x1 - x0) * (y1 - y0) < 20) continue
            boxes.add(Box(x0, y0, x1 + 1, y1 + 1))
        }
        return boxes
    }

    // ---- Recognition (CTC) --------------------------------------------------
    private fun recognizeBox(e: OrtEnvironment, sess: OrtSession, src: Bitmap, b: Box): String {
        val bw = b.x1 - b.x0; val bh = b.y1 - b.y0
        if (bw <= 0 || bh <= 0) return ""
        val crop = Bitmap.createBitmap(src, b.x0, b.y0, bw, bh)
        val targetH = 48
        var targetW = (targetH.toFloat() * bw / bh).roundToInt().coerceIn(16, 640)
        targetW -= targetW % 8; if (targetW < 16) targetW = 16
        val resized = Bitmap.createScaledBitmap(crop, targetW, targetH, true)
        crop.recycle()
        val area = targetW * targetH
        val chw = FloatArray(3 * area)
        val px = IntArray(area)
        resized.getPixels(px, 0, targetW, 0, 0, targetW, targetH)
        for (i in px.indices) {
            val c = px[i]
            chw[i] = (((c shr 16) and 0xFF) / 255f - 0.5f) / 0.5f
            chw[area + i] = (((c shr 8) and 0xFF) / 255f - 0.5f) / 0.5f
            chw[2 * area + i] = ((c and 0xFF) / 255f - 0.5f) / 0.5f
        }
        resized.recycle()
        val input = OnnxTensor.createTensor(e, FloatBuffer.wrap(chw), longArrayOf(1, 3, targetH.toLong(), targetW.toLong()))
        val name = sess.inputNames.iterator().next()
        val out = sess.run(mapOf(name to input))
        val v = out[0].value
        @Suppress("UNCHECKED_CAST")
        val seq = ((v as Array<*>)[0] as Array<FloatArray>)   // [T][C]
        input.close(); out.close()
        return ctcDecode(seq)
    }

    private fun ctcDecode(seq: Array<FloatArray>): String {
        val sb = StringBuilder()
        var prev = -1
        for (t in seq.indices) {
            val row = seq[t]
            var best = 0; var bestV = row[0]
            for (c in 1 until row.size) if (row[c] > bestV) { bestV = row[c]; best = c }
            if (best != 0 && best != prev) charFor(best)?.let { sb.append(it) }
            prev = best
        }
        return sb.toString().trim()
    }

    /** index 0 = CTC blank; 1..dict.size map to the dictionary; last = space. */
    private fun charFor(index: Int): String? {
        val i = index - 1
        return when {
            i < 0 -> null
            i < dict.size -> dict[i]
            i == dict.size -> " "
            else -> null
        }
    }
}
