# تعليمات تسليم الدفعة الرابعة للمطور

## نقطة البداية

هذه الحزمة مصدر كامل وليست Patch فقط. افتحها كمستودع جديد أو طبّق ملف Patch على خط الأساس المبين في تقرير التسليم.

## البناء

```bash
cd ios
brew install xcodegen
xcodegen generate
open Basir.xcodeproj
```

ثم اختر فريق التطوير ومعرفات الحزمة المناسبة للتطبيق والامتداد. التطبيق يستهدف iOS 17 فأحدث.

## الفحص الإلزامي قبل Xcode

من جذر المستودع:

```bash
python3 scripts/verify_project.py
```

لا تتجاوز فشل هذا الأمر ولا تحذف قاعدة للتحايل عليها. أصلح السبب.

## الفحص عبر Xcode

شغّل Scheme باسم `Basir`، ثم:

1. Product > Analyze.
2. Product > Test.
3. Build على محاكي حديث.
4. Archive على Generic iOS Device.

## ملفات محورية

- `ios/Basir/Networking/GeminiClient.swift`: اتصال Gemini المباشر والرفع والمخرجات المنظمة.
- `ios/Basir/Networking/NetworkTransport.swift`: الجلسة الموحدة وحدود الاستجابة وأمان الخادم الوسيط.
- `ios/Basir/Networking/AIResponseValidator.swift`: فحص الاستجابة قبل عرضها.
- `ios/Basir/Helpers/StructuredDocConverter.swift`: التحويل المستقل لكل صفحة.
- `ios/Basir/Helpers/DocumentText.swift`: أنواع الملفات والحدود والاستخراج وOCR.
- `ios/Basir/Helpers/DocumentContextSelector.swift`: اختيار مقاطع المستند للأسئلة.
- `ios/Basir/Documents/ZipReader.swift`: فك DOCX وPPTX مع حدود الأمان.
- `ios/Basir/Camera/LiveSceneGuidanceController.swift`: الكاميرا والوصف المباشر.
- `ios/Basir/Location/LocationService.swift`: الإذن والمهلة والإلغاء.
- `ios/Basir/Speech`: التعرف والقراءة الصوتية.
- `ios/Basir/PrivacyInfo.xcprivacy`: Privacy Manifest.
- `scripts/verify_project.py`: بوابة الجودة المحمولة.

## قواعد لا يجوز التراجع عنها

- لا تضع مفتاح Gemini في URL.
- لا تستخدم `URLSession.shared` خارج طبقة النقل.
- لا تحوّل ملفًا كاملًا إلى Data إذا أمكن رفعه من القرص.
- لا تعالج PDF بالكامل على MainActor.
- لا تسمح بفشل صفحة واحدة أن يحذف الصفحات الأخرى.
- لا تعرض نتيجة غير مكتملة بوصفها مكتملة.
- لا تدمج نص المستند داخل تعليمات النظام.
- لا تحذف حدود ZIP أو الملفات أو الصور أو الاستجابات.
- لا تخزن محتوى المستخدم أو مفتاحه في السجل.
- لا تنشر قبل نجاح CI واختبار جهاز حقيقي.

## الخادم الوسيط

يجب أن يدعم عقد `basir-ai-2026.06-v4`، وأن يعيد إما نصًا مباشرًا أو JSON يحتوي الحقل `answer`. يجب أن يطبق حدوده الخاصة وألا يثق بحقول العميل. يجب أن يحذف الملفات المؤقتة، ويستخدم HTTPS، وألا يسجل محتوى المستند أو الصور أو رموز الدخول.

## ترحيل إعدادات المستخدم

الإصدار يحافظ على مفاتيح الإعدادات الموجودة. لا تغيّر أسماء مفاتيح UserDefaults أو Keychain دون إضافة ترحيل صريح واختبار له.

## خصوصية App Store

راجع App Privacy في App Store Connect وتأكد من مطابقتها للاستخدام الحالي: محتوى المستخدم، الصور أو الفيديو، والموقع الدقيق عند استخدام رسالة المساعدة أو سياق الوصف المباشر. التطبيق لا يستخدم هذه البيانات للتتبع أو الإعلان وفق الشفرة الحالية.
