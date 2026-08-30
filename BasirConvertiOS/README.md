# Basir Convert iOS 3.0.0 (11)

تطبيق iPhone أصلي للتحويل والترجمة عبر خادم Basir الخاص، مع VoiceOver، نقل خلفي
قابل للاستئناف، حفظ المهام، والتحقق من ملف Word قبل اعتماده.

## عقد الخادم

يعتمد التطبيق على `api_contract_v3` فقط. لا يرتبط بأسماء الخوارزميات الداخلية
أو رقم ترقيع للخادم. يرسل اختيار الصفحات بعد تحويل الأرقام العربية والفارسية
والفواصل والشرطات إلى صيغة سلكية موحدة.

## البناء المحلي

المتطلبات: macOS، Xcode، وXcodeGen.

```bash
cd BasirConvertiOS
python3 tools/verify_project.py . --source-only
xcodegen generate --spec project.yml
scripts/verify_project.sh
xcodebuild test -project BasirConvert.xcodeproj -scheme BasirConvert \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

لبناء IPA غير موقع، اضبط `BASIR_SERVER_URL` و`BASIR_CLIENT_TOKEN` ثم شغّل:

```bash
scripts/build_unsigned_ipa.sh
```

الناتج هو `dist/Basir_v3.0.0_unsigned.ipa` مع ملف SHA-256 مرافق.

## الأمان

- لا يحتوي المصدر على مفتاح مزود ذكاء اصطناعي أو نقطة اتصال مباشرة به.
- عنوان الخادم يجب أن يكون HTTPS.
- رمز العميل يُحقن وقت البناء ولا يُكتب في سجل البناء.
- النتيجة لا تُحفظ قبل التحقق من DOCX وبيان الجودة وبصمة SHA-256.
- IPA الناتج غير موقع عمدًا؛ التوقيع والتوزيع خطوة لاحقة مستقلة.

