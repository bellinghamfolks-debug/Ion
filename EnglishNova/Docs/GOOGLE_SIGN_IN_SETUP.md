# إعداد Google Sign-In في EnglishNova

هذا الملف يحدد الجزء البرمجي والجزء الخارجي المطلوبين حتى لا يظهر زر Google في نسخة غير مهيأة.

## 1. Google Cloud / Google Auth Platform

استخدم مشروع Google المخصص لـ EnglishNova، ثم أكمل Branding / Audience حسب نوع حسابات المستخدمين التي ستسمح بها. يجب أن تكون بيانات اسم التطبيق والبريد وسياسة الخصوصية والنطاقات المصرح بها صحيحة قبل النشر العام.

أنشئ OAuth Client ID من نوع **iOS** للحزمة:

`com.englishnova.app`

وسجّل قيمتين للبناء:

- `GOOGLE_IOS_CLIENT_ID`: قيمة iOS client ID وتنتهي عادةً بـ `.apps.googleusercontent.com`.
- `GOOGLE_REVERSED_CLIENT_ID`: مخطط URL المعكوس الموافق لقيمة iOS client ID، مثل `com.googleusercontent.apps.123456-example`.

أنشئ OAuth Client ID من نوع **Web application** لاستخدامه كجمهور للخادم:

- `GOOGLE_SERVER_CLIENT_ID`

لا تستخدم Client Secret داخل تطبيق iOS. الخادم يحتاج معرّف Web client للتحقق من الجمهور، وليس سر OAuth داخل التطبيق.

## 2. GitHub Actions

أضف أسرار المستودع التالية:

- `GOOGLE_IOS_CLIENT_ID`
- `GOOGLE_SERVER_CLIENT_ID`
- `GOOGLE_REVERSED_CLIENT_ID`

مهمة إنشاء IPA ترفض البناء إذا كانت أي قيمة مفقودة أو تبدو كقيمة placeholder. بعدها تمرر القيم إلى Xcode كإعدادات بناء، وتتحقق من Info.plist الناتج داخل `.app` قبل إنشاء IPA.

## 3. Codemagic

أضف المتغيرات الثلاثة نفسها كمتغيرات سرية في بيئة Codemagic. لا تضع القيم داخل `project.yml` أو ملفات Swift.

## 4. Railway

أضف إلى خدمة EnglishNova:

- `GOOGLE_SERVER_CLIENT_ID` بالقيمة نفسها المستخدمة في `GIDServerClientID` داخل التطبيق.
- `JWT_SECRET` عشوائيًا بطول 32 حرفًا على الأقل.
- `DATABASE_URL` من PostgreSQL.

بعد النشر، يجب أن يعرض `/health`:

- `status: ok`
- `db: true`
- `auth.google: true`

## 5. تدفق التحقق

1. تطبيق iOS يفتح GoogleSignIn SDK.
2. Google يعيد ID token.
3. التطبيق يرسل ID token إلى `POST /auth/google`.
4. الخادم يتحقق من مفاتيح Google العامة، والمصدر، والجمهور، والبريد الموثق.
5. بعد نجاح التحقق فقط يصدر الخادم JWT خاصًا بجلسة EnglishNova.

## 6. اختبار الإصدار

لا يكفي أن ينجح Compile. يجب اختبار تسجيل الدخول على جهاز حقيقي أو نسخة موقعة تستطيع إكمال إعادة التوجيه إلى مخطط URL. اختبر كذلك: إلغاء نافذة Google، حسابًا جديدًا، حسابًا موجودًا بالبريد نفسه، تسجيل الخروج، حذف الحساب، ثم مزامنة التقدم واستعادته.

إذا أضيفت لاحقًا صلاحيات Google حساسة أو مقيدة غير بيانات الهوية الأساسية، راجع متطلبات التحقق الخاصة بهذه الصلاحيات قبل نشرها للمستخدمين.
