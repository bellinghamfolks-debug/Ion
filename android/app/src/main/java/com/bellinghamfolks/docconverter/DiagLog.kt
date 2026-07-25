package com.bellinghamfolks.docconverter

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Append-only diagnostic log for the live reader. Captures every meaningful step
 * — session start, permissions, engine setup, per-frame gate decisions, each OCR
 * attempt (engine, network, HTTP code, timing, result/error), speech, and
 * teardown — into a single file the user can share. This turns "it went silent"
 * into a precise, inspectable trace.
 *
 * The file lives in the app's external files dir so it is easy to share:
 *   Android/data/com.bellinghamfolks.docconverter/files/live-reader-diagnostic.log
 */
object DiagLog {
    private const val FILE = "live-reader-diagnostic.log"
    private const val MAX_BYTES = 2_000_000L
    private val lock = Any()
    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    @Volatile private var file: File? = null

    fun init(ctx: Context) {
        if (file == null) {
            val dir = ctx.getExternalFilesDir(null) ?: ctx.filesDir
            file = File(dir, FILE)
        }
    }

    /** Begin a new session block; trims the file if it has grown too large. */
    fun startSession(ctx: Context, header: String) {
        init(ctx)
        synchronized(lock) {
            try {
                val f = file ?: return
                if (f.exists() && f.length() > MAX_BYTES) f.writeText("")
                f.appendText("\n\n========== SESSION START ${stamp()} ==========\n$header\n")
            } catch (_: Exception) {}
        }
    }

    fun log(tag: String, msg: String) {
        synchronized(lock) {
            try { file?.appendText("${stamp()}  ${tag.padEnd(7)} $msg\n") } catch (_: Exception) {}
        }
    }

    fun err(tag: String, t: Throwable) {
        log(tag, "EXCEPTION ${t.javaClass.simpleName}: ${t.message}")
        synchronized(lock) {
            try { file?.appendText(t.stackTraceToString().take(1600) + "\n") } catch (_: Exception) {}
        }
    }

    fun clear(ctx: Context) {
        init(ctx)
        synchronized(lock) { try { file?.writeText("cleared ${stamp()}\n") } catch (_: Exception) {} }
    }

    fun file(ctx: Context): File { init(ctx); return file!! }

    private fun stamp(): String = fmt.format(Date())
}
