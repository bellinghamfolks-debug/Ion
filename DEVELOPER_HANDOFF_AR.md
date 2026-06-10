# تسليم المشروع للمطور

## الملفات الأساسية

- `ios/Basir/Networking/NetworkTransport.swift`: الشبكة والإلغاء وHTTPS.
- `ios/Basir/Networking/GeminiClient.swift`: اتصال Gemini والمخرجات المنظمة ورفع الملفات.
- `ios/Basir/Networking/GeminiPrompts.swift`: جميع أوامر النموذج ومخططات JSON.
- `ios/Basir/Helpers/StructuredDocConverter.swift`: محرك تحويل الصفحة والتحقق والبدائل.
- `ios/Basir/Documents/DocxWriter.swift`: إنشاء Word.
- `ios/Basir/Helpers/ImagePreprocessor.swift`: تصغير الصور بذاكرة محدودة.
- `ios/Basir/Documents/ZipReader.swift`: قراءة DOCX/PPTX بحدود أمان.
- `ios/BasirTests`: اختبارات الانحدار.
- `scripts/verify_project.py`: بوابة الجودة المحلية.

## ممنوعات هندسية

1. لا تعيد تجميع صفحات PDF في طلب واحد كبير.
2. لا تضع نص المستخدم أو المستند داخل System Prompt.
3. لا تستخدم `URLSession.shared` خارج طبقة النقل.
4. لا تستخدم `try!`.
5. لا تحمّل PDF كاملًا في `Data` لرفعه.
6. لا تفك صورة أصلية ضخمة إلى `UIImage` قبل التصغير.
7. لا تنشئ جدولًا اعتمادًا على المسافات فقط.
8. لا تفرض RTL على المقاطع الإنجليزية والرقمية.
9. لا تسمِّ الملف الجزئي مكتملًا.
10. لا تحذف الصفحة عند فشل OCR، بل استخدم البديل المناسب.

## دورة اعتماد أي تعديل جديد

1. تعديل الكود.
2. إضافة اختبار يغطي العيب.
3. تشغيل فاحص المستودع.
4. تشغيل اختبارات Xcode.
5. تحويل ملف الاختبار العلمي.
6. مقارنة Word بالحقيقة الأرضية.
7. اختبار VoiceOver على جهاز حقيقي.
8. عدم الدمج إذا فشل أي بند حرج.
