package com.bellinghamfolks.docconverter

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
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
import android.speech.tts.TextToSpeech
import android.util.DisplayMetrics
import android.view.WindowManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.util.Locale

/**
 * Foreground service: mirrors the screen (the eSight Companion camera view),
 * throttles to ~1 frame/2s, OCRs each frame on the server, and speaks new text
 * aloud in Arabic/English. No on-device OCR — just capture + network + TTS.
 */
class ScreenReaderService : Service() {

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var tts: TextToSpeech? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private var lastSpoken = ""
    private var inFlight = false
    private var lastSentAt = 0L
    private val model = "gemini-3.6-flash"
    private val channelId = "live_reader"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, buildNotification())
        }
        tts = TextToSpeech(this) { }
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
        val scale = minOf(1f, 1440f / maxOf(metrics.widthPixels, metrics.heightPixels))
        val dw = (metrics.widthPixels * scale).toInt().coerceAtLeast(1)
        val dh = (metrics.heightPixels * scale).toInt().coerceAtLeast(1)

        val reader = ImageReader.newInstance(dw, dh, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        virtualDisplay = proj.createVirtualDisplay(
            "live-reader", dw, dh, metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader.surface, null, null)

        reader.setOnImageAvailableListener({ r ->
            val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            val now = System.currentTimeMillis()
            if (inFlight || now - lastSentAt < 2000) { image.close(); return@setOnImageAvailableListener }
            lastSentAt = now
            val jpeg = try { toJpeg(image, dw, dh) } catch (e: Exception) { null } finally { image.close() }
            if (jpeg != null) { inFlight = true; send(jpeg) }
        }, Handler(Looper.getMainLooper()))
    }

    private fun toJpeg(image: Image, dw: Int, dh: Int): ByteArray {
        val plane = image.planes[0]
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * dw
        val bmp = Bitmap.createBitmap(dw + rowPadding / pixelStride, dh, Bitmap.Config.ARGB_8888)
        bmp.copyPixelsFromBuffer(buffer)
        val cropped = Bitmap.createBitmap(bmp, 0, 0, dw, dh)
        val out = ByteArrayOutputStream()
        cropped.compress(Bitmap.CompressFormat.JPEG, 70, out)
        bmp.recycle(); cropped.recycle()
        return out.toByteArray()
    }

    private fun send(jpeg: ByteArray) {
        scope.launch {
            try {
                val text = ConvertApi.liveOcr(jpeg, model).trim()
                if (text.isNotEmpty() && !isNearDuplicate(text)) {
                    lastSpoken = text
                    speak(text)
                }
            } catch (_: Exception) {
            } finally {
                inFlight = false
            }
        }
    }

    private fun isNearDuplicate(text: String): Boolean {
        val a = normalize(text)
        val b = normalize(lastSpoken)
        return a == b || (b.length >= 8 && (a.contains(b) || b.contains(a)))
    }

    private fun normalize(s: String): String =
        s.replace(Regex("[\\u064B-\\u0652\\u0640\\s]+"), " ").trim().lowercase()

    private fun speak(text: String) {
        val isArabic = text.any { it.code in 0x0600..0x06FF }
        tts?.language = if (isArabic) Locale("ar") else Locale.ENGLISH
        // Apply the user's chosen reading speed (updated live from the UI).
        val rate = getSharedPreferences("live_reader", Context.MODE_PRIVATE).getFloat("rate", 1.0f)
        tts?.setSpeechRate(rate)
        tts?.speak(text, TextToSpeech.QUEUE_ADD, null, System.nanoTime().toString())
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "القارئ اللحظي", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, channelId) else Notification.Builder(this)
        return builder
            .setContentTitle("القارئ اللحظي للنظارة")
            .setContentText("يقرأ النص من كاميرا النظارة…")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        virtualDisplay?.release()
        imageReader?.close()
        projection?.stop()
        tts?.stop()
        tts?.shutdown()
    }
}
