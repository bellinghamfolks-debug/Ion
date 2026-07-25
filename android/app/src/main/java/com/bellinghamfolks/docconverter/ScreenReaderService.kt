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
    private var speakingNorm = ""       // normalised text of the current utterance
    private var currentUtterId = ""
    private var inFlight = false
    private var lastSentAt = 0L
    private var lastSignature: IntArray? = null   // last frame we actually processed
    @Volatile private var isSpeaking = false       // an utterance is playing now
    private var switchStreak = 0                    // debounce for jumping to new text
    @Volatile private var captureRequested = false  // on-demand: read/describe once now
    private var blankStreak = 0                      // consecutive black/blank captured frames
    @Volatile private var blankHintSpoken = false    // one-shot "screen looks black" hint

    private var localOcr: TessBaseAPI? = null
    @Volatile private var localReady = false
    private var overlayButton: View? = null   // floating trigger over other apps
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, buildNotification())
        }
        tts = TextToSpeech(this) { }
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) { if (utteranceId == currentUtterId) isSpeaking = true }
            override fun onDone(utteranceId: String?) { if (utteranceId == currentUtterId) { isSpeaking = false; speakingNorm = "" } }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) { if (utteranceId == currentUtterId) { isSpeaking = false; speakingNorm = "" } }
        })
        initLocalOcrIfNeeded()
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

        reader.setOnImageAvailableListener({ r ->
            val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            // On-demand mode: ignore every frame until the user asks (notification
            // action or in-app button), then read/describe the current view once,
            // unconditionally (no change/blank skip — they explicitly requested it).
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
            // Local OCR has no network cost, so it can refresh much faster and
            // feel instant; the online path stays at ~2s (Gemini Lite).
            val minInterval = if (useLocal()) 700L else 2000L
            if (inFlight || now - lastSentAt < minInterval) { image.close(); return@setOnImageAvailableListener }
            val bmp = try { imageToBitmap(image, dw, dh) } catch (e: Exception) { null } finally { image.close() }
            if (bmp == null) return@setOnImageAvailableListener
            val sig = signature(bmp)
            // FREE on-device savers: skip a blank/near-uniform view (no text) and
            // skip a view identical to the last one we processed (you are still
            // looking at the same thing). Only genuinely NEW content is analysed.
            if (isBlank(sig)) {
                // Diagnose the common "eSight camera view is a secure/overlay
                // surface -> captured as black" case, so the user hears WHY it is
                // silent instead of nothing at all.
                blankStreak++
                if (blankStreak >= 4 && !blankHintSpoken) {
                    blankHintSpoken = true
                    announce("لا ألتقط نصًا من الشاشة. إذا كان مشهد النظارة معروضًا الآن، فقد لا يستطيع النظام تصويره؛ جرّب التقاط لقطة شاشة للتأكّد.")
                }
                bmp.recycle(); return@setOnImageAvailableListener
            }
            blankStreak = 0
            if (similar(sig, lastSignature)) { bmp.recycle(); return@setOnImageAvailableListener }
            lastSignature = sig
            lastSentAt = now
            inFlight = true
            process(bmp)
        }, Handler(Looper.getMainLooper()))

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
        scope.launch {
            val text = try {
                if (useLocal()) recognizeLocal(bmp) else recognizeOnline(bmp)
            } catch (_: Exception) { "" } finally { bmp.recycle() }
            handleText(text)
        }
    }

    private suspend fun recognizeOnline(bmp: Bitmap): String {
        // Keep the upload light/fast: online doesn't need the full 2160 capture.
        val scaled = scaleToLongEdge(bmp, 1440)
        val jpeg = compressJpeg(scaled)
        if (scaled !== bmp) scaled.recycle()
        val mode = if (describeEnabled()) "describe" else "ocr"
        return ConvertApi.liveOcr(jpeg, onlineModel, mode).trim()
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
        val prepped = preprocessForOcr(bmp)
        val text = synchronized(api) {
            api.setImage(prepped)
            val t = api.getUTF8Text() ?: ""
            val conf = try { api.meanConfidence() } catch (_: Exception) { 0 }
            api.clear()
            // Below this confidence Tesseract is guessing at noise -> say nothing
            // rather than reading out garbled symbols.
            if (conf < 55) "" else t
        }
        if (prepped !== bmp) prepped.recycle()
        return cleanOcr(text)
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
        val iw = w + 1
        val integral = LongArray(iw * (h + 1))
        for (y in 0 until h) {
            var rowSum = 0L
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
                val count = ((x2 - x1 + 1) * (y2 - y1 + 1)).toLong()
                val sum = integral[(y2 + 1) * iw + (x2 + 1)] - integral[y1 * iw + (x2 + 1)] -
                    integral[(y2 + 1) * iw + x1] + integral[y1 * iw + x1]
                val black = lum[y * w + x].toLong() * count * 100 <= sum * (100 - t)
                out[y * w + x] = if (black) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
            }
        }
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.setPixels(out, 0, w, 0, 0, w, h)
        return bmp
    }

    /** Drop noise lines (mostly symbols); keep lines that are real words. */
    private fun cleanOcr(raw: String): String {
        val kept = raw.split('\n').map { it.trim() }.filter { line ->
            if (line.isEmpty()) return@filter false
            val letters = line.count { it.isLetter() }
            letters >= 2 && letters.toDouble() / line.length >= 0.5
        }
        return kept.joinToString(" ").trim()
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
        val dontInterrupt = describeEnabled()

        if (isSpeaking) {
            if (dontInterrupt || similarity(newNorm, speakingNorm) >= 0.5) {
                switchStreak = 0            // same text / narrating -> keep going, no restart
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

        // Idle: read new text, but not something we just finished reading.
        switchStreak = 0
        if (!isNearDuplicate(text)) {
            lastSpoken = text
            speak(text)
        }
    }

    // ---- Settings -----------------------------------------------------------

    private fun prefs() = getSharedPreferences("live_reader", Context.MODE_PRIVATE)

    /** Local (Tesseract) OCR is only used when selected AND ready AND not describing. */
    private fun useLocal(): Boolean =
        localReady && prefs().getString("ocr_mode", "online") == "local" && !describeEnabled()

    private fun describeEnabled(): Boolean = prefs().getBoolean("describe", false)

    private fun autoStopEnabled(): Boolean = prefs().getBoolean("autostop", true)

    private fun localSelected(): Boolean = prefs().getString("ocr_mode", "online") == "local"

    /** "live" = continuous auto-reading; "demand" = only on an explicit trigger. */
    private fun demandMode(): Boolean = prefs().getString("trigger", "live") == "demand"

    // ---- On-device OCR (Tesseract) -----------------------------------------

    private fun initLocalOcrIfNeeded() {
        if (!localSelected()) return
        scope.launch {
            try {
                val dataDir = filesDir                     // parent of the tessdata/ folder
                // First run only: the language data is fetched once (needs
                // internet), then the local scanner works fully offline. Speak
                // the state so a blind user knows what's happening.
                if (!traineddataPresent(dataDir)) announce("جارٍ تنزيل بيانات القراءة المحلية، لحظة من فضلك.")
                ensureTraineddata(dataDir)
                val api = TessBaseAPI()
                if (api.init(dataDir.absolutePath, "ara+eng")) {
                    // SPARSE_TEXT finds text anywhere in a real-world scene without
                    // assuming a clean page layout — far more robust than PSM_AUTO
                    // on photographic camera frames (signs, labels, held pages).
                    api.pageSegMode = TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT
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
        tts?.language = Locale("ar")
        tts?.speak(msg, TextToSpeech.QUEUE_ADD, null, "announce-" + System.nanoTime())
    }

    /** Download the fast ara/eng models once into filesDir/tessdata/. */
    private fun ensureTraineddata(dataDir: File) {
        val tess = File(dataDir, "tessdata").apply { mkdirs() }
        for (lang in listOf("ara", "eng")) {
            val f = File(tess, "$lang.traineddata")
            if (f.exists() && f.length() > 0) continue
            val url = URL("https://github.com/tesseract-ocr/tessdata_fast/raw/main/$lang.traineddata")
            val conn = url.openConnection() as HttpURLConnection
            try {
                conn.connectTimeout = 20000
                conn.readTimeout = 120000
                conn.instanceFollowRedirects = true
                conn.inputStream.use { input -> f.outputStream().use { input.copyTo(it) } }
            } finally { conn.disconnect() }
        }
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

    /** Cheap 8x8 grayscale perceptual signature for change/blank detection. */
    private fun signature(bmp: Bitmap): IntArray {
        val n = 8
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

    private fun isBlank(sig: IntArray): Boolean {
        val mean = sig.average()
        var variance = 0.0
        for (v in sig) { val d = v - mean; variance += d * d }
        variance /= sig.size
        return variance < 15.0     // near-uniform => no text to read (lowered so
                                   // dim-but-real camera frames still get a chance)
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
        val isArabic = text.any { it.code in 0x0600..0x06FF }
        tts?.language = if (isArabic) Locale("ar") else Locale.ENGLISH
        // Apply the user's chosen reading speed (updated live from the UI).
        val rate = prefs().getFloat("rate", 1.0f)
        tts?.setSpeechRate(rate)
        speakingNorm = normalize(text)
        isSpeaking = true
        val id = System.nanoTime().toString()
        currentUtterId = id
        // FLUSH is safe here: handleText only calls speak() for genuinely new
        // text, never to restart the same passage the user is still reading.
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
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
        return builder.build()
    }

    private fun capturePendingIntent(): PendingIntent {
        val i = Intent(this, ScreenReaderService::class.java).setAction(ACTION_CAPTURE)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getService(this, 0, i, flags)
    }

    override fun onDestroy() {
        super.onDestroy()
        removeOverlayButton()
        scope.cancel()
        virtualDisplay?.release()
        imageReader?.close()
        projection?.stop()
        tts?.stop()
        tts?.shutdown()
        localOcr?.recycle()
    }

    companion object {
        const val ACTION_CAPTURE = "com.bellinghamfolks.docconverter.CAPTURE"
    }
}
