package com.bellinghamfolks.docconverter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat

/**
 * Sets up and starts the glasses live reader. Lets the user choose the analysis
 * mode (online Gemini Lite / local offline OCR), turn on rich live scene
 * description, set reading speed, and go back — then hands the screen-capture
 * projection to ScreenReaderService.
 */
class LiveReaderActivity : AppCompatActivity() {

    private lateinit var status: TextView
    private val prefs by lazy { getSharedPreferences("live_reader", Context.MODE_PRIVATE) }

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
            text = "يقرأ ما تراه كاميرا نظارة eSight تلقائيًا بصوت عربي/إنجليزي."
            textSize = 17f; setPadding(0, 8, 0, 16)
        }
        root.addView(status)

        // --- Rich live description (flagship toggle) ---
        root.addView(sectionLabel("الوصف الحي الغني"))
        root.addView(TextView(this).apply {
            text = "بدل قراءة النص فقط، يصف لك المشهد كاملًا: المكان، الأشخاص والأشياء " +
                "ومواضعها، ثم يقرأ أي نص ظاهر. (يتطلب الإنترنت)"
            textSize = 15f; setPadding(0, 0, 0, 8)
        })
        root.addView(CheckBox(this).apply {
            text = "تفعيل الوصف الحي الغني للمشهد"
            textSize = 18f
            isChecked = prefs.getBoolean("describe", false)
            setOnCheckedChangeListener { _, checked ->
                prefs.edit().putBoolean("describe", checked).apply()
            }
        })

        // --- Analysis mode ---
        root.addView(sectionLabel("طريقة القراءة"))
        val modeGroup = RadioGroup(this).apply { orientation = RadioGroup.VERTICAL }
        val onlineBtn = RadioButton(this).apply {
            text = "أونلاين — دقيق (Gemini Lite، كل ثانيتين)"; textSize = 17f; id = 101
        }
        val localBtn = RadioButton(this).apply {
            text = "محلي — فوري بدون إنترنت (تجريبي، دقة أقل)"; textSize = 17f; id = 102
        }
        modeGroup.addView(onlineBtn)
        modeGroup.addView(localBtn)
        if (prefs.getString("ocr_mode", "online") == "local") localBtn.isChecked = true else onlineBtn.isChecked = true
        modeGroup.setOnCheckedChangeListener { _, id ->
            val mode = if (id == 102) "local" else "online"
            prefs.edit().putString("ocr_mode", mode).apply()
            if (mode == "local") status.text = "الوضع المحلي: ستُحمَّل بيانات اللغة مرة واحدة عند أول تشغيل."
        }
        root.addView(modeGroup)

        // --- Trigger: continuous live vs on-demand (applies to read AND describe) ---
        root.addView(sectionLabel("طريقة التشغيل"))
        val trigGroup = RadioGroup(this).apply { orientation = RadioGroup.VERTICAL }
        val liveBtn = RadioButton(this).apply {
            text = "بث مباشر — قراءة/وصف تلقائي مستمر"; textSize = 17f; id = 201
        }
        val demandBtn = RadioButton(this).apply {
            text = "عند الطلب — يقرأ/يصف فقط عند الضغط"; textSize = 17f; id = 202
        }
        trigGroup.addView(liveBtn)
        trigGroup.addView(demandBtn)
        if (prefs.getString("trigger", "live") == "demand") demandBtn.isChecked = true else liveBtn.isChecked = true
        trigGroup.setOnCheckedChangeListener { _, id ->
            val t = if (id == 202) "demand" else "live"
            prefs.edit().putString("trigger", t).apply()
            status.text = if (t == "demand")
                "وضع الطلب: اضغط «اقرأ/صِف الآن» أو زر الإشعار عند الحاجة."
            else "بث مباشر مفعّل."
        }
        root.addView(trigGroup)

        // --- Start / stop ---
        root.addView(bigButton("بدء القراءة (مشاركة الشاشة)") {
            val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projectionLauncher.launch(mpm.createScreenCaptureIntent())
        })
        root.addView(bigButton("إيقاف") {
            stopService(Intent(this, ScreenReaderService::class.java))
            status.text = "أُوقفت القراءة."
        })

        // On-demand trigger: read/describe the current view once. (Also available
        // as a notification action so it works while the eSight app is in front.)
        root.addView(bigButton("اقرأ/صِف الآن (عند الطلب)") {
            startService(Intent(this, ScreenReaderService::class.java)
                .setAction(ScreenReaderService.ACTION_CAPTURE))
            status.text = "تمّ الطلب…"
        })

        // Smart auto-switch when the user moves to a different text.
        root.addView(CheckBox(this).apply {
            text = "الانتقال التلقائي عند النظر إلى نص جديد"
            textSize = 16f
            isChecked = prefs.getBoolean("autostop", true)
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            lp.topMargin = 24; layoutParams = lp
            setOnCheckedChangeListener { _, checked ->
                prefs.edit().putBoolean("autostop", checked).apply()
            }
        })

        // --- Reading speed ---
        root.addView(sectionLabel("سرعة القراءة"))
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

    private fun sectionLabel(text: String): TextView = TextView(this).apply {
        this.text = text; textSize = 19f; setTypeface(null, Typeface.BOLD)
        setTextColor(Color.parseColor("#1565C0"))
        setPadding(0, 32, 0, 8)
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
            prefs.edit().putFloat("rate", rate).apply()
            status.text = "سرعة القراءة: $label"
        }
    }
}
