package com.bellinghamfolks.docconverter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
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
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Sets up and starts the glasses live reader. Lets the user choose the analysis
 * mode (online Gemini / offline on-device PaddleOCR), turn on rich live scene
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
        NetManager.setPreferCellular(this, prefs.getBoolean("prefer_cellular", false))
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
            text = "نور — قارئ النظارة"; textSize = 24f; gravity = Gravity.CENTER
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
                // Notify an already-running reader too. Updating preferences
                // alone does not invalidate its current OCR frame reference.
                startService(Intent(this@LiveReaderActivity, ScreenReaderService::class.java)
                    .setAction(ScreenReaderService.ACTION_SET_DESCRIBE)
                    .putExtra(ScreenReaderService.EXTRA_DESCRIBE_ENABLED, checked))
                status.text = if (checked)
                    "تم تشغيل الوصف الحي — سيصف المشهد الحالي الآن."
                else "تم إيقاف الوصف الحي — عاد القارئ إلى قراءة النص."
            }
        })

        // --- Analysis mode ---
        root.addView(sectionLabel("طريقة القراءة"))
        val modeGroup = RadioGroup(this).apply { orientation = RadioGroup.VERTICAL }
        val onlineBtn = RadioButton(this).apply {
            text = "أونلاين — دقيق (Gemini، كل ثانيتين، يتطلب إنترنت)"; textSize = 17f; id = 101
        }
        val paddleBtn = RadioButton(this).apply {
            text = "بدون إنترنت — على الجهاز (PaddleOCR عربي)"; textSize = 17f; id = 103
        }
        modeGroup.addView(onlineBtn)
        modeGroup.addView(paddleBtn)
        when (prefs.getString("ocr_mode", "online")) {
            "paddle" -> paddleBtn.isChecked = true
            else -> onlineBtn.isChecked = true
        }
        modeGroup.setOnCheckedChangeListener { _, id ->
            val mode = if (id == 103) "paddle" else "online"
            prefs.edit().putString("ocr_mode", mode).apply()
            status.text = when (mode) {
                "paddle" -> "وضع عدم الاتصال: يُنزّل المحرّك مرة واحدة عند أول تشغيل ثم يعمل بلا إنترنت."
                else -> "الوضع الأونلاين."
            }
        }
        root.addView(modeGroup)

        // --- Online model choice (applies to the online mode) ---
        root.addView(sectionLabel("نموذج الأونلاين"))
        root.addView(TextView(this).apply {
            text = "اختر النموذج للوضع الأونلاين: السريع للاستجابة الأقل تأخيرًا، أو الدقيق للنصوص الصعبة."
            textSize = 15f; setPadding(0, 0, 0, 8)
        })
        val modelGroup = RadioGroup(this).apply { orientation = RadioGroup.VERTICAL }
        val liteBtn = RadioButton(this).apply {
            text = "سريع — Gemini Flash Lite (أقل تأخيرًا)"; textSize = 17f; id = 301
        }
        val flashBtn = RadioButton(this).apply {
            text = "دقيق — Gemini 3.6 Flash (أفضل دقّة)"; textSize = 17f; id = 302
        }
        modelGroup.addView(liteBtn)
        modelGroup.addView(flashBtn)
        if (prefs.getString("online_model", "gemini-3.5-flash-lite") == "gemini-3.6-flash")
            flashBtn.isChecked = true else liteBtn.isChecked = true
        modelGroup.setOnCheckedChangeListener { _, id ->
            val m = if (id == 302) "gemini-3.6-flash" else "gemini-3.5-flash-lite"
            prefs.edit().putString("online_model", m).apply()
            status.text = if (m == "gemini-3.6-flash") "النموذج: 3.6 Flash (دقيق)." else "النموذج: Flash Lite (سريع)."
        }
        root.addView(modelGroup)

        // Use cellular data for the server even when joined to the glasses' Wi-Fi
        // (which has no internet). Fixes "online won't work while on glasses Wi-Fi".
        root.addView(CheckBox(this).apply {
            text = "استخدم بيانات الجوّال للاتصال بالخادم (لو النظارة على واي‑فاي بلا إنترنت)"
            textSize = 16f
            isChecked = prefs.getBoolean("prefer_cellular", false)
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            lp.topMargin = 12; layoutParams = lp
            setOnCheckedChangeListener { _, checked ->
                prefs.edit().putBoolean("prefer_cellular", checked).apply()
                NetManager.setPreferCellular(this@LiveReaderActivity, checked)
                status.text = if (checked) "سيتصل بالخادم عبر بيانات الجوّال." else "اتصال عادي."
            }
        })

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
                "وضع الطلب: اضغط الزر العائم فوق تطبيق eSight، أو زر الإشعار."
            else "بث مباشر مفعّل."
        }
        root.addView(trigGroup)

        // --- Pre-download the offline model (with precise progress) ---
        root.addView(sectionLabel("نموذج عدم الاتصال"))
        root.addView(TextView(this).apply {
            text = "نزّل نموذج PaddleOCR العربي قبل البدء ليعمل بلا إنترنت. اختر «بدون إنترنت» أعلاه ثم نزّل."
            textSize = 15f; setPadding(0, 8, 0, 8)
        })
        val dlStatus = TextView(this).apply { text = ""; textSize = 16f; setPadding(0, 4, 0, 8) }
        root.addView(dlStatus)
        root.addView(bigButton("تنزيل النموذج (بتقدّم)") {
            if (prefs.getString("ocr_mode", "online") != "paddle") {
                dlStatus.text = "اختر «بدون إنترنت» أولًا."; return@bigButton
            }
            dlStatus.text = "بدء التنزيل…"
            lifecycleScope.launch {
                val err = withContext(Dispatchers.IO) {
                    PaddleOcr(this@LiveReaderActivity).downloadModels { p ->
                        runOnUiThread { dlStatus.text = "تنزيل النموذج: $p%" }
                    }
                }
                dlStatus.text = if (err == null) "اكتمل التنزيل ✅ — النموذج جاهز للعمل بلا إنترنت."
                else "تعذّر التنزيل: $err — تأكّد من الإنترنت وأعد المحاولة."
            }
        })

        // Floating button lets on-demand work WITHOUT leaving the eSight app.
        root.addView(TextView(this).apply {
            text = "الزر العائم: يظهر زر كبير فوق تطبيق eSight تضغطه للقراءة/الوصف " +
                "دون الخروج من التطبيق. يتطلب إذن «العرض فوق التطبيقات» مرة واحدة."
            textSize = 15f; setPadding(0, 8, 0, 8)
        })
        root.addView(bigButton("تفعيل الزر العائم (فوق التطبيقات)") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")))
            } else {
                status.text = "الزر العائم مُفعّل — اختر «عند الطلب» ثم «بدء القراءة»."
            }
        })

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

        // Stop reading automatically when the view goes blank (you looked away).
        root.addView(CheckBox(this).apply {
            text = "إيقاف القراءة تلقائيًا عند النظر بعيدًا (شاشة فارغة)"
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

        // --- Diagnostics ---
        root.addView(sectionLabel("التشخيص"))
        root.addView(TextView(this).apply {
            text = "يسجّل التطبيق كل خطوة (التقاط، كشف، اتصال، قراءة، أخطاء) في ملف. " +
                "شغّل القراءة ثم شارك الملف معي لتحديد أي مشكلة بدقّة."
            textSize = 15f; setPadding(0, 8, 0, 8)
        })
        root.addView(bigButton("مشاركة ملف التشخيص") {
            try {
                val f = DiagLog.file(this)
                if (!f.exists() || f.length() == 0L) { status.text = "لا يوجد سجل بعد — شغّل القراءة أولًا."; return@bigButton }
                val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_SUBJECT, "نور live-reader diagnostic")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(send, "مشاركة ملف التشخيص"))
            } catch (e: Exception) {
                status.text = "تعذّرت المشاركة: ${e.message}"
            }
        })
        root.addView(bigButton("مسح ملف التشخيص") {
            DiagLog.clear(this)
            status.text = "مُسح ملف التشخيص."
        })

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
