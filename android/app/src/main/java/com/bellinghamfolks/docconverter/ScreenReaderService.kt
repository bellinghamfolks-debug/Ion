package com.bellinghamfolks.docconverter

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import com.googlecode.tesseract.android.TessBaseAPI
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

/**
 * Foreground service that powers the glasses live reader. It mirrors the screen
 * (the eSight Companion camera view), detects when the view genuinely changes,
 * turns the frame into text, and speaks it aloud in Arabic/English.
 *
 * Three modes, chosen from the live-reader settings:
 *   - Online OCR (Gemini Flash-Lite): reads visible text, refreshed ~every 2s.
 *   - Local OCR  (Tesseract ara+eng): offline, instant, free — lower accuracy.
 *   - Rich live description: a spoken narration of the whole scene for a blind
 *     user (online only — Tesseract can only read text, not describe).
 */
class ScreenReaderService : Service() {

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var tts: TextToSpeech? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private var lastSpoken = ""
    @Volatile private var speakingNorm = ""       // normalised text of the current utterance
    @Volatile private var currentUtterId = ""
    @Volatile private var inFlight = false
    private var lastSentAt = 0L
    @Volatile private var lastSignature: IntArray? = null   // last frame we actually processed
    @Volatile private var isSpeaking = false       // an utterance is playing now
    @Volatile private var announcing = false       // an important status announcement is playing
    private var switchStreak = 0                    // debounce for jumping to new text
    @Volatile private var captureRequested = false  // on-demand: read/describe once now
    private var blankStreak = 0                      // consecutive black/blank captured frames
    private var blurStreak = 0                       // consecutive blurry frames skipped
    @Volatile private var blankHintSpoken = false    // one-shot "screen looks black" hint
    private var pendingNorm = ""                     // a read awaiting 2-frame confirmation
    private var narrationSig: IntArray? = null       // frame signature when a describe narration began
    @Volatile private var released = false           // service torn down; stop touching bitmaps
    private var captureThread: android.os.HandlerThread? = null

    private var localOcr: TessBaseAPI? = null
    @Volatile private var localReady = false
    private var paddle: PaddleOcr? = null      // experimental high-accuracy on-device engine
    private var overlayButton: View? = null   // floating trigger over other apps
    private val tessVariant = "best"          // tessdata_best = highest on-device accuracy
    // Fast, cheap model for near-real-time reading (Gemini Lite).
    private val onlineModel = "gemini-3.5-flash-lite"
    private val channelId = "live_reader"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // On-demand trigger from the notification action / in-app button: the
        // service is already running, just arm a single capture.
        if (intent?.action == ACTION_CAPTURE) {
            if (projection == null) { stopSelf(); return START_NOT_STICKY }  // not started yet
            captureRequested = true
            return START_NOT_STICKY
        }
        // Live switch between reading text and describing the scene, from the
        // notification, without leaving the eSight app.
        if (intent?.action == ACTION_TOGGLE_DESCRIBE) {
            val now = !describeEnabled()
            prefs().edit().putBoolean("describe", now).apply()
            tts?.stop()
            announce(if (now) "تم تشغيل الوصف، وأُوقفت القراءة." else "تم إيقاف الوصف، والعودة للقراءة.")
            try { getSystemService(NotificationManager::class.java).notify(1, buildNotification()) } catch (_: Exception) {}
            return START_NOT_STICKY
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, buildNotification())
        }
        tts = TextToSpeech(this) { }
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) { if (utteranceId == currentUtterId) isSpeaking = true }
            override fun onDone(utteranceId: String?) {
                if (utteranceId?.startsWith("announce") == true) announcing = false
                if (utteranceId == currentUtterId) { isSpeaking = false; speakingNorm = "" }
            }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                if (utteranceId?.startsWith("announce") == true) announcing = false
                if (utteranceId == currentUtterId) { isSpeaking = false; speakingNorm = "" }
            }
        })
        initLocalOcrIfNeeded()
        initPaddleIfNeeded()
        NetManager.setPreferCellular(this, prefs().getBoolean("prefer_cellular", false))
        val code = intent?.getIntExtra("code", Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        @Suppress("DEPRECATION")
        val data: Intent? = intent?.getParcelableExtra("data")
        if (code == Activity.RESULT_OK && data != null) startCapture(code, data) else stopSelf()
        return START_NOT_STICKY
    }

    private fun startCapture(code: Int, data: Intent) {
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val proj = mpm.getMediaProjection(code, data)
        projection = proj
        // Android 14 requires a registered callback before creating the display.
        proj.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() { stopSelf() }
        }, Handler(Looper.getMainLooper()))

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        // Capture at high resolution (2160 long edge) so on-device OCR has enough
        // pixels for small text; online frames are downscaled again before upload.
        val scale = minOf(1f, 2160f / maxOf(metrics.widthPixels, metrics.heightPixels))
        val dw = (metrics.widthPixels * scale).toInt().coerceAtLeast(1)
        val dh = (metrics.heightPixels * scale).toInt().coerceAtLeast(1)

        val reader = ImageReader.newInstance(dw, dh, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        virtualDisplay = proj.createVirtualDisplay(
            "live-reader", dw, dh, metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader.surface, null, null)

        // Run the per-frame CPU work on a dedicated thread, never the UI thread.
        val ct = android.os.HandlerThread("live-capture").apply { start() }
        captureThread = ct
        val captureHandler = Handler(ct.looper)

        reader.setOnImageAvailableListener({ r ->
            try {
                val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                // On-demand: ignore frames until the user asks, then read the
                // current view once, unconditionally (they explicitly requested it).
                if (demandMode()) {
                    if (!captureRequested || inFlight) { image.close(); return@setOnImageAvailableListener }
                    captureRequested = false
                    val bmp = try { imageToBitmap(image, dw, dh) } catch (e: Exception) { null } finally { image.close() }
                    if (bmp == null) return@setOnImageAvailableListener
                    lastSignature = signature(bmp)
                    inFlight = true
                    process(bmp)
                    return@setOnImageAvailableListener
                }
                // Live stream mode: continuous auto-reading.
                val now = System.currentTimeMillis()
                val minInterval = if (engine() == "online") 2000L else 700L
                if (inFlight || now - lastSentAt < minInterval) { image.close(); return@setOnImageAvailableListener }
                val bmp = try { imageToBitmap(image, dw, dh) } catch (e: Exception) { null } finally { image.close() }
                if (bmp == null) return@setOnImageAvailableListener
                val sig = signature(bmp)
                val info = analyzeFrame(bmp)
                if (!info.hasText) {
                    // Diagnose the "captured as black" case so the user hears WHY.
                    blankStreak++
                    if (blankStreak >= 4 && !blankHintSpoken) {
                        blankHintSpoken = true
                        announce("لا ألتقط نصًا من الشاشة. إذا كان مشهد النظارة معروضًا الآن، فقد لا يستطيع النظام تصويره؛ جرّب التقاط لقطة شاشة للتأكّد.")
                    }
                    bmp.recycle(); return@setOnImageAvailableListener
                }
                blankStreak = 0
                // Skip blurry/moving frames so OCR only sees a sharp view — but
                // never starve: read anyway after a few soft frames.
                if (!info.sharp && blurStreak < 3) { blurStreak++; bmp.recycle(); return@setOnImageAvailableListener }
                blurStreak = 0
                if (similar(sig, lastSignature)) { bmp.recycle(); return@setOnImageAvailableListener }
                lastSignature = sig
                lastSentAt = now
                inFlight = true
                process(bmp)
            } catch (_: Exception) {
                // A single frame error must never crash the capture thread/service.
            }
        }, captureHandler)

        // On-demand: show a big floating button ON TOP of the eSight app so the
        // user can trigger a read/describe without switching apps.
        if (demandMode() && canOverlay()) addOverlayButton()
    }

    private fun canOverlay(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    private fun addOverlayButton() {
        if (overlayButton != null) return
        val btn = Button(this).apply {
            text = if (describeEnabled()) "صِف الآن" else "اقرأ الآن"
            textSize = 22f
            setPadding(80, 48, 80, 48)
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#D32F2F"))
            setOnClickListener {
                captureRequested = true
                @Suppress("DEPRECATION")
                it.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
            }
        }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT)
        lp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        lp.y = 140
        try {
            (getSystemService(WINDOW_SERVICE) as WindowManager).addView(btn, lp)
            overlayButton = btn
        } catch (_: Exception) { /* overlay not permitted -> notification action still works */ }
    }

    private fun removeOverlayButton() {
        overlayButton?.let { v ->
            try { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(v) } catch (_: Exception) {}
        }
        overlayButton = null
    }

    private fun process(bmp: Bitmap) {
        if (released) { bmp.recycle(); inFlight = false; return }
        scope.launch {
            val text = try {
                when (engine()) {
                    "paddle" -> recognizePaddle(bmp)
                    "local" -> recognizeLocal(bmp)
                    else -> recognizeOnline(bmp)
                }
            } catch (_: Exception) { "" } finally { bmp.recycle() }
            try { handleText(text) } catch (_: Exception) { inFlight = false }
        }
    }

    /** Which engine to use for this frame (describe always needs online). */
    private fun engine(): String {
        if (describeEnabled()) return "online"
        return when (prefs().getString("ocr_mode", "online")) {
            "paddle" -> if (paddle?.ready() == true) "paddle" else "online"
            "local" -> if (localReady) "local" else "online"
            else -> "online"
        }
    }

    private fun recognizePaddle(bmp: Bitmap): String {
        val p = paddle ?: return ""
        val work = scaleToLongEdge(bmp, 1600)
        val norm = normalizeLighting(work)       // adapt to the scene's lighting
        if (work !== bmp) work.recycle()
        val t = try { p.recognize(norm) } catch (_: Exception) { "" }
        norm.recycle()
        return cleanOcr(t)
    }

    private suspend fun recognizeOnline(bmp: Bitmap): String {
        // Keep the upload light/fast: online doesn't need the full 2160 capture.
        val scaled = scaleToLongEdge(bmp, 1440)
        val norm = normalizeLighting(scaled)     // adapt to the scene's lighting
        if (scaled !== bmp) scaled.recycle()
        val jpeg = compressJpeg(norm)
        norm.recycle()
        val mode = if (describeEnabled()) "describe" else "ocr"
        return ConvertApi.liveOcr(jpeg, onlineModel, mode).trim()
    }

    /**
     * Lighting-adaptive correction shared by ALL modes so the reader copes with
     * dim, bright, washed-out, back-lit or low-contrast scenes. Robust contrast
     * stretch (1st/99th percentile) + auto-gamma driven by mean brightness,
     * applied to RGB via a per-luminance scale so colour is preserved. It is
     * near-identity in already-good lighting, so it never hurts a clean frame.
     * Always returns a NEW bitmap.
     */
    private fun normalizeLighting(src: Bitmap): Bitmap {
        val w = src.width; val h = src.height
        val out = Bitmap.createBitmap(w.coerceAtLeast(1), h.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        if (w <= 0 || h <= 0) return out
        val px = IntArray(w * h)
        src.getPixels(px, 0, w, 0, 0, w, h)
        val luma = IntArray(w * h)
        val hist = IntArray(256)
        var sum = 0L
        for (i in px.indices) {
            val c = px[i]
            val y = (0.299 * ((c shr 16) and 0xFF) +
                0.587 * ((c shr 8) and 0xFF) + 0.114 * (c and 0xFF)).toInt().coerceIn(0, 255)
            luma[i] = y; hist[y]++; sum += y
        }
        val total = w * h
        val lowCut = (total * 0.01).toInt(); val highCut = (total * 0.99).toInt()
        var acc = 0; var lo = 0; var hi = 255
        for (v in 0..255) { acc += hist[v]; if (acc >= lowCut) { lo = v; break } }
        acc = 0; for (v in 0..255) { acc += hist[v]; if (acc >= highCut) { hi = v; break } }
        if (hi <= lo) { lo = 0; hi = 255 }
        val range = (hi - lo).coerceAtLeast(1)
        val mean = sum.toDouble() / total
        val gamma = when {
            mean < 90 -> 0.6      // very dark -> brighten strongly
            mean < 130 -> 0.8     // dim -> brighten
            mean > 190 -> 1.4     // washed out -> darken
            mean > 160 -> 1.2
            else -> 1.0           // good light -> leave it
        }
        val lut = IntArray(256)
        for (v in 0..255) {
            val t = ((v - lo).toFloat() / range).coerceIn(0f, 1f)
            lut[v] = (Math.pow(t.toDouble(), gamma) * 255).toInt().coerceIn(0, 255)
        }
        val res = IntArray(w * h)
        for (i in px.indices) {
            val c = px[i]; val y = luma[i]; val ny = lut[y]
            if (y == 0) { res[i] = (0xFF shl 24) or (ny shl 16) or (ny shl 8) or ny; continue }
            val scale = ny.toFloat() / y
            val r = (((c shr 16) and 0xFF) * scale).toInt().coerceIn(0, 255)
            val g = (((c shr 8) and 0xFF) * scale).toInt().coerceIn(0, 255)
            val b = ((c and 0xFF) * scale).toInt().coerceIn(0, 255)
            res[i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
        }
        out.setPixels(res, 0, w, 0, 0, w, h)
        return out
    }

    private fun scaleToLongEdge(src: Bitmap, maxEdge: Int): Bitmap {
        val longEdge = maxOf(src.width, src.height)
        if (longEdge <= maxEdge) return src
        val s = maxEdge.toFloat() / longEdge
        return Bitmap.createScaledBitmap(
            src, (src.width * s).toInt().coerceAtLeast(1), (src.height * s).toInt().coerceAtLeast(1), true)
    }

    private fun recognizeLocal(bmp: Bitmap): String {
        val api = localOcr ?: return ""
        // Cap the work size: the best model is heavy; 1800px keeps each pass usable
        // while still giving small text plenty of detail.
        val work = scaleToLongEdge(bmp, 1800)
        val norm = normalizeLighting(work)       // adapt to lighting, THEN binarise
        if (work !== bmp) work.recycle()
        val prepped = preprocessForOcr(norm)
        val result = synchronized(api) {
            var bestText = ""
            var bestConf = -1
            // Best-of-PSM: a held page/paragraph reads best as a single block,
            // a sign/scattered scene as sparse text. Try both, keep the more
            // confident non-empty result.
            for (psm in intArrayOf(
                    TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK,
                    TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT)) {
                api.pageSegMode = psm
                api.setImage(prepped)
                val t = api.getUTF8Text() ?: ""
                val conf = try { api.meanConfidence() } catch (_: Exception) { 0 }
                api.clear()
                if (t.isNotBlank() && conf > bestConf) { bestConf = conf; bestText = t }
            }
            // Below this confidence Tesseract is guessing at noise -> say nothing
            // rather than reading out garbled symbols.
            if (bestConf < 55) "" else bestText
        }
        if (prepped !== norm) prepped.recycle()
        norm.recycle()
        return cleanOcr(result)
    }

    /**
     * Adaptive (Bradley) thresholding: binarise each pixel against the mean of a
     * local window using an integral image. Unlike a global stretch this handles
     * UNEVEN camera lighting, which is what turned local OCR into garbage on the
     * glasses feed — text now comes out clean black-on-white for Tesseract.
     */
    private fun preprocessForOcr(src: Bitmap): Bitmap {
        val w = src.width; val h = src.height
        if (w <= 0 || h <= 0) return src
        val px = IntArray(w * h)
        src.getPixels(px, 0, w, 0, 0, w, h)
        val lum = IntArray(w * h)
        for (i in px.indices) {
            val c = px[i]
            lum[i] = (0.299 * ((c shr 16) and 0xFF) +
                0.587 * ((c shr 8) and 0xFF) + 0.114 * (c and 0xFF)).toInt()
        }
        // Integral image as Int (not Long): work size is capped at 1800px, so the
        // max prefix sum (255 * ~1.8M px) stays well under Int.MAX — halves memory.
        val iw = w + 1
        val integral = IntArray(iw * (h + 1))
        for (y in 0 until h) {
            var rowSum = 0
            for (x in 0 until w) {
                rowSum += lum[y * w + x]
                integral[(y + 1) * iw + (x + 1)] = integral[y * iw + (x + 1)] + rowSum
            }
        }
        val s = (w / 16).coerceAtLeast(8)   // local window side ~ image/16
        val half = s / 2
        val t = 15                          // Bradley threshold percent below local mean
        val out = IntArray(w * h)
        for (y in 0 until h) {
            val y1 = (y - half).coerceAtLeast(0)
            val y2 = (y + half).coerceAtMost(h - 1)
            for (x in 0 until w) {
                val x1 = (x - half).coerceAtLeast(0)
                val x2 = (x + half).coerceAtMost(w - 1)
                val count = (x2 - x1 + 1) * (y2 - y1 + 1)
                val sum = (integral[(y2 + 1) * iw + (x2 + 1)] - integral[y1 * iw + (x2 + 1)] -
                    integral[(y2 + 1) * iw + x1] + integral[y1 * iw + x1]).toLong()
                val black = lum[y * w + x].toLong() * count * 100 <= sum * (100 - t)
                out[y * w + x] = if (black) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
            }
        }
        despeckle(out, w, h)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.setPixels(out, 0, w, 0, 0, w, h)
        return bmp
    }

    /** Remove isolated black speckles and fill lone white holes (3x3 majority). */
    private fun despeckle(bin: IntArray, w: Int, h: Int) {
        if (w < 3 || h < 3) return
        val black = 0xFF000000.toInt()
        val white = 0xFFFFFFFF.toInt()
        val copy = bin.copyOf()
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                var blk = 0
                for (dy in -1..1) for (dx in -1..1) {
                    if (dx == 0 && dy == 0) continue
                    if (copy[(y + dy) * w + (x + dx)] == black) blk++
                }
                val i = y * w + x
                if (copy[i] == black && blk <= 1) bin[i] = white
                else if (copy[i] == white && blk >= 7) bin[i] = black
            }
        }
    }

    /**
     * Drop noise lines (mostly symbols) but KEEP real content — including
     * numbers-only lines (prices, times, phone/room numbers). Letters AND digits
     * count as meaningful. Lines are kept as separate lines so TTS pauses between
     * them (natural reading structure).
     */
    private fun cleanOcr(raw: String): String {
        val kept = raw.split('\n').map { it.trim() }.filter { line ->
            if (line.isEmpty()) return@filter false
            val meaningful = line.count { it.isLetterOrDigit() }
            meaningful >= 2 && meaningful.toDouble() / line.length >= 0.5
        }
        return kept.joinToString("\n").trim()
    }

    /**
     * Decide what (if anything) to speak for a freshly recognised frame.
     *
     * Key fix for the "reads, restarts, reads, restarts… never finishes" loop:
     * while an utterance is playing we do NOT restart it for text that is
     * essentially the same (tiny eye movements make the OCR jitter). We only jump
     * to new text once a genuinely different reading persists for 2 frames. In
     * rich-description mode we never interrupt — the narration always finishes.
     */
    private fun handleText(text: String) {
        inFlight = false
        if (text.isBlank()) {
            // On-demand: the user pressed and got nothing — tell them, don't stay silent.
            if (demandMode()) announce("لا يوجد نص واضح لأقرأه في هذا المشهد.")
            return
        }
        // On-demand: the user explicitly asked, so read/describe it now — even if
        // it repeats the last thing and even if something is already playing.
        if (demandMode()) {
            lastSpoken = text
            speak(text)
            return
        }
        val newNorm = normalize(text)
        val describing = describeEnabled()

        if (isSpeaking) {
            if (describing) {
                // A description finishes uninterrupted UNLESS the scene itself
                // changed a lot (the user moved to something new).
                val cur = lastSignature
                if (cur != null && narrationSig != null && !similar(cur, narrationSig)) {
                    lastSpoken = text
                    speak(text)
                }
                switchStreak = 0
                return
            }
            if (similarity(newNorm, speakingNorm) >= 0.5) {
                switchStreak = 0            // same text still in view -> keep reading
                return
            }
            // A genuinely different text appeared. Only jump to it once it
            // persists for a couple of frames (debounce), and only when
            // auto-switch is on — a single jittery frame must not interrupt.
            if (autoStopEnabled()) {
                switchStreak++
                if (switchStreak >= 2) {
                    switchStreak = 0
                    lastSpoken = text
                    speak(text)
                }
            }
            return
        }

        // Idle. Confirm a new reading across TWO frames before speaking, so a
        // single noisy frame can never produce a wrong or partial read.
        switchStreak = 0
        if (isNearDuplicate(text)) { pendingNorm = ""; return }
        if (pendingNorm.isNotEmpty() && similarity(newNorm, pendingNorm) >= 0.7) {
            pendingNorm = ""
            lastSpoken = text
            speak(text)
        } else {
            pendingNorm = newNorm       // wait for the next frame to confirm
        }
    }

    // ---- Settings -----------------------------------------------------------

    private fun prefs() = getSharedPreferences("live_reader", Context.MODE_PRIVATE)

    private fun describeEnabled(): Boolean = prefs().getBoolean("describe", false)

    private fun autoStopEnabled(): Boolean = prefs().getBoolean("autostop", true)

    private fun localSelected(): Boolean = prefs().getString("ocr_mode", "online") == "local"

    /** "live" = continuous auto-reading; "demand" = only on an explicit trigger. */
    private fun demandMode(): Boolean = prefs().getString("trigger", "live") == "demand"

    private fun paddleSelected(): Boolean = prefs().getString("ocr_mode", "online") == "paddle"

    // ---- Experimental on-device OCR (PaddleOCR / ONNX) ---------------------

    private fun initPaddleIfNeeded() {
        if (!paddleSelected()) return
        scope.launch {
            val p = PaddleOcr(this@ScreenReaderService)
            announce("جارٍ تجهيز محرّك PaddleOCR عالي الدقّة، قد يأخذ دقائق عند أول مرة.")
            val err = p.setup()
            if (err == null) {
                paddle = p
                announce("محرّك PaddleOCR جاهز.")
            } else {
                announce("تعذّر تجهيز PaddleOCR، سيتم استخدام البديل. السبب: $err")
            }
        }
    }

    // ---- On-device OCR (Tesseract) -----------------------------------------

    private fun initLocalOcrIfNeeded() {
        if (!localSelected()) return
        scope.launch {
            try {
                val dataDir = filesDir                     // parent of the tessdata/ folder
                // First run only: the high-accuracy language data is fetched once
                // (needs internet, larger than before), then the local scanner
                // works fully offline. Speak the state so a blind user knows.
                if (needsTessDownload(dataDir)) announce("جارٍ تنزيل بيانات القراءة المحلية عالية الدقّة، قد تأخذ دقيقة.")
                ensureTraineddata(dataDir)
                // OEM_LSTM_ONLY: the neural engine required by the best models.
                val api = TessBaseAPI()
                if (api.init(dataDir.absolutePath, "ara+eng", TessBaseAPI.OEM_LSTM_ONLY)) {
                    api.setVariable("user_defined_dpi", "300")        // Tesseract targets ~300 DPI
                    api.setVariable("preserve_interword_spaces", "1")
                    localOcr = api
                    localReady = true
                    announce("الماسح المحلي جاهز، يعمل الآن بدون إنترنت.")
                } else {
                    api.recycle()
                    announce("تعذّر تجهيز القراءة المحلية، سيتم استخدام الإنترنت.")
                }
            } catch (_: Exception) {
                localReady = false            // fall back to online OCR
                announce("تعذّر تنزيل بيانات القراءة المحلية، سيتم استخدام الإنترنت.")
            }
        }
    }

    private fun traineddataPresent(dataDir: File): Boolean {
        val tess = File(dataDir, "tessdata")
        val ara = File(tess, "ara.traineddata")
        val eng = File(tess, "eng.traineddata")
        return ara.exists() && ara.length() > 0 && eng.exists() && eng.length() > 0
    }

    /** Speak a short spoken status update (used for local-scanner setup). */
    private fun announce(msg: String) {
        announcing = true
        tts?.language = Locale("ar")
        tts?.speak(msg, TextToSpeech.QUEUE_ADD, null, "announce-" + System.nanoTime())
    }

    private fun needsTessDownload(dataDir: File): Boolean {
        val tess = File(dataDir, "tessdata")
        val marker = File(tess, ".variant")
        val variant = if (marker.exists()) marker.runCatching { readText().trim() }.getOrDefault("") else ""
        return variant != tessVariant || !traineddataPresent(dataDir)
    }

    /**
     * Download the HIGH-ACCURACY ara/eng models (tessdata_best) once into
     * filesDir/tessdata/. If an older (fast) variant is present it is replaced.
     */
    private fun ensureTraineddata(dataDir: File) {
        val tess = File(dataDir, "tessdata").apply { mkdirs() }
        val marker = File(tess, ".variant")
        val variant = if (marker.exists()) marker.runCatching { readText().trim() }.getOrDefault("") else ""
        if (variant != tessVariant) {
            File(tess, "ara.traineddata").delete()
            File(tess, "eng.traineddata").delete()
        }
        for (lang in listOf("ara", "eng")) {
            val f = File(tess, "$lang.traineddata")
            if (f.exists() && f.length() > 0) continue
            val url = URL("https://github.com/tesseract-ocr/tessdata_best/raw/main/$lang.traineddata")
            val conn = url.openConnection() as HttpURLConnection
            try {
                conn.connectTimeout = 20000
                conn.readTimeout = 240000        // best models are larger
                conn.instanceFollowRedirects = true
                conn.inputStream.use { input -> f.outputStream().use { input.copyTo(it) } }
            } finally { conn.disconnect() }
        }
        marker.runCatching { writeText(tessVariant) }
    }

    // ---- Frame helpers ------------------------------------------------------

    private fun imageToBitmap(image: Image, dw: Int, dh: Int): Bitmap {
        val plane = image.planes[0]
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * dw
        val bmp = Bitmap.createBitmap(dw + rowPadding / pixelStride, dh, Bitmap.Config.ARGB_8888)
        bmp.copyPixelsFromBuffer(buffer)
        if (rowPadding == 0) return bmp
        val cropped = Bitmap.createBitmap(bmp, 0, 0, dw, dh)
        bmp.recycle()
        return cropped
    }

    private fun compressJpeg(bmp: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 70, out)
        return out.toByteArray()
    }

    /** 16x16 grayscale perceptual signature for change detection — fine enough
     *  to notice a single changed word/line on an otherwise-similar page. */
    private fun signature(bmp: Bitmap): IntArray {
        val n = 16
        val small = Bitmap.createScaledBitmap(bmp, n, n, true)
        val sig = IntArray(n * n)
        for (y in 0 until n) for (x in 0 until n) {
            val c = small.getPixel(x, y)
            sig[y * n + x] = (0.299 * ((c shr 16) and 0xFF) +
                0.587 * ((c shr 8) and 0xFF) + 0.114 * (c and 0xFF)).toInt()
        }
        small.recycle()
        return sig
    }

    private fun similar(a: IntArray, b: IntArray?): Boolean {
        if (b == null || a.size != b.size) return false
        var diff = 0
        for (i in a.indices) diff += kotlin.math.abs(a[i] - b[i])
        return diff < 8 * a.size   // avg per-cell luma change < 8/255 => same view
    }

    private data class FrameInfo(val hasText: Boolean, val sharp: Boolean)

    /**
     * Smart on-device frame analysis in one pass:
     *  - hasText: text — even small/medium — is a dense cluster of sharp stroke
     *    edges (measured globally AND per grid cell), so a small block of text in
     *    a corner still triggers a read while blank/smooth frames are skipped.
     *  - sharp: the sharpest text region's edge strength; a motion-blurred or
     *    out-of-focus frame has weak edges even where text is, so we can wait for
     *    a crisp frame before OCR. Both are size-robust (per-cell, not global).
     */
    private fun analyzeFrame(bmp: Bitmap): FrameInfo {
        val target = 512
        val scale = minOf(1f, target.toFloat() / maxOf(bmp.width, bmp.height))
        val w = (bmp.width * scale).toInt().coerceAtLeast(16)
        val h = (bmp.height * scale).toInt().coerceAtLeast(16)
        val small = Bitmap.createScaledBitmap(bmp, w, h, true)
        val px = IntArray(w * h)
        small.getPixels(px, 0, w, 0, 0, w, h)
        small.recycle()
        val lum = IntArray(w * h)
        for (i in px.indices) {
            val c = px[i]
            lum[i] = (0.299 * ((c shr 16) and 0xFF) +
                0.587 * ((c shr 8) and 0xFF) + 0.114 * (c and 0xFF)).toInt()
        }
        val gxN = 8; val gyN = 8
        val cellEdges = IntArray(gxN * gyN)
        val cellGrad = IntArray(gxN * gyN)   // cell gradient sums fit in Int (<~1.2M)
        var total = 0
        val thr = 36                       // strong-edge threshold
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                val g = kotlin.math.abs(lum[y * w + x + 1] - lum[y * w + x - 1]) +
                    kotlin.math.abs(lum[(y + 1) * w + x] - lum[(y - 1) * w + x])
                val ci = (y * gyN / h) * gxN + (x * gxN / w)
                cellGrad[ci] += g
                if (g > thr) { total++; cellEdges[ci]++ }
            }
        }
        val area = ((w - 2).coerceAtLeast(1)) * ((h - 2).coerceAtLeast(1))
        val globalFrac = total.toDouble() / area
        val cellArea = ((w / gxN).coerceAtLeast(1) * (h / gyN).coerceAtLeast(1)).toDouble()
        var maxCell = 0.0; var maxGrad = 0.0
        for (ci in cellEdges.indices) {
            maxCell = maxOf(maxCell, cellEdges[ci] / cellArea)
            maxGrad = maxOf(maxGrad, cellGrad[ci] / cellArea)
        }
        val hasText = globalFrac > 0.004 || maxCell > 0.10
        val sharp = maxGrad > 8.0          // sharpest region crisp enough to OCR
        return FrameInfo(hasText, sharp)
    }

    // ---- Text helpers -------------------------------------------------------

    /** Token overlap (Jaccard) — tolerant of OCR jitter and word reordering. */
    private fun similarity(a: String, b: String): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        val sa = a.split(' ').filter { it.isNotBlank() }.toHashSet()
        val sb = b.split(' ').filter { it.isNotBlank() }.toHashSet()
        if (sa.isEmpty() || sb.isEmpty()) return 0.0
        val inter = sa.count { it in sb }
        val union = sa.size + sb.size - inter
        return if (union == 0) 0.0 else inter.toDouble() / union
    }

    private fun isNearDuplicate(text: String): Boolean {
        val a = normalize(text)
        val b = normalize(lastSpoken)
        if (a == b) return true
        if (b.length >= 8 && (a.contains(b) || b.contains(a))) return true
        return similarity(a, b) >= 0.6
    }

    private fun normalize(s: String): String =
        s.replace(Regex("[\\u064B-\\u0652\\u0640\\s]+"), " ").trim().lowercase()

    private fun speak(text: String) {
        val rate = prefs().getFloat("rate", 1.0f)
        tts?.setSpeechRate(rate)
        speakingNorm = normalize(text)
        isSpeaking = true
        if (describeEnabled()) narrationSig = lastSignature   // for scene-change interruption
        val baseId = System.nanoTime().toString()
        currentUtterId = baseId
        // Speak each script run in its own language so mixed Arabic/English text
        // isn't voiced entirely in one language (mispronunciation).
        val runs = splitByScript(text)
        // Don't clobber an important status announcement mid-sentence: append if
        // one is still playing, otherwise flush the previous read.
        var mode = if (announcing) TextToSpeech.QUEUE_ADD else TextToSpeech.QUEUE_FLUSH
        for ((idx, run) in runs.withIndex()) {
            val ar = run.any { it.code in 0x0600..0x06FF }
            tts?.language = if (ar) Locale("ar") else Locale.ENGLISH
            // The LAST run carries currentUtterId so onDone clears isSpeaking.
            val id = if (idx == runs.size - 1) baseId else "$baseId-$idx"
            tts?.speak(run, mode, null, id)
            mode = TextToSpeech.QUEUE_ADD
        }
    }

    /** Split text into maximal runs of Arabic vs non-Arabic letters; spaces,
     *  digits and punctuation stay attached to the current run. */
    private fun splitByScript(text: String): List<String> {
        val runs = ArrayList<String>()
        val sb = StringBuilder()
        var curAr: Boolean? = null
        for (ch in text) {
            if (!ch.isLetter()) { sb.append(ch); continue }
            val ar = ch.code in 0x0600..0x06FF
            if (curAr == null) curAr = ar
            if (ar != curAr) {
                if (sb.isNotBlank()) runs.add(sb.toString())
                sb.setLength(0)
                curAr = ar
            }
            sb.append(ch)
        }
        if (sb.isNotBlank()) runs.add(sb.toString())
        return if (runs.isEmpty()) listOf(text) else runs
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "القارئ اللحظي", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, channelId) else Notification.Builder(this)
        builder
            .setContentTitle("القارئ اللحظي للنظارة")
            .setContentText(if (demandMode()) "اضغط الزر لقراءة/وصف ما تراه النظارة." else "يقرأ النص من كاميرا النظارة…")
            .setSmallIcon(android.R.drawable.ic_menu_view)
        // On-demand: a tappable action so the user can trigger a single read
        // without leaving the eSight app (pull down the notification, tap).
        if (demandMode()) {
            val label = if (describeEnabled()) "صِف الآن" else "اقرأ الآن"
            @Suppress("DEPRECATION")
            builder.addAction(android.R.drawable.ic_menu_view, label, capturePendingIntent())
        }
        // Always: flip between reading text and describing the scene, live.
        val descLabel = if (describeEnabled()) "إيقاف الوصف (قراءة)" else "تشغيل الوصف"
        @Suppress("DEPRECATION")
        builder.addAction(android.R.drawable.ic_menu_info_details, descLabel, describePendingIntent())
        return builder.build()
    }

    private fun capturePendingIntent(): PendingIntent = servicePendingIntent(ACTION_CAPTURE, 0)
    private fun describePendingIntent(): PendingIntent = servicePendingIntent(ACTION_TOGGLE_DESCRIBE, 1)

    private fun servicePendingIntent(action: String, requestCode: Int): PendingIntent {
        val i = Intent(this, ScreenReaderService::class.java).setAction(action)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getService(this, requestCode, i, flags)
    }

    override fun onDestroy() {
        super.onDestroy()
        released = true                 // stop any in-flight coroutine from touching bitmaps
        removeOverlayButton()
        scope.cancel()
        try { captureThread?.quitSafely() } catch (_: Exception) {}
        captureThread = null
        virtualDisplay?.release()
        imageReader?.close()
        projection?.stop()
        tts?.stop()
        tts?.shutdown()
        localOcr?.recycle()
        paddle?.close()
    }

    companion object {
        const val ACTION_CAPTURE = "com.bellinghamfolks.docconverter.CAPTURE"
        const val ACTION_TOGGLE_DESCRIBE = "com.bellinghamfolks.docconverter.TOGGLE_DESCRIBE"
    }
}
