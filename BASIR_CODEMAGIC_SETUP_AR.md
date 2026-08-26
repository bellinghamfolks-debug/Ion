# تهيئة بصير للبناء عبر Codemagic

الفرع المخصص: `basir-ios-v2.3.0-codemagic`

## ما هو مهيأ آلياً

- يعيد `codemagic.yaml` تركيب مصدر بصير من `basir_source_parts`.
- يتحقق من SHA-256 للمصدر قبل فك الضغط.
- يثبت XcodeGen عند الحاجة.
- يشغل `scripts/verify_project.sh` قبل البناء.
- يولد مشروع Xcode من `project.yml`.
- يحل Swift Package Dependencies.
- يبني Release مخصصاً لـ iPhone بدون توقيع توزيع.
- ينتج `Basir_v2.3.0_unsigned.ipa` مع ملف SHA-256.
- يتحقق من سلامة ملف IPA قبل نشره ضمن Artifacts.
- عنوان الخادم المستخدم في البناء:
  `https://basir-convert-api-1045442243599.europe-west4.run.app`

## الخطوة اليدوية الوحيدة المطلوبة في Codemagic

لأن مستودع Ion عام، لا يوضع رمز عميل بصير داخل GitHub.

في Codemagic افتح إعدادات التطبيق ثم Environment variables، وأنشئ مجموعة باسم:

`basir_secrets`

داخلها أضف متغيراً باسم:

`BASIR_CLIENT_TOKEN`

ضع قيمته الحقيقية وفعّل خيار Secure / Encrypted.

لا تضع قيمة الرمز في ملف `codemagic.yaml` ولا في أي Commit.

## التشغيل

اختر الفرع:

`basir-ios-v2.3.0-codemagic`

ثم شغّل Workflow:

`basir-ios-unsigned`

أي Push جديد لهذا الفرع مهيأ لتشغيل الـWorkflow تلقائياً بعد ربط المستودع في Codemagic.

## ناتج البناء

تحت Artifacts ستجد:

- `Basir_v2.3.0_unsigned.ipa`
- `Basir_v2.3.0_unsigned.ipa.sha256`

الـIPA غير موقعة للتوزيع، ومخصصة لإعادة التوقيع عبر خدمة التوقيع التي تستخدمها.
