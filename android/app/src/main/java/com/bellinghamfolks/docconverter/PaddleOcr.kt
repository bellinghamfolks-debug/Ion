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

    // Detection is language-agnostic; this SWHL/RapidOCR file is confirmed to exist.
    private val detUrls = listOf(
        "https://huggingface.co/SWHL/RapidOCR/resolve/main/PP-OCRv4/ch_PP-OCRv4_det_infer.onnx",
        "https://huggingface.co/SWHL/RapidOCR/resolve/main/PP-OCRv4/ch_PP-OCRv4_det_server_infer.onnx"
    )
    // Bump this when the preferred recognition model changes so existing installs
    // discard the old model file and download the new one.
    private val recVersion = "v5"

    // Arabic recognition + its MATCHING dictionary. FIRST choice is the official
    // PP-OCRv5 Arabic model, which we convert to ONNX in CI and publish as a
    // GitHub Release (its dictionary is the model's OWN embedded 747-char list,
    // so the CTC labels line up exactly). The monkt/deepghs v3 models remain as
    // fallbacks if the release can't be reached.
    private val recDictPairs = listOf(
        "https://github.com/bellinghamfolks-debug/Ion/releases/download/arabic-ocr-v5/arabic_v5_rec.onnx"
            to "https://github.com/bellinghamfolks-debug/Ion/releases/download/arabic-ocr-v5/arabic_v5_dict.txt",
        "https://huggingface.co/monkt/paddleocr-onnx/resolve/main/languages/arabic/rec.onnx"
            to "https://huggingface.co/monkt/paddleocr-onnx/resolve/main/languages/arabic/dict.txt",
        "https://huggingface.co/monkt/paddleocr-onnx/resolve/main/languages/ar/rec.onnx"
            to "https://huggingface.co/monkt/paddleocr-onnx/resolve/main/languages/ar/dict.txt",
        "https://huggingface.co/deepghs/paddleocr/resolve/main/arabic/rec.onnx"
            to "https://huggingface.co/deepghs/paddleocr/resolve/main/arabic/dict.txt"
    )

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
            val detFile = File(dir, "det.onnx")
            val recFile = File(dir, "rec.onnx")
            val dictFile = File(dir, "dict.txt")
            // If the preferred recognition model changed, drop the old one so the
            // new (e.g. v5) model is downloaded instead of the stale cached file.
            purgeStaleRec(dir, recFile, dictFile)

            if (!nonEmpty(detFile)) {
                var ok = false
                for (u in detUrls) { detFile.delete(); if (download(detFile, u)) { ok = true; break } }
                if (!ok) return "det_download"
            }
            if (!(nonEmpty(recFile) && nonEmpty(dictFile))) {
                var ok = false
                for ((ru, du) in recDictPairs) {
                    recFile.delete(); dictFile.delete()
                    if (download(recFile, ru) && download(dictFile, du)) { ok = true; break }
                }
                if (!ok) return "rec_download"
                markRecVersion(dir)
            }

            dict = dictFile.readLines().map { it.trimEnd('\n', '\r') }
            if (dict.isEmpty()) return "dict_empty"
            val e = OrtEnvironment.getEnvironment()
            env = e
            det = e.createSession(detFile.absolutePath, OrtSession.SessionOptions())
            rec = e.createSession(recFile.absolutePath, OrtSession.SessionOptions())
            isReady = true
            null
        } catch (ex: Exception) {
            "init:" + (ex.message ?: "err").take(60)
        }
    }

    /** Pre-download the models (same paths setup() uses) with 0..100 progress. */
    fun downloadModels(onProgress: (Int) -> Unit): String? {
        return try {
            val dir = File(ctx.filesDir, "paddle").apply { mkdirs() }
            val detFile = File(dir, "det.onnx")
            val recFile = File(dir, "rec.onnx")
            val dictFile = File(dir, "dict.txt")
            purgeStaleRec(dir, recFile, dictFile)
            if (!nonEmpty(detFile)) {
                var ok = false
                for (u in detUrls) { detFile.delete(); if (ModelStore.download(u, detFile) { p -> onProgress(p / 2) }) { ok = true; break } }
                if (!ok) return "det_download"
            } else onProgress(50)
            if (!(nonEmpty(recFile) && nonEmpty(dictFile))) {
                var ok = false
                for ((ru, du) in recDictPairs) {
                    recFile.delete(); dictFile.delete()
                    if (ModelStore.download(ru, recFile) { p -> onProgress(50 + p / 2) } && ModelStore.download(du, dictFile) { }) { ok = true; break }
                }
                if (!ok) return "rec_download"
                markRecVersion(dir)
            }
            onProgress(100)
            null
        } catch (e: Exception) { "paddle:" + (e.message ?: "err").take(40) }
    }

    private fun nonEmpty(f: File): Boolean = f.exists() && f.length() > 0

    /** Delete the cached rec model/dict if they were fetched for an older
     *  recVersion, forcing a fresh download of the current preferred model. */
    private fun purgeStaleRec(dir: File, recFile: File, dictFile: File) {
        val marker = File(dir, ".recver")
        val have = if (marker.exists()) marker.runCatching { readText().trim() }.getOrDefault("") else ""
        if (have != recVersion) { recFile.delete(); dictFile.delete() }
    }

    private fun markRecVersion(dir: File) {
        File(dir, ".recver").runCatching { writeText(recVersion) }
    }

    /** Download url -> f, returning true only on an HTTP 2xx with real bytes. */
    private fun download(f: File, url: String): Boolean {
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 20000
            conn.readTimeout = 240000
            conn.instanceFollowRedirects = true
            if (conn.responseCode !in 200..299) { conn.disconnect(); return false }
            conn.inputStream.use { i -> f.outputStream().use { o -> i.copyTo(o) } }
            conn.disconnect()
            nonEmpty(f)
        } catch (e: Exception) { false }
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
        val boxes = try { detect(e, d, src) } catch (ex: Exception) { DiagLog.err("PADDLE", ex); emptyList() }
        DiagLog.log("PADDLE", "detected ${boxes.size} text box(es)")
        if (boxes.isEmpty()) return ""
        val sb = StringBuilder()
        for (b in boxes) {
            var line = try { recognizeBox(e, r, src, b) } catch (ex: Exception) { DiagLog.err("PADDLE", ex); "" }
            if (line.isNotBlank()) {
                // PaddleOCR recognises Arabic glyphs correctly but emits the line
                // in visual LEFT-to-right order; restore logical reading order.
                // A plain reverse fixes Arabic but flips embedded Latin/number
                // runs ("Google" -> "elgooG"), so reverse the whole line then
                // un-reverse each Latin/digit run.
                line = fixVisualOrder(line)
                sb.append(line).append('\n')
            }
        }
        return sb.toString().trim()
    }

    /** Reverse the visual line into logical order, keeping Latin/digit runs
     *  (which read left-to-right even inside Arabic) in their correct order. */
    private fun fixVisualOrder(s: String): String {
        val rev = StringBuilder(s).reverse().toString()
        val out = StringBuilder(rev.length)
        var i = 0
        while (i < rev.length) {
            if (isLtr(rev[i])) {
                var j = i
                while (j < rev.length && isLtr(rev[j])) j++
                out.append(StringBuilder(rev.substring(i, j)).reverse())
                i = j
            } else { out.append(rev[i]); i++ }
        }
        return out.toString()
    }

    /** Characters that flow left-to-right: ASCII letters/digits, Arabic-Indic
     *  digits, and the joiners common inside numbers/versions/URLs. */
    private fun isLtr(c: Char): Boolean =
        c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' ||
        c in '٠'..'٩' || c in '۰'..'۹' ||
        c == '.' || c == ',' || c == '-' || c == '+' || c == ':' || c == '/' || c == '@'

    // ---- Detection (DB) -----------------------------------------------------
    private data class Box(val x0: Int, val y0: Int, val x1: Int, val y1: Int)

    /**
     * Multi-scale (image-pyramid) detection: run the DB detector at a HIGH input
     * scale (small text stays legible) AND a LOW scale (large text / full
     * context), then merge the boxes with non-max suppression. This makes the
     * reader robust to very small AND very large text on the same screen.
     */
    private fun detect(e: OrtEnvironment, sess: OrtSession, src: Bitmap): List<Box> {
        val boxes = ArrayList<Box>()
        boxes += detectAt(e, sess, src, 1280)   // high scale -> small text
        boxes += detectAt(e, sess, src, 736)    // low scale  -> large text / context
        val merged = mergeBoxes(boxes)
        // Reading order: group into lines top-to-bottom, and RIGHT-to-left within
        // a line (Arabic), so multi-box lines join in the correct order.
        val avgH = merged.map { it.y1 - it.y0 }.average().let { if (it.isNaN() || it < 1.0) 20.0 else it }
        return merged.sortedWith(compareBy({ (it.y0 / (avgH * 0.7)).toInt() }, { -it.x0 }))
    }

    /** DB text detection at a single input scale; returns boxes in src coords. */
    private fun detectAt(e: OrtEnvironment, sess: OrtSession, src: Bitmap, maxSide: Int): List<Box> {
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
        var above = 0
        for (y in 0 until th) {
            val row = map[y]
            for (x in 0 until tw) { val on = row[x] > thr; bin[y * tw + x] = on; if (on) above++ }
        }
        DiagLog.log("PADDLE", "det@$maxSide input ${tw}x${th}, pixels>thr=$above (${(above * 100L / area)}%)")
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
    }

    /** Non-max suppression across the two scales: drop a box that overlaps an
     *  already-kept (larger) box by IoU > 0.3, so cross-scale duplicates
     *  collapse while uniquely-found small/large boxes survive. */
    private fun mergeBoxes(boxes: List<Box>): List<Box> {
        val sorted = boxes.sortedByDescending { (it.x1 - it.x0).toLong() * (it.y1 - it.y0) }
        val kept = ArrayList<Box>()
        for (b in sorted) {
            if (kept.none { iou(b, it) > 0.3f }) kept.add(b)
        }
        return kept
    }

    private fun iou(a: Box, b: Box): Float {
        val ix0 = max(a.x0, b.x0); val iy0 = max(a.y0, b.y0)
        val ix1 = min(a.x1, b.x1); val iy1 = min(a.y1, b.y1)
        val iw = ix1 - ix0; val ih = iy1 - iy0
        if (iw <= 0 || ih <= 0) return 0f
        val inter = iw.toFloat() * ih
        val ua = (a.x1 - a.x0).toFloat() * (a.y1 - a.y0)
        val ub = (b.x1 - b.x0).toFloat() * (b.y1 - b.y0)
        return inter / (ua + ub - inter)
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
        val seq = ((v as Array<*>)[0] as Array<FloatArray>)   // expected [T][C]
        input.close(); out.close()
        val tT = seq.size
        val tC = if (tT > 0) seq[0].size else 0
        val (text, conf) = ctcDecode(seq)
        // Deep diagnostics: box size, rec tensor dims vs dict size (C should be
        // ~dict+2), and the raw decode — pinpoints detection-merge vs shape/dict.
        DiagLog.log("PADDLE", "box ${bw}x${bh} rec T=$tT C=$tC dict=${dict.size} conf=${(conf * 100).toInt()}% chars=${text.length} raw='${text.take(40).replace('\n', ' ')}'")
        // Gate low-confidence lines (loosened to 0.3 while tuning the engine).
        return if (conf >= 0.3) text else ""
    }

    /** Greedy CTC decode; also returns mean confidence of the emitted chars. */
    private fun ctcDecode(seq: Array<FloatArray>): Pair<String, Double> {
        val sb = StringBuilder()
        var prev = -1
        var probSum = 0.0; var probN = 0
        for (t in seq.indices) {
            val row = seq[t]
            var best = 0; var bestV = row[0]
            for (c in 1 until row.size) if (row[c] > bestV) { bestV = row[c]; best = c }
            if (best != 0 && best != prev) {
                charFor(best)?.let { sb.append(it) }
                // The PP-OCR CTC head already outputs per-class probabilities, so
                // the winning class's confidence IS its row max. (Re-applying
                // softmax here divided every score by ~numClasses, crushing real
                // ~0.9 confidences down to ~1/163 ≈ 1%; the 0.3 gate below then
                // dropped every box and the engine produced nothing at all.)
                probSum += bestV; probN++
            }
            prev = best
        }
        val conf = if (probN == 0) 0.0 else probSum / probN
        return Pair(sb.toString().trim(), conf)
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
