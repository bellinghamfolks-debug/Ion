# قهوتي — Coffee Access

تطبيق iPhone مستقل ومتاح بالكامل لماكينات القهوة الأوتوماتيكية من De'Longhi، صُمّم أولًا لمستخدمي VoiceOver، وموجّه أساسًا إلى **Eletta Ultra (ECAM 472.85.MB)**.

> تطبيق غير رسمي وغير تابع لشركة De'Longhi. الرسومات والتصميم أصلية.

## المميزات
- **القائمة كاملة:** 47 مشروبًا في قوائم الماكينة الخمس: قهوة ساخنة (14)، بالحليب (15)، قهوة باردة (6)، حليب بارد (8)، شاي وماء (4). تشمل الكولد برو والأباريق والقهوة المقطّرة والشاي بدرجات حرارته. مع خيار كوب السفر تتجاوز الوصفات 50.
- **سبع مجموعات:** مقترحة الآن حسب الوقت، قوية، ناعمة، بالحليب، باردة، اكتشف العالم، للطريق.
- **التخصيص:** كمية القهوة والماء والحليب، والقوة (5)، والحرارة (3)، والحليب أولًا، وحجم كوب السفر. كل إعداد عنصر VoiceOver واحد يُغيَّر بالسحب لأعلى ولأسفل.
- **Bean Adapt:** حتى ستة ملفات للبن تضبط القوة والحرارة وتقترح درجة الطحن.
- **وصفاتي:** أنشئ مشروبًا باسمك من أي مشروب، ورتّب المفضلة، واستخدم وضع الضيف. أربعة ملفات شخصية.
- **إعدادات الماكينة دون شاشتها:** قساوة الماء، والإطفاء التلقائي، وتوفير الطاقة، وإضاءة الكوب، والأصوات، وحرارة الماء، والساعة، ووضع الاستعداد، واستيراد أسماء الملفات.
- **الإحصائيات:** رسم بياني لسبعة أيام يُسمع كرسم صوتي، وعدّادات الماكينة نفسها.
- **التحضير:** إعلانات للمراحل والنسبة، وإشعار «مشروبك جاهز» والهاتف مقفل، وتنبيهات الماكينة فور ظهورها.
- **9 أدلة عناية خطوة بخطوة:** مع تذكيرات اختيارية، وصفحة «حل المشكلات».
- **قراءة شاشة الماكينة بالكاميرا:** على الجهاز نفسه، دون رفع أي صورة.
- **Siri والاختصارات:** لكل المشروبات، مع القوة والكمية وكوب السفر.
- **فحص الماكينة:** يختبر بروتوكول البلوتوث ويُخرج تقريرًا قابلًا للمشاركة.
- **وضع التجربة:** ماكينة افتراضية كاملة.
- **العرض:** عربي وإنجليزي، وأكبر أحجام الخط، وتباين WCAG AA، و«تقليل الحركة».

## الاتصال بالماكينة
- يستخدم التطبيق بروتوكول ECAM عبر البلوتوث كما وثّقه مجتمع المصادر المفتوحة: [barista](https://github.com/asaf5767/barista) بترخيص MIT، و[home_assistant_delonghi_primadonna](https://github.com/Arbuzov/home_assistant_delonghi_primadonna) بترخيص Apache 2.0.
- تختبر الوحدات المشفّر والمحلّل بايتًا بايتًا على حزم مسجّلة من ماكينات حقيقية.
- لم يتأكد أحد بعد أن Eletta Ultra تستخدم هذا البروتوكول؛ أداة «فحص الماكينة» هي التي تحسم ذلك.

## البناء
```bash
brew install xcodegen
xcodegen generate
open CoffeeAccess.xcodeproj
```

- **التحقق قبل البناء:** `python3 Scripts/validate_strings.py`، و`python3 Scripts/check_contrast.py`، و`python3 Scripts/generate_intents.py --check`.
- **GitHub Actions:** يبني التطبيق ويشغّل الاختبارات على المحاكي، ثم يُخرج ملف IPA غير موقّع.
- **Codemagic:** يُخرج ملف IPA غير موقّع عند كل دفع إلى `main` أو `claude/**`.

## English summary
Coffee Access is an independent, VoiceOver-first iPhone app for De'Longhi bean-to-cup machines, aimed at the Eletta Ultra.
- **Drinks:** browse all 47 drinks in the machine's five menus and seven collections, with travel-mug sizes, and customize every setting with single adjustable controls.
- **Bean Adapt and recipes:** keep bean profiles, create your own recipes and use guest mode.
- **Machine settings and counters:** change the machine's settings and read its counters over Bluetooth.
- **Read the screen:** read the machine's display aloud with the camera.
- **Profiles:** keep favorites and personal defaults per profile.
- **Brewing:** follow brewing with spoken progress and haptics.
- **Care:** hear machine alerts and use step-by-step maintenance guides.
- **Siri:** use Siri shortcuts.
- **Machine check:** run a Bluetooth check that produces a shareable report.

The app talks to the machine with the community-documented ECAM Bluetooth protocol. Unit tests pin it against packets captured from real machines.
