# قهوتي — Coffee Access

تطبيق iPhone مستقل ومتاح بالكامل لماكينات القهوة الأوتوماتيكية من De'Longhi، صُمّم أولًا لمستخدمي VoiceOver، وموجّه أساسًا إلى **Eletta Ultra (ECAM 472.85.MB)**.

> تطبيق غير رسمي وغير تابع لشركة De'Longhi. الرسومات والتصميم أصلية.

## المميزات
- **24 مشروبًا** في أربعة أقسام: قهوة، بالحليب، باردة، أخرى. لكل مشروب رسم أصلي يُظهر طبقاته في الكوب.
- **التخصيص:** كمية القهوة والماء والحليب، والقوة، والحرارة، والحليب أولًا. كل إعداد عنصر VoiceOver واحد تغيّره بالسحب لأعلى ولأسفل، والأحجام السريعة في قائمة الإجراءات.
- **أربعة ملفات شخصية:** لكل ملف مفضلته وإعداداته الخاصة لكل مشروب، وسجل خاص به.
- **شاشة التحضير:** تعلن المراحل والنسبة وانتهاء المشروب، مع اهتزاز. زر الإيقاف متاح دائمًا.
- **التنبيهات:** تُعلن فور ظهورها (الماء، البن، الحاوية، الصينية، الترسبات، الفلتر، إبريق الحليب)، ولكل تنبيه دليل صيانة خطوة بخطوة.
- **7 أدلة صيانة:** تنقل التركيز إلى الخطوة الجديدة، ويمكن عرض كل الخطوات دفعة واحدة.
- **Siri والاختصارات:** «حضّر كابتشينو في قهوتي»، و«حضّر مشروبي المفضل»، و«حالة الماكينة»، و«شغّل الماكينة».
- **فحص الماكينة:** يبحث عن الماكينة عبر البلوتوث ويفحص خدماتها ويختبر البروتوكول، ثم يعطي تقريرًا قابلًا للمشاركة.
- **وضع التجربة:** ماكينة افتراضية كاملة لتعلّم التطبيق.
- **العرض:** عربي وإنجليزي، وتكبير الخط حتى أكبر الأحجام، وتباين WCAG AA مع «زيادة التباين»، واحترام «تقليل الحركة».

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

- **التحقق قبل البناء:** `python3 Scripts/validate_strings.py` و`python3 Scripts/check_contrast.py`.
- **GitHub Actions:** يبني التطبيق ويشغّل الاختبارات على المحاكي، ثم يُخرج ملف IPA غير موقّع.
- **Codemagic:** يُخرج ملف IPA غير موقّع عند كل دفع إلى `main` أو `claude/**`.

## English summary
Coffee Access is an independent, VoiceOver-first iPhone app for De'Longhi bean-to-cup machines, aimed at the Eletta Ultra.
- **Drinks:** browse 24 drinks and customize every setting with single adjustable controls.
- **Profiles:** keep favorites and personal defaults per profile.
- **Brewing:** follow brewing with spoken progress and haptics.
- **Care:** hear machine alerts and use step-by-step maintenance guides.
- **Siri:** use Siri shortcuts.
- **Machine check:** run a Bluetooth check that produces a shareable report.

The app talks to the machine with the community-documented ECAM Bluetooth protocol. Unit tests pin it against packets captured from real machines.
