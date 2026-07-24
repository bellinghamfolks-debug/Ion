package com.bellinghamfolks.docconverter

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat

/**
 * Starts the glasses live reader: asks for screen-capture permission, then hands
 * the projection to ScreenReaderService which OCRs the eSight camera view.
 */
class LiveReaderActivity : AppCompatActivity() {

    private lateinit var status: TextView

    private val projectionLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == Activity.RESULT_OK && result.data != null) {
                val svc = Intent(this, ScreenReaderService::class.java).apply {
                    putExtra("code", result.resultCode)
                    putExtra("data", result.data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(svc)
                else startService(svc)
                status.text = "القراءة فعّالة — افتح تطبيق eSight ووجّه النظارة نحو النص."
            } else {
                status.text = "لم تُمنح صلاحية مشاركة الشاشة."
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33) {
            ActivityCompat.requestPermissions(
                this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 96, 48, 48)
            layoutDirection = ViewGroup.LAYOUT_DIRECTION_RTL
        }
        val title = TextView(this).apply {
            text = "القارئ اللحظي للنظارة"; textSize = 24f; gravity = Gravity.CENTER
        }
        status = TextView(this).apply {
            text = "يقرأ النص الظاهر من كاميرا نظارة eSight تلقائيًا بصوت عربي/إنجليزي."
            textSize = 17f; setPadding(0, 24, 0, 24)
        }
        val startBtn = Button(this).apply {
            text = "بدء القراءة (مشاركة الشاشة)"; textSize = 20f
            setOnClickListener {
                val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                projectionLauncher.launch(mpm.createScreenCaptureIntent())
            }
        }
        val stopBtn = Button(this).apply {
            text = "إيقاف"; textSize = 20f
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            lp.topMargin = 24; layoutParams = lp
            setOnClickListener {
                stopService(Intent(this@LiveReaderActivity, ScreenReaderService::class.java))
                status.text = "أُوقفت القراءة."
            }
        }
        root.addView(title)
        root.addView(status)
        root.addView(startBtn)
        root.addView(stopBtn)
        setContentView(root)
    }
}
