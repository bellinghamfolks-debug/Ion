package com.bellinghamfolks.docconverter

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var status: TextView
    private var selectedPdf: Uri? = null
    private var selectedName: String = "document.pdf"
    private var pendingDocx: ByteArray? = null
    private val model = "gemini-3.6-flash"

    private val pickPdf = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            selectedPdf = uri
            selectedName = queryName(uri)
            status.text = "تم اختيار: $selectedName"
        }
    }

    private val saveDocx = registerForActivityResult(
        ActivityResultContracts.CreateDocument(
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    ) { uri ->
        val data = pendingDocx
        if (uri != null && data != null) {
            contentResolver.openOutputStream(uri)?.use { it.write(data) }
            status.text = "تم حفظ ملف الوورد ✅"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 96, 48, 48)
            layoutDirection = ViewGroup.LAYOUT_DIRECTION_RTL
        }
        val title = TextView(this).apply { text = "محول المستندات"; textSize = 26f; gravity = Gravity.CENTER }
        status = TextView(this).apply {
            text = "اختر ملف PDF لتحويله إلى Word."
            textSize = 18f; gravity = Gravity.CENTER; setPadding(0, 32, 0, 32)
        }
        root.addView(title)
        root.addView(status)
        root.addView(button("اختيار ملف PDF") { pickPdf.launch(arrayOf("application/pdf")) })
        root.addView(button("بدء التحويل") { startConvert() })
        root.addView(button("القارئ اللحظي للنظارة") {
            startActivity(Intent(this, LiveReaderActivity::class.java))
        })
        setContentView(ScrollView(this).apply { addView(root) })
        handleIncoming(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncoming(intent)
    }

    private fun handleIncoming(intent: Intent?) {
        @Suppress("DEPRECATION")
        val uri: Uri? = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            else -> null
        }
        if (uri != null) {
            selectedPdf = uri
            selectedName = queryName(uri)
            status.text = "تم استقبال: $selectedName"
        }
    }

    private fun startConvert() {
        val uri = selectedPdf ?: run { status.text = "اختر ملف PDF أولًا."; return }
        status.text = "جارٍ رفع الملف…"
        lifecycleScope.launch {
            try {
                val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                val jobId = ConvertApi.createJob(bytes, selectedName, model)
                status.text = "بدأ التحويل على الخادم…"
                while (true) {
                    delay(2500)
                    val s = ConvertApi.status(jobId)
                    when (s.status) {
                        "processing", "key_required" -> {
                            status.text = "قيد المعالجة: ${s.done}/${s.total}"
                            continue
                        }
                        "done", "partial" -> {
                            pendingDocx = ConvertApi.downloadDocx(jobId)
                            status.text = "اكتمل ✅ اختر مكان الحفظ."
                            saveDocx.launch("${selectedName.substringBeforeLast('.')}.docx")
                        }
                        else -> status.text = "فشل التحويل."
                    }
                    break
                }
            } catch (e: Exception) {
                status.text = "خطأ: ${e.message}"
            }
        }
    }

    private fun button(text: String, onClick: () -> Unit): Button = Button(this).apply {
        this.text = text
        textSize = 20f
        val lp = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        lp.topMargin = 28
        layoutParams = lp
        setOnClickListener { onClick() }
    }

    private fun queryName(uri: Uri): String {
        var name = "document.pdf"
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && c.moveToFirst()) name = c.getString(idx) ?: name
        }
        return name
    }
}
