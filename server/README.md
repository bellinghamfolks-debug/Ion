# EnglishNova Server

الخادم المدمج لتطبيق EnglishNova. يوفر الحسابات، تسجيل الدخول بالبريد وكلمة المرور أو Google، مزامنة التقدم، المحتوى المتصل، والتحليلات وخدمات الذكاء الاصطناعي الاختيارية. التخزين الأساسي PostgreSQL.

## نقاط الحساب والمزامنة

- `POST /auth/register` لإنشاء حساب بالبريد وكلمة المرور.
- `POST /auth/login` لتسجيل الدخول بالبريد وكلمة المرور.
- `POST /auth/google` يستقبل Google ID token ويتحقق منه على الخادم قبل إنشاء جلسة EnglishNova.
- `GET /me` و`DELETE /me` لقراءة الحساب أو حذفه.
- `GET /progress` و`PUT /progress` لمزامنة نسخة التقدم.
- `GET /leaderboard` للترتيب، ولا يعيد عناوين البريد.
- `GET /health` يعيد حالة قاعدة البيانات وحالة تهيئة Google دون كشف أي أسرار.

المسارات المحمية تستخدم `Authorization: Bearer <token>`.

## متغيرات الإنتاج الإلزامية

على Railway أو أي استضافة إنتاجية يجب ضبط:

- `DATABASE_URL`: اتصال PostgreSQL.
- `JWT_SECRET`: قيمة عشوائية بطول 32 حرفًا على الأقل. لا توجد قيمة افتراضية غير آمنة في الإنتاج.
- `GOOGLE_SERVER_CLIENT_ID`: معرّف OAuth من نوع Web application، وهو نفسه الجمهور الذي يتحقق منه الخادم عند فحص Google ID token.

متغيرات اختيارية:

- `GEMINI_API_KEY` لميزات الذكاء الاصطناعي المتصلة.
- `ADMIN_TOKEN` لمسارات الإدارة والنشر.

عند اكتشاف بيئة Railway إنتاجية، يرفض الخادم البدء إذا كانت إعدادات قاعدة البيانات أو جلسة JWT أو Google ناقصة. هذا مقصود حتى لا تعمل نسخة إنتاجية بمصادقة نصف مهيأة.

## Railway

1. اجعل Root Directory للخدمة هو `server`.
2. أضف PostgreSQL حتى يوفر Railway المتغير `DATABASE_URL`.
3. أنشئ `JWT_SECRET` عشوائيًا وطويلًا.
4. أضف `GOOGLE_SERVER_CLIENT_ID` المطابق لإعداد تطبيق iOS.
5. انشر الخدمة.
6. يجب أن يعيد `/health` حالة `ok` بعد تجهيز قاعدة البيانات، وأن تكون `auth.google` مساوية `true`.

التطبيق الحالي يستخدم عنوان الإنتاج المدمج في `ServerEndpoint.swift`. عند تغيير نطاق الإنتاج يجب تحديثه قبل إصدار التطبيق بدل الاعتماد على عنوان قديم بصمت.

## التطوير المحلي

```bash
cd server
cp .env.example .env
npm install
npm run check
npm start
```

ملاحظة: Node لا يحمّل `.env` تلقائيًا في هذا المشروع. صدّر المتغيرات في shell أو استخدم أداة إدارة البيئة في بيئة التطوير التي تختارها.

## Google Sign-In

التطبيق لا يرسل معرّف مستخدم عاديًا إلى الخادم. يرسل ID token صادرًا من Google، والخادم يتحقق من التوقيع والمصدر `accounts.google.com` والجمهور `GOOGLE_SERVER_CLIENT_ID` وبريد Google الموثق قبل ربط الحساب. راجع `EnglishNova/Docs/GOOGLE_SIGN_IN_SETUP.md` لإعداد تطبيق iOS وGitHub Actions وCodemagic وRailway.
