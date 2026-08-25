import SwiftUI

private struct LegalSection: Identifiable {
    let id = UUID()
    let title: String
    let paragraphs: [String]
}

private struct LegalDocumentView: View {
    let title: String
    let updated: String
    let intro: String
    let sections: [LegalSection]

    var body: some View {
        List {
            Section {
                Text(intro)
                    .font(.subheadline)
                Text(updated)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyView: View {
    var body: some View {
        LegalDocumentView(
            title: L("سياسة الخصوصية"),
            updated: LE("آخر تحديث: 26 أغسطس 2026", "Last updated: August 26, 2026"),
            intro: privacyIntro,
            sections: privacySections
        )
    }

    private var privacyIntro: String {
        if Localizer.shared.isEnglish {
            return "This policy explains what EnglishNova stores, what stays on your device, and what is sent when you use online or AI features."
        }
        return "توضح هذه السياسة ما الذي يحفظه EnglishNova، وما الذي يبقى على جهازك، وما الذي يُرسل عند استخدام الحساب أو الميزات المتصلة بالإنترنت."
    }

    private var privacySections: [LegalSection] {
        if Localizer.shared.isEnglish { return englishPrivacySections }
        return arabicPrivacySections
    }

    private var arabicPrivacySections: [LegalSection] {
        [
            .init(title: "الحساب", paragraphs: [
                "إذا أنشأت حسابًا، يحفظ خادم EnglishNova بريدك الإلكتروني واسم العرض ومعرّف الحساب. كلمة المرور لا تُحفظ كنص قابل للقراءة؛ تُخزّن بصيغة تجزئة آمنة باستخدام bcrypt.",
                "عند تسجيل الدخول باستخدام Google، يرسل التطبيق رمز هوية صادرًا من Google إلى خادم EnglishNova للتحقق من صحة تسجيل الدخول وربطه بحسابك. لا يحفظ EnglishNova كلمة مرور حساب Google، ولا يطلب صلاحيات Google إضافية خارج بيانات الهوية اللازمة لتسجيل الدخول."
            ]),
            .init(title: "تقدّمك في التعلّم", paragraphs: [
                "عند استخدام المزامنة، يرفع التطبيق نسخة من بيانات تعلّمك إلى حسابك. قد تشمل الدروس والنتائج والنقاط والمراجعات والمفردات والإعدادات وسجل التدريب والأخطاء التعليمية وتقارير النطق المبنية على النص الذي تعرّف إليه النظام.",
                "تُستخدم هذه البيانات لاستعادة تقدّمك على أجهزتك ولتخصيص بعض ميزات التعلّم."
            ]),
            .init(title: "الذكاء الاصطناعي", paragraphs: [
                "عند استخدام ميزة تعمل بالذكاء الاصطناعي عبر الإنترنت، يُرسل المحتوى اللازم لتنفيذ طلبك إلى خادم EnglishNova، ثم قد يُرسل إلى Google Gemini لإنشاء الرد.",
                "بحسب الميزة، قد يتضمن الطلب نصك، مستواك، والسياق التعليمي المطلوب. وإذا كنت مسجلًا وتستخدم المزامنة، قد يضيف الخادم ملخصًا محدودًا من ملف تعلّمك، مثل المهارات الأضعف، أخطاء غير محسومة، مؤشرات نطق، عدد مراجعات مستحقة، ونتائج تدريب حديثة.",
                "لا يضع EnglishNova كلمة مرورك أو بريدك الإلكتروني في ملخص التعلّم المرسل إلى نموذج الذكاء الاصطناعي. ولا يرسل التسجيل الصوتي الخام إلى خادم EnglishNova ضمن تدريب النطق والمحادثة الحالي."
            ]),
            .init(title: "الصوت والتعرّف على الكلام", paragraphs: [
                "يستخدم التطبيق خدمات iOS للميكروفون والتعرّف على الكلام عندما تبدأ تدريبًا صوتيًا. طريقة معالجة Apple للصوت تخضع لإعدادات جهازك وسياسات Apple وقد تختلف بحسب اللغة والجهاز والاتصال.",
                "يحفظ EnglishNova النتائج التعليمية المشتقة التي يحتاجها للتدريب، مثل النص المتعرّف إليه والدرجات والكلمات التي تحتاج إلى مراجعة، ولا يرفع ملف التسجيل الصوتي الخام إلى خادمه في المسار الحالي."
            ]),
            .init(title: "بيانات تبقى على جهازك", paragraphs: [
                "صورة الملف الشخصي المختارة داخل التطبيق تبقى على الجهاز ولا تُرفع إلى خادم EnglishNova.",
                "رمز جلسة تسجيل الدخول يُحفظ في Keychain على الجهاز. كما قد تبقى محادثات المدرّب وملفات النسخ المحلية داخل مساحة التطبيق إلى أن تحذفها أو تحذف التطبيق."
            ]),
            .init(title: "بيانات التشغيل", paragraphs: [
                "قد يسجل الخادم أحداثًا فنية محدودة لتشغيل الخدمة وتحسينها، مثل استخدام ميزة تعليمية أو مستوى النشاط ووقت حدوثه. لا تُستخدم هذه الأحداث لبيع بياناتك أو لتقديم إعلانات مخصصة داخل EnglishNova.",
                "قد تمر بيانات الخدمة عبر مزودي الاستضافة والبنية التحتية اللازمين لتشغيل الخادم."
            ]),
            .init(title: "حذف الحساب والبيانات", paragraphs: [
                "يمكنك حذف حسابك من شاشة الحساب. يؤدي ذلك إلى حذف الحساب والتقدّم المرتبط به من خادم EnglishNova وفق السلوك الحالي للخدمة.",
                "حذف الحساب لا يمحو تلقائيًا كل نسخة محلية موجودة على جهازك. لحذف البيانات المحلية بالكامل يمكنك حذف التطبيق وبياناته من الجهاز."
            ]),
            .init(title: "المشاركة والبيع", paragraphs: [
                "لا يبيع EnglishNova بياناتك الشخصية للمعلنين، ولا يشاركها لأغراض الإعلانات السلوكية.",
                "تُشارك البيانات مع خدمات خارجية فقط بالقدر اللازم لتقديم الوظائف التي تستخدمها، مثل Google للتحقق من تسجيل الدخول وGoogle Gemini للميزات التي تختار تشغيلها بالذكاء الاصطناعي، أو خدمات Apple على جهازك للميكروفون والتعرّف على الكلام."
            ]),
            .init(title: "تواصل معنا", paragraphs: [
                "للاستفسار عن الخصوصية أو طلب المساعدة بشأن بياناتك، تواصل عبر البريد ubdallahalrashdee@gmail.com أو حساب X: @abdullahuksu."
            ])
        ]
    }

    private var englishPrivacySections: [LegalSection] {
        [
            .init(title: "Account", paragraphs: [
                "If you create an account, the EnglishNova server stores your email address, display name, and account identifier. Passwords are not stored as readable text; they are hashed using bcrypt.",
                "When you sign in with Google, the app sends a Google ID token to the EnglishNova server so the server can verify the sign-in and connect it to your account. EnglishNova does not store your Google password or request additional Google permissions beyond the identity data needed for sign-in."
            ]),
            .init(title: "Learning progress", paragraphs: [
                "When sync is used, the app uploads a copy of your learning data to your account. This can include lessons, scores, points, reviews, vocabulary, settings, practice history, learning mistakes, and text-based pronunciation reports.",
                "This data is used to restore progress across devices and personalize learning features."
            ]),
            .init(title: "Artificial intelligence", paragraphs: [
                "When you use an online AI feature, the content needed to fulfill the request is sent to the EnglishNova server and may then be sent to Google Gemini to generate a response.",
                "Depending on the feature, this may include your text, level, and relevant learning context. If you are signed in and syncing, the server may add a limited learning summary such as weaker skills, unresolved learning mistakes, pronunciation indicators, due-review counts, and recent practice results.",
                "EnglishNova does not include your password or email address in the learning summary sent to the AI model. Current speech practice does not upload your raw audio recording to the EnglishNova server."
            ]),
            .init(title: "Speech recognition", paragraphs: [
                "The app uses iOS microphone and speech-recognition services when you start voice practice. Apple's processing depends on your device, language, connectivity, settings, and Apple policies.",
                "EnglishNova stores educational results it needs, such as recognized text and scores, rather than uploading the raw audio file in the current flow."
            ]),
            .init(title: "Data on your device", paragraphs: [
                "Your in-app profile photo remains on your device. The sign-in session token is stored in Keychain. Tutor history and local backup files may also remain in the app's local storage until removed."
            ]),
            .init(title: "Operational data", paragraphs: [
                "The server may record limited technical events needed to operate and improve the service, such as use of a learning feature, level, and event time. EnglishNova does not sell this data to advertisers or use it for behavioral advertising.",
                "Service data may pass through hosting and infrastructure providers required to operate the server."
            ]),
            .init(title: "Account deletion", paragraphs: [
                "You can delete your account from the Account screen. This deletes the account and associated synced progress from the EnglishNova server under the current service behavior.",
                "Deleting the account does not automatically erase every local copy on your device. Deleting the app and its data removes the app's local storage."
            ]),
            .init(title: "Sharing and sale", paragraphs: [
                "EnglishNova does not sell your personal data to advertisers or share it for behavioral advertising.",
                "Data is shared with external services only as needed for features you choose to use, such as Google to verify sign-in, Google Gemini for selected AI features, hosting infrastructure required to operate the service, or Apple services on your device for microphone and speech recognition."
            ]),
            .init(title: "Contact", paragraphs: [
                "For privacy questions or help with your data, contact ubdallahalrashdee@gmail.com or @abdullahuksu on X."
            ])
        ]
    }
}

struct TermsOfUseView: View {
    var body: some View {
        LegalDocumentView(
            title: L("شروط الاستخدام"),
            updated: LE("آخر تحديث: 26 أغسطس 2026", "Last updated: August 26, 2026"),
            intro: termsIntro,
            sections: termsSections
        )
    }

    private var termsIntro: String {
        if Localizer.shared.isEnglish {
            return "By using EnglishNova, you agree to use the app and its online services under these terms."
        }
        return "باستخدام EnglishNova، فإنك توافق على استخدام التطبيق وخدماته المتصلة بالإنترنت وفق هذه الشروط."
    }

    private var termsSections: [LegalSection] {
        if Localizer.shared.isEnglish { return englishTermsSections }
        return arabicTermsSections
    }

    private var arabicTermsSections: [LegalSection] {
        [
            .init(title: "الغرض من التطبيق", paragraphs: [
                "EnglishNova أداة تعليمية لتعلّم الإنجليزية والتدرّب عليها. لا يضمن التطبيق درجة محددة في IELTS أو STEP أو أي اختبار، ولا يضمن نتيجة دراسية أو وظيفية بعينها.",
                "تقديرات المستوى والدرجات داخل التطبيق مؤشرات تعليمية تساعدك على المتابعة، وليست شهادات رسمية لمستوى CEFR."
            ]),
            .init(title: "الذكاء الاصطناعي", paragraphs: [
                "قد تتضمن بعض الميزات ردودًا منشأة بالذكاء الاصطناعي. يمكن أن تكون هذه الردود غير دقيقة أو ناقصة، لذلك لا تعتمد عليها وحدها في قرار مهم أو في معلومة تحتاج إلى تحقق متخصص.",
                "يحاول التطبيق تكييف الرد مع مستواك وأدائك، لكن التخصيص لا يعني أن النموذج يعرف كل ظروفك أو أن تقييمه معصوم من الخطأ."
            ]),
            .init(title: "حسابك", paragraphs: [
                "أنت مسؤول عن المحافظة على سرية بيانات الدخول إلى حسابك وعن استخدام بريد تملكه أو يحق لك استخدامه.",
                "يجوز لك استخدام التطبيق دون حساب في الوظائف المحلية المتاحة. تحتاج بعض ميزات المزامنة والذكاء الاصطناعي عبر الإنترنت إلى تسجيل الدخول."
            ]),
            .init(title: "الاستخدام المقبول", paragraphs: [
                "لا تستخدم الخدمة لمحاولة تعطيل الخادم، تجاوز حدود الاستخدام، الوصول إلى حسابات الآخرين، استخراج مفاتيح أو أسرار الخدمة، أو إرسال محتوى يخالف القانون.",
                "يجوز تقييد الوصول إلى الميزات المتصلة بالإنترنت عند إساءة الاستخدام أو عند الحاجة لحماية الخدمة والمستخدمين."
            ]),
            .init(title: "المحتوى والحقوق", paragraphs: [
                "محتوى EnglishNova التعليمي والواجهة والبرمجيات محمية بالحقوق التي تنطبق عليها. استخدام التطبيق لا ينقل إليك ملكية هذه المواد.",
                "تبقى النصوص التي تكتبها أنت مملوكة لك، مع السماح بمعالجتها بالقدر اللازم لتقديم الوظيفة التي طلبتها وفق سياسة الخصوصية."
            ]),
            .init(title: "توفر الخدمة", paragraphs: [
                "قد تعمل بعض الوظائف دون إنترنت، بينما تعتمد وظائف أخرى على خادم EnglishNova أو خدمات خارجية. قد تتوقف ميزة متصلة مؤقتًا بسبب الصيانة أو الشبكة أو مزود الخدمة.",
                "قد تتغير الميزات أو النماذج أو حدود الاستخدام مع تطوير التطبيق، مع السعي إلى عدم إفساد تقدّمك المحفوظ."
            ]),
            .init(title: "إنهاء الحساب", paragraphs: [
                "يمكنك تسجيل الخروج أو حذف حسابك من داخل التطبيق. حذف الحساب إجراء نهائي بالنسبة إلى البيانات المخزنة على الخادم ولا يمكن الاعتماد على استعادتها بعد الحذف."
            ]),
            .init(title: "التغييرات", paragraphs: [
                "قد تتغير هذه الشروط عند إضافة وظائف جديدة أو تعديل طريقة تشغيل الخدمة. سيُحدّث تاريخ المراجعة عند إجراء تغيير جوهري على النص."
            ]),
            .init(title: "تواصل معنا", paragraphs: [
                "للأسئلة المتعلقة بهذه الشروط، تواصل عبر ubdallahalrashdee@gmail.com أو @abdullahuksu على X."
            ])
        ]
    }

    private var englishTermsSections: [LegalSection] {
        [
            .init(title: "Purpose", paragraphs: [
                "EnglishNova is an educational tool for learning and practicing English. It does not guarantee a particular IELTS, STEP, academic, or employment outcome.",
                "In-app level estimates and scores are learning indicators, not official CEFR certifications."
            ]),
            .init(title: "Artificial intelligence", paragraphs: [
                "Some features may contain AI-generated responses. They can be inaccurate or incomplete and should not be your only source for an important decision or information that requires specialist verification.",
                "Personalization uses available learning data but does not mean the model knows every circumstance or that its evaluation is error-free."
            ]),
            .init(title: "Your account", paragraphs: [
                "You are responsible for protecting your sign-in credentials and using an email address you own or are authorized to use.",
                "Some local features can be used without an account. Online sync and some server AI features require sign-in."
            ]),
            .init(title: "Acceptable use", paragraphs: [
                "Do not use the service to disrupt the server, bypass usage limits, access other accounts, extract service secrets, or send content that violates applicable law.",
                "Online access may be restricted when needed to address abuse or protect the service and its users."
            ]),
            .init(title: "Content and rights", paragraphs: [
                "EnglishNova educational content, interface, and software remain subject to their applicable rights. Using the app does not transfer ownership of those materials to you.",
                "You retain ownership of text you create, while allowing it to be processed as needed to provide the feature you requested under the Privacy Policy."
            ]),
            .init(title: "Availability", paragraphs: [
                "Some features work offline while others depend on the EnglishNova server or third-party services. Connected features may be temporarily unavailable because of maintenance, networking, or provider outages.",
                "Features, models, and usage limits may change as the app evolves."
            ]),
            .init(title: "Account termination", paragraphs: [
                "You can sign out or delete your account in the app. Server-side account deletion is intended to be final, and you should not rely on deleted synced data being recoverable."
            ]),
            .init(title: "Changes", paragraphs: [
                "These terms may be updated when features or service operation change. The revision date will be updated for material changes to this text."
            ]),
            .init(title: "Contact", paragraphs: [
                "Questions about these terms can be sent to ubdallahalrashdee@gmail.com or @abdullahuksu on X."
            ])
        ]
    }
}

struct AccessibilityStatementView: View {
    var body: some View {
        List {
            Section {
                Text(L("EnglishNova مصمم ليعمل مع VoiceOver وأحجام الخط الديناميكية، مع أزرار واضحة وترتيب قراءة منطقي."))
                Text(L("لا تتطلب الأنشطة الأساسية السحب الدقيق أو الاعتماد على اللون وحده. تظهر النتائج والملاحظات كنص يمكن لقارئ الشاشة قراءته."))
            }
            Section(L("الصوت والتدريب")) {
                Text(L("يمكن إدخال كثير من الإجابات بالكتابة أو بالصوت. وتبقى عناصر التحكم في التسجيل والاستماع أزرارًا مستقلة ذات تسميات واضحة."))
                Text(L("تقييم النطق المعروض في التطبيق يعتمد على النص الذي تعرّف إليه النظام والتوقيت والثقة، ولا يقدَّم بوصفه قياسًا مخبريًا لمخارج الحروف."))
            }
            Section(L("المحتوى")) {
                Text(L("النص الإنجليزي يبقى باتجاهه الصحيح داخل الواجهة العربية، وتُعرض الشروحات العربية بشكل مستقل لتقليل اختلاط اتجاه القراءة."))
                Text(L("إذا وجدت عنصرًا يصعب استخدامه مع VoiceOver، يمكنك إبلاغ المطوّر من قسم المساعدة والتواصل في الإعدادات."))
            }
        }
        .navigationTitle(L("بيان الوصولية"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
