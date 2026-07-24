package com.bellinghamfolks.docconverter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat

/**
 * Starts the glasses live reader: asks for screen-capture permission, then hands
 * the projection to ScreenReaderService which OCRs the eSight camera view.
 * Also lets the user pick the reading speed and go back.
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
            setPadding(48, 48, 48, 48)
            layoutDirection = ViewGroup.LAYOUT_DIRECTION_RTL
        }

        // Back button (present on this screen so the user can always return).
        root.addView(Button(this).apply {
            text = "‹ رجوع"
            textSize = 18f
            setOnClickListener { finish() }
        })

        root.addView(TextView(this).apply {
            text = "القارئ اللحظي للنظارة"; textSize = 24f; gravity = Gravity.CENTER
            setPadding(0, 24, 0, 8)
        })
        status = TextView(this).apply {
            text = "يقرأ النص الظاهر من كاميرا نظارة eSight تلقائيًا بصوت عربي/إنجليزي."
            textSize = 17f; setPadding(0, 8, 0, 24)
        }
        root.addView(status)

        root.addView(bigButton("بدء القراءة (مشاركة الشاشة)") {
            val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projectionLauncher.launch(mpm.createScreenCaptureIntent())
        })
        root.addView(bigButton("إيقاف") {
            stopService(Intent(this, ScreenReaderService::class.java))
            status.text = "أُوقفت القراءة."
        })

        // --- Reading speed ---
        root.addView(TextView(this).apply {
            text = "سرعة القراءة:"; textSize = 18f; setPadding(0, 32, 0, 8)
        })
        val speedRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutDirection = ViewGroup.LAYOUT_DIRECTION_RTL
        }
        speedRow.addView(speedButton("بطيء", 0.7f))
        speedRow.addView(speedButton("عادي", 1.0f))
        speedRow.addView(speedButton("سريع", 1.4f))
        speedRow.addView(speedButton("أسرع", 1.8f))
        root.addView(speedRow)

        setContentView(ScrollView(this).apply { addView(root) })
    }

    private fun bigButton(text: String, onClick: () -> Unit): Button = Button(this).apply {
        this.text = text; textSize = 20f
        val lp = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        lp.topMargin = 20; layoutParams = lp
        setOnClickListener { onClick() }
    }

    private fun speedButton(label: String, rate: Float): Button = Button(this).apply {
        text = label; textSize = 17f
        val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        lp.marginStart = 8; lp.marginEnd = 8; layoutParams = lp
        setOnClickListener {
            getSharedPreferences("live_reader", Context.MODE_PRIVATE)
                .edit().putFloat("rate", rate).apply()
            status.text = "سرعة القراءة: $label"
        }
    }
}
