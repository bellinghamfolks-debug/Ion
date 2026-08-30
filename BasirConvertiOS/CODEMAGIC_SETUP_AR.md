# إعداد Codemagic لـBasir iOS 3.0

أنشئ مجموعة متغيرات مشفرة باسم `basir_secrets` وأضف إليها:

- `BASIR_CLIENT_TOKEN`: رمز العميل المطابق لسر الخادم.

عنوان الخادم موجود كمتغير غير سري في `codemagic.yaml`. عند كل Push إلى الفرع
`basir-ios-v2.3.0-codemagic` يُبنى المصدر الموجود مباشرة في `BasirConvertiOS`،
وتعمل اختبارات الوحدة، ثم يُنتج:

- `Basir_v3.0.0_unsigned.ipa`
- `Basir_v3.0.0_unsigned.ipa.sha256`

لا يحتاج المسار إلى أرشيف مصدر أو أجزاء Base64 أو أي سكربت ترقيع.

