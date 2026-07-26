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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.util.Locale

/**
 * Foreground service that powers the glasses live reader. It mirrors the screen
 * (the eSight Companion camera view), decides — from phase-correlation motion —
 * when the view genuinely changes, turns the frame into text, and speaks it
 * aloud in Arabic/English.
 *
 * Modes, chosen from the settings:
 *   - Online (Gemini): reads visible text, refreshed ~every 2s (most accurate).
 *   - Offline (PaddleOCR, Arabic PP-OCRv5): on-device, no internet.
 *   - Rich live description: a spoken narration of the whole scene for a blind
 *     user (online only — the offline engine only reads text).
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
    @Volatile private var readGray: FloatArray? = null   // N×N luma of the frame being read (phase-correlation reference)
    @Volatile private var isSpeaking = false       // an utterance is playing now
    @Volatile private var announcing = false       // an important status announcement is playing
    @Volatile private var captureRequested = false  // on-demand: read/describe once now
    private var blankStreak = 0                      // consecutive black/blank captured frames
    private var frameSeq = 0                         // evaluated-frame counter (for the diagnostic log)
    @Volatile private var blankHintSpoken = false    // one-shot "screen looks black" hint
    @Volatile private var speakStartAt = 0L           // when the current utterance started (watchdog)
    @Volatile private var released = false           // service torn down; stop touching bitmaps
    @Volatile private var fallbackAnnounced = false  // told the user the offline engine fell back to online
    private var captureThread: android.os.HandlerThread? = null

    private var paddle: PaddleOcr? = null      // offline on-device engine (Arabic PP-OCRv5)
    @Volatile private var paddleIniting = false // guard against double setup on restart
    private var overlayButton: View? = null    // floating trigger over other apps
    @Volatile private var readSeq = 0           // utterance id counter for streamed sentences
    private val channelId = "live_reader"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // On-demand trigger from the notification action / in-app button: the
        // service is already running, just arm a single capture.
        if (intent?.action == ACTION_CAPTURE) {
            DiagLog.log("ACTION", "capture requested (running=${projection != null})")
            if (projection == null) { stopSelf(); return START_NOT_STICKY }  // not started yet
            captureRequested = true
            return START_NOT_STICKY
        }
        // Live switch between reading text and describing the scene, from the
        // notification, without leaving the eSight app.
        if (intent?.action == ACTION_TOGGLE_DESCRIBE) {
            val now = !describeEnabled()
            DiagLog.log("ACTION", "toggle describe -> $now")
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
        DiagLog.startSession(this, "device=${Build.MANUFACTURER} ${Build.MODEL} android=${Build.VERSION.SDK_INT}" +
            " | mode=${prefs().getString("ocr_mode", "online")} trigger=${prefs().getString("trigger", "live")}" +
            " describe=${describeEnabled()} preferCellular=${prefs().getBoolean("prefer_cellular", false)}" +
            " onlineModel=${onlineModel()}")
        tts = TextToSpeech(this) { status ->
            // Audible proof that the service is alive AND text-to-speech works.
            DiagLog.log("TTS", "init status=$status (0=SUCCESS)")
            if (status == TextToSpeech.SUCCESS) announce("القارئ جاهز.")
        }
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

        DiagLog.log("CAPTURE", "start dw=$dw dh=$dh scale=$scale dpi=${metrics.densityDpi}")
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
                    if (bmp == null) { DiagLog.log("FRAME", "demand: null bitmap"); return@setOnImageAvailableListener }
                    DiagLog.log("FRAME", "demand -> process eng=${engine()}")
                    val gray = MotionEstimator.grayGrid(bmp)
                    inFlight = true
                    process(bmp, gray)
                    return@setOnImageAvailableListener
                }
                // Live stream mode: OCR the current view at the interval REGARDLESS
                // of whether we're speaking. handleText decides — same text as what
                // is playing -> keep reading (no restart); DIFFERENT text (you moved
                // to a new screen) -> interrupt and read it. A blank view while
                // speaking -> you looked away -> stop.
                val now = System.currentTimeMillis()
                if (isSpeaking && now - speakStartAt > 45000L) { isSpeaking = false; speakingNorm = "" }  // watchdog
                val interval = if (engine() == "online") 2000L else 1000L
                if (inFlight || now - lastSentAt < interval) { image.close(); return@setOnImageAvailableListener }
                val bmp = try { imageToBitmap(image, dw, dh) } catch (e: Exception) { null } finally { image.close() }
                if (bmp == null) { DiagLog.log("FRAME", "null bitmap from capture"); return@setOnImageAvailableListener }
                val fno = ++frameSeq
                val sig = signature(bmp)
                // Only skip a TRULY blank/black frame. Everything else — small or
                // medium text, AND non-text scenes for description — is read. (The
                // old text-detector/sharpness/change gates were dropped: they were
                // missing medium text, blocking description, and causing silence.)
                if (blankSig(sig)) {
                    if (isSpeaking && autoStopEnabled()) {
                        DiagLog.log("HANDLE", "blank view while speaking -> stop (looked away)")
                        tts?.stop(); isSpeaking = false; speakingNorm = ""
                    }
                    blankStreak++
                    DiagLog.log("FRAME", "#$fno skip blank/black (blankStreak=$blankStreak)")
                    if (blankStreak >= 5 && !blankHintSpoken) {
                        blankHintSpoken = true
                        announce("لا ألتقط نصًا من الشاشة. إذا كان مشهد النظارة معروضًا الآن، فقد لا يستطيع النظام تصويره؛ جرّب التقاط لقطة شاشة للتأكّد.")
                    }
                    bmp.recycle(); return@setOnImageAvailableListener
                }
                blankStreak = 0
                lastSentAt = now
                inFlight = true
                val gray = MotionEstimator.grayGrid(bmp)   // for phase-correlation motion check
                DiagLog.log("FRAME", "#$fno READ -> eng=${engine()}")
                process(bmp, gray)
            } catch (e: Exception) {
                DiagLog.err("FRAME", e)
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

    private fun process(bmp: Bitmap, gray: FloatArray) {
        if (released) { bmp.recycle(); inFlight = false; return }
        scope.launch {
            // If the user picked the offline engine but it isn't ready yet, we
            // fall back to online — say so once so they know why it needs internet.
            if (!describeEnabled() && !fallbackAnnounced &&
                prefs().getString("ocr_mode", "online") == "paddle" && paddle?.ready() != true) {
                fallbackAnnounced = true
                announce("محرّك عدم الاتصال غير جاهز بعد، سأستخدم الإنترنت مؤقتًا.")
            }
            val eng = engine()
            if (eng == "online") {
                // Online path STREAMS the read and speaks it sentence-by-sentence
                // for low latency; it decides new-vs-same from frame motion.
                try { processOnlineStreaming(bmp, gray) }
                catch (e: Exception) { DiagLog.err("OCR", e); bmp.recycle(); inFlight = false }
                return@launch
            }
            // Offline (PaddleOCR): single-shot recognition, then the text decision.
            val t0 = System.currentTimeMillis()
            var failure: String? = null
            val text = try {
                recognizePaddle(bmp)
            } catch (e: Exception) { failure = e.message; DiagLog.err("OCR", e); "" } finally { bmp.recycle() }
            val dt = System.currentTimeMillis() - t0
            if (failure != null) {
                DiagLog.log("OCR", "FAILED eng=$eng ${dt}ms: $failure")
            } else {
                DiagLog.log("OCR", "ok eng=$eng ${dt}ms chars=${text.length} \"${text.take(120).replace('\n', ' ')}\"")
            }
            try { handleText(text, gray) } catch (e: Exception) { DiagLog.err("HANDLE", e); inFlight = false }
        }
    }

    /**
     * Online reading via streaming: decide new-vs-same from PHASE-CORRELATION
     * motion (no need to wait for text), then stream the recognition and speak
     * each complete sentence as it arrives. inFlight is held only while the
     * stream is being RECEIVED (a couple of seconds); TTS then plays on after,
     * during which the capture loop can detect a new screen and interrupt.
     */
    private suspend fun processOnlineStreaming(bmp: Bitmap, gray: FloatArray) {
        // Same-view gate (live mode): skip re-reading the view we're already
        // reading / just read. A slight movement aligns with a low residual.
        if (!demandMode()) {
            val ref = readGray
            if (ref != null) {
                val m = MotionEstimator.estimate(ref, gray)
                if (m.valid && m.residual <= MotionEstimator.SAME_RESIDUAL) {
                    DiagLog.log("HANDLE", "aligned view (dx=${m.dx} dy=${m.dy} res=${fmt1(m.residual)}) -> keep, no re-read")
                    bmp.recycle(); inFlight = false; return
                }
            }
        }
        readGray = gray
        val describe = describeEnabled()
        val jpeg = buildOnlineJpeg(bmp, describe)
        bmp.recycle()
        val model = onlineModel()
        val mode = if (describe) "describe" else "ocr"
        DiagLog.log("NET", "online STREAM model=$model mode=$mode jpeg=${jpeg.size}B")
        var first = true
        var any = false
        try {
            ConvertApi.liveOcrStream(jpeg, model, mode) { sentence ->
                any = true
                speakSentence(sentence, first)
                first = false
            }
        } catch (e: Exception) {
            DiagLog.log("OCR", "FAILED eng=online STREAM: ${e.message}")
            announceError(e.message)
        }
        if (!any && demandMode()) announce("لا يوجد نص واضح لأقرأه في هذا المشهد.")
        inFlight = false
    }

    /** Build the JPEG uploaded to the server. Reading frames go near-full-res +
     *  high quality so small text stays legible; describe frames stay light. */
    private fun buildOnlineJpeg(bmp: Bitmap, describe: Boolean): ByteArray {
        val maxEdge = if (describe) 1280 else 2048
        val quality = if (describe) 65 else 85
        val scaled = scaleToLongEdge(bmp, maxEdge)
        val norm = normalizeLighting(scaled)     // CLAHE lighting adaptation
        if (scaled !== bmp) scaled.recycle()
        val jpeg = compressJpeg(norm, quality)
        norm.recycle()
        return jpeg
    }

    /** The chosen Gemini model (user-selectable; defaults to the fast Lite). */
    private fun onlineModel(): String =
        prefs().getString("online_model", "gemini-3.5-flash-lite") ?: "gemini-3.5-flash-lite"

    private var lastErrAt = 0L
    /** Speak WHY a read failed (throttled) so silent failures become diagnosable. */
    private fun announceError(msg: String?) {
        val now = System.currentTimeMillis()
        if (now - lastErrAt < 8000) return
        lastErrAt = now
        val m = msg ?: ""
        val human = when {
            m.contains("Unable to resolve host") || m.contains("failed to connect") ||
                m.contains("timeout", true) || m.contains("timed out", true) ->
                "تعذّر اتصال التطبيق بالإنترنت. إن كنت على واي‑فاي النظارة فعّل «استخدم بيانات الجوّال»، أو تأكّد من الإنترنت."
            m.contains("HTTP 5") -> "خطأ من الخادم، حاول بعد قليل."
            m.contains("HTTP 4") || m.contains("ocr_failed") -> "تعذّرت القراءة من الخادم."
            else -> "تعذّرت القراءة، تحقّق من الاتصال."
        }
        announce(human)
    }

    /** Which engine to use for this frame (describe always needs online). */
    private fun engine(): String {
        if (describeEnabled()) return "online"
        return when (prefs().getString("ocr_mode", "online")) {
            "paddle" -> if (paddle?.ready() == true) "paddle" else "online"
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


    /**
     * Lighting-adaptive correction shared by ALL modes so the reader copes with
     * dim, bright, back-lit, shadowed or low-contrast scenes. Uses CLAHE
     * (Contrast Limited Adaptive Histogram Equalization) on the luminance
     * channel — tile-local histogram equalization with a clip limit that lifts
     * shadows and boosts local text contrast WITHOUT amplifying noise, far
     * stronger on uneven lighting than a single global stretch. The equalized
     * luma is applied back to RGB via a per-pixel scale so colour is preserved.
     * Always returns a NEW bitmap.
     */
    private fun normalizeLighting(src: Bitmap): Bitmap {
        val w = src.width; val h = src.height
        val out = Bitmap.createBitmap(w.coerceAtLeast(1), h.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        if (w <= 0 || h <= 0) return out
        val px = IntArray(w * h)
        src.getPixels(px, 0, w, 0, 0, w, h)
        val luma = IntArray(w * h)
        for (i in px.indices) {
            val c = px[i]
            luma[i] = (0.299 * ((c shr 16) and 0xFF) +
                0.587 * ((c shr 8) and 0xFF) + 0.114 * (c and 0xFF)).toInt().coerceIn(0, 255)
        }
        val eq = clahe(luma, w, h)
        val res = IntArray(w * h)
        for (i in px.indices) {
            val c = px[i]; val y = luma[i]; val ny = eq[i]
            if (y <= 0) { res[i] = (0xFF shl 24) or (ny shl 16) or (ny shl 8) or ny; continue }
            val scale = ny.toFloat() / y
            val r = (((c shr 16) and 0xFF) * scale).toInt().coerceIn(0, 255)
            val g = (((c shr 8) and 0xFF) * scale).toInt().coerceIn(0, 255)
            val b = ((c and 0xFF) * scale).toInt().coerceIn(0, 255)
            res[i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
        }
        out.setPixels(res, 0, w, 0, 0, w, h)
        return out
    }

    /**
     * CLAHE on a grayscale plane: split into an 8×8 grid of tiles, build a
     * clipped, equalized 0..255 mapping per tile (the clip limit caps how much
     * any single intensity is amplified — this is what prevents noise blow-up),
     * then map each pixel by BILINEARLY interpolating the four surrounding tile
     * mappings so no block edges appear. Returns the new luminance plane.
     */
    private fun clahe(luma: IntArray, w: Int, h: Int): IntArray {
        val tilesX = 8; val tilesY = 8
        val tw = (w + tilesX - 1) / tilesX
        val th = (h + tilesY - 1) / tilesY
        val clip = maxOf(1, (3.0 * tw * th / 256).toInt())   // contrast limit
        val maps = Array(tilesX * tilesY) { IntArray(256) }
        for (ty in 0 until tilesY) {
            val y0 = ty * th; val y1 = minOf(y0 + th, h)
            for (tx in 0 until tilesX) {
                val x0 = tx * tw; val x1 = minOf(x0 + tw, w)
                val hist = IntArray(256)
                var count = 0
                for (y in y0 until y1) {
                    val row = y * w
                    for (x in x0 until x1) { hist[luma[row + x]]++; count++ }
                }
                val map = maps[ty * tilesX + tx]
                if (count == 0) { for (v in 0..255) map[v] = v; continue }
                var excess = 0                       // clip the histogram
                for (v in 0..255) if (hist[v] > clip) { excess += hist[v] - clip; hist[v] = clip }
                val inc = excess / 256; val rem = excess % 256
                for (v in 0..255) hist[v] += inc     // redistribute clipped mass
                for (v in 0 until rem) hist[v]++
                var cdf = 0
                val sc = 255.0 / count
                for (v in 0..255) { cdf += hist[v]; map[v] = (cdf * sc).toInt().coerceIn(0, 255) }
            }
        }
        val outL = IntArray(w * h)
        for (y in 0 until h) {
            val gy = y.toFloat() / th - 0.5f
            val fy0 = kotlin.math.floor(gy).toInt()
            val fy = gy - fy0
            val ty0 = fy0.coerceIn(0, tilesY - 1); val ty1 = (fy0 + 1).coerceIn(0, tilesY - 1)
            val row = y * w
            for (x in 0 until w) {
                val gx = x.toFloat() / tw - 0.5f
                val fx0 = kotlin.math.floor(gx).toInt()
                val fx = gx - fx0
                val tx0 = fx0.coerceIn(0, tilesX - 1); val tx1 = (fx0 + 1).coerceIn(0, tilesX - 1)
                val v = luma[row + x]
                val m00 = maps[ty0 * tilesX + tx0][v]; val m01 = maps[ty0 * tilesX + tx1][v]
                val m10 = maps[ty1 * tilesX + tx0][v]; val m11 = maps[ty1 * tilesX + tx1][v]
                val top = m00 + (m01 - m00) * fx
                val bot = m10 + (m11 - m10) * fx
                outL[row + x] = (top + (bot - top) * fy).toInt().coerceIn(0, 255)
            }
        }
        return outL
    }

    private fun scaleToLongEdge(src: Bitmap, maxEdge: Int): Bitmap {
        val longEdge = maxOf(src.width, src.height)
        if (longEdge <= maxEdge) return src
        val s = maxEdge.toFloat() / longEdge
        return Bitmap.createScaledBitmap(
            src, (src.width * s).toInt().coerceAtLeast(1), (src.height * s).toInt().coerceAtLeast(1), true)
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
     * Decide what to speak for a freshly recognised frame, using BOTH the text
     * and PHASE-CORRELATION motion between this frame and the one being read. We
     * OCR every interval even while speaking, so a new read must only interrupt
     * when the view REALLY changed:
     *  - SAME text as what is playing -> keep reading (no restart).
     *  - DIFFERENT text BUT the frame only shifted (a slight glasses movement:
     *    consistent translation, low aligned residual) -> OCR jitter, NOT a new
     *    screen -> keep reading. (Fixes "any tiny movement restarts the read".)
     *  - DIFFERENT text AND the content actually changed (no consistent shift /
     *    high residual) -> new screen -> speak() flushes and reads it now.
     *  - empty result -> engine miss/timeout, keep the current read.
     */
    private fun handleText(text: String, gray: FloatArray) {
        inFlight = false
        if (text.isBlank()) {
            // An empty result can mean the engine failed (a Gemini timeout, or
            // PaddleOCR missing a frame) — NOT that the user looked away. Do NOT
            // stop the current read here or every latency spike would cut off a
            // good read. Genuine look-away (a blank/black view) is detected by
            // the frame-signature check in the capture loop, which stops there.
            DiagLog.log("HANDLE", "empty result (engine returned nothing) -> keep current read")
            if (demandMode()) announce("لا يوجد نص واضح لأقرأه في هذا المشهد.")
            return
        }
        if (demandMode()) {
            readGray = gray
            lastSpoken = text
            speak(text)
            return
        }
        if (isNearDuplicate(text)) {
            DiagLog.log("HANDLE", "same content -> keep reading (no restart)")
            return
        }
        // Text differs — but only treat it as a NEW screen if the view's CONTENT
        // actually changed. Phase-correlate against the frame we're reading: if
        // it's just a translation (slight movement) that aligns with a low
        // residual, the text difference is OCR jitter -> keep reading.
        val ref = readGray
        if (ref != null) {
            val m = MotionEstimator.estimate(ref, gray)
            if (m.valid && m.residual <= MotionEstimator.SAME_RESIDUAL) {
                DiagLog.log("HANDLE", "aligned view (dx=${m.dx} dy=${m.dy} res=${fmt1(m.residual)}) -> slight movement, keep reading")
                return
            }
            DiagLog.log("HANDLE", "content changed (valid=${m.valid} dx=${m.dx} dy=${m.dy} res=${fmt1(m.residual)}) -> new screen")
        }
        // New content — read it now (flushes any current utterance).
        readGray = gray
        lastSpoken = text
        speak(text)
    }

    // ---- Settings -----------------------------------------------------------

    private fun prefs() = getSharedPreferences("live_reader", Context.MODE_PRIVATE)

    private fun fmt1(v: Double) = String.format(Locale.US, "%.1f", v)

    private fun describeEnabled(): Boolean = prefs().getBoolean("describe", false)

    private fun autoStopEnabled(): Boolean = prefs().getBoolean("autostop", true)

    /** "live" = continuous auto-reading; "demand" = only on an explicit trigger. */
    private fun demandMode(): Boolean = prefs().getString("trigger", "live") == "demand"

    private fun paddleSelected(): Boolean = prefs().getString("ocr_mode", "online") == "paddle"

    // ---- Offline on-device OCR (PaddleOCR Arabic PP-OCRv5 / ONNX) -----------

    private fun initPaddleIfNeeded() {
        if (!paddleSelected() || paddle != null || paddleIniting) return
        paddleIniting = true
        scope.launch {
            DiagLog.log("PADDLE", "setup start")
            val p = PaddleOcr(this@ScreenReaderService)
            announce("جارٍ تجهيز محرّك عدم الاتصال العربي، قد يأخذ دقائق عند أول مرة.")
            val err = p.setup()
            if (err == null) {
                paddle = p
                DiagLog.log("PADDLE", "ready")
                announce("محرّك عدم الاتصال جاهز، يعمل الآن بدون إنترنت.")
            } else {
                DiagLog.log("PADDLE", "setup FAILED: $err")
                announce("تعذّر تجهيز محرّك عدم الاتصال، سيتم استخدام الإنترنت. السبب: $err")
            }
            paddleIniting = false
        }
    }

    /** Speak a short spoken status update. */
    private fun announce(msg: String) {
        announcing = true
        tts?.language = Locale("ar")
        tts?.speak(msg, TextToSpeech.QUEUE_ADD, null, "announce-" + System.nanoTime())
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

    private fun compressJpeg(bmp: Bitmap, quality: Int = 70): ByteArray {
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), out)
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

    /** True only for a genuinely uniform frame (blank wall / black capture).
     *  Threshold is very low so even small/medium text easily passes. */
    private fun blankSig(sig: IntArray): Boolean {
        var sum = 0.0; var sumSq = 0.0
        for (v in sig) { sum += v; sumSq += v.toDouble() * v }
        val n = sig.size
        val mean = sum / n
        val variance = sumSq / n - mean * mean
        return variance < 2.0
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
        speakStartAt = System.currentTimeMillis()
        // readGray (the frame being read) is set by the caller (handleText) from
        // that frame's own grid, so it can't race the capture thread here.
        val baseId = System.nanoTime().toString()
        currentUtterId = baseId
        // Speak each script run in its own language so mixed Arabic/English text
        // isn't voiced entirely in one language (mispronunciation).
        val runs = splitByScript(text)
        DiagLog.log("SPEAK", "runs=${runs.size} rate=$rate \"${text.take(60).replace('\n', ' ')}\"")
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

    /**
     * Speak ONE streamed sentence. The first sentence of a new read flushes the
     * previous utterance (interrupt); the rest queue after it, so a long read
     * plays as continuous natural sentences. Each sentence becomes the "current"
     * utterance, so isSpeaking only clears when the LAST sentence finishes.
     */
    private fun speakSentence(text: String, first: Boolean) {
        val rate = prefs().getFloat("rate", 1.0f)
        tts?.setSpeechRate(rate)
        isSpeaking = true
        speakStartAt = System.currentTimeMillis()
        speakingNorm = normalize(text)
        val baseId = "read-" + (readSeq++)
        currentUtterId = baseId
        val runs = splitByScript(text)
        DiagLog.log("SPEAK", "sentence first=$first runs=${runs.size} \"${text.take(50).replace('\n', ' ')}\"")
        var mode = if (first && !announcing) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
        for ((idx, run) in runs.withIndex()) {
            val ar = run.any { it.code in 0x0600..0x06FF }
            tts?.language = if (ar) Locale("ar") else Locale.ENGLISH
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
            .setContentTitle("نور — قارئ النظارة")
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
        DiagLog.log("SVC", "onDestroy — session ending")
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
        paddle?.close()
    }

    companion object {
        const val ACTION_CAPTURE = "com.bellinghamfolks.docconverter.CAPTURE"
        const val ACTION_TOGGLE_DESCRIBE = "com.bellinghamfolks.docconverter.TOGGLE_DESCRIBE"
    }
}
