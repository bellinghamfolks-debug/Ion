#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
legal_path = root / "BasirConvert" / "Views" / "InstitutionLegalScreens.swift"
settings_path = root / "BasirConvert" / "Views" / "SettingsView.swift"

for path in (legal_path, settings_path):
    if not path.is_file():
        raise SystemExit(f"R19 legal merge missing required source: {path}")

legal = legal_path.read_text(encoding="utf-8")
settings = settings_path.read_text(encoding="utf-8")

# The Usage Policy is substantively part of the Terms of Use. Keep its clauses
# as internal content, but expose only one Terms document plus a separate Privacy
# Policy. This removes duplicate legal destinations from the UI.
legal = legal.replace(
    "enum InstitutionLegalDocumentKind {\n    case terms\n    case usagePolicy\n}",
    "enum InstitutionLegalDocumentKind {\n    case terms\n    case privacyPolicy\n}",
)
legal = legal.replace(
    'case .usagePolicy: return isArabic ? "سياسة الاستخدام" : "Usage Policy"',
    'case .privacyPolicy: return isArabic ? "سياسة الخصوصية" : "Privacy Policy"',
)

old_intro = '''        case .usagePolicy:
            return isArabic
                ? "تهدف هذه السياسة إلى حماية المستخدمين والخدمة والغير، وتحدد الاستخدامات المسموح بها والمحظورة. تسري على جميع وظائف بصير، بما في ذلك تحويل المستندات وترجمتها وقراءتها وتحليل المحتوى ووصف العناصر البصرية وأي أدوات تضاف لاحقًا."
                : "This Policy protects users, the service, and third parties by defining permitted and prohibited uses. It applies to all Basir features, including document conversion, translation, reading, content analysis, visual description, and future tools."
'''
new_intro = '''        case .privacyPolicy:
            return isArabic
                ? "توضح سياسة الخصوصية كيفية تعامل بصير مع الملفات والبيانات والمعلومات التقنية اللازمة لتقديم الخدمة، وما الخيارات والضمانات المرتبطة بها. وهي مستقلة عن شروط الاستخدام."
                : "This Privacy Policy explains how Basir handles files, data, and technical information needed to provide the service, together with the related choices and safeguards. It is separate from the Terms of Use."
'''
if old_intro in legal:
    legal = legal.replace(old_intro, new_intro, 1)
elif "case .privacyPolicy:" not in legal:
    raise SystemExit("R19 privacy introduction anchor not found")

old_clauses_switch = '''        case .terms: return termsClauses
        case .usagePolicy: return usageClauses
'''
new_clauses_switch = '''        case .terms:
            return termsClauses + usageClauses.map { clause in
                Clause(
                    id: clause.id + 100,
                    titleAR: clause.titleAR,
                    titleEN: clause.titleEN,
                    bodyAR: clause.bodyAR,
                    bodyEN: clause.bodyEN
                )
            }
        case .privacyPolicy: return privacyClauses
'''
if old_clauses_switch in legal:
    legal = legal.replace(old_clauses_switch, new_clauses_switch, 1)
elif "case .privacyPolicy: return privacyClauses" not in legal:
    raise SystemExit("R19 legal clauses switch anchor not found")

privacy_clauses = r'''
    private var privacyClauses: [Clause] {
        [
            Clause(id: 201,
                   titleAR: "1. نطاق هذه السياسة",
                   titleEN: "1. Scope of This Policy",
                   bodyAR: "تسري هذه السياسة على البيانات التي تعالج عند استخدام تطبيق وخدمات بصير، بما في ذلك الملفات التي تختار إرسالها للتحويل أو القراءة أو الترجمة أو الوصف، والمعلومات التقنية اللازمة لتنفيذ المهمة وتشغيل الخدمة بأمان.",
                   bodyEN: "This Policy applies to data processed when you use the Basir application and services, including files you choose to submit for conversion, reading, translation, or description, and technical information needed to perform the task and operate the service securely."),
            Clause(id: 202,
                   titleAR: "2. البيانات التي تقدمها",
                   titleEN: "2. Data You Provide",
                   bodyAR: "قد تتضمن البيانات الملفات والنصوص والصور والمستندات وخيارات التحويل أو الترجمة وأي معلومات ترسلها طوعًا عبر وظائف التطبيق أو قنوات الدعم. لا يطلب منك بصير إضافة بيانات شخصية إلى المستند لمجرد استخدام الخدمة.",
                   bodyEN: "Data may include files, text, images, documents, conversion or translation choices, and information you voluntarily submit through app features or support channels. Basir does not require you to add personal information to a document merely to use the service."),
            Clause(id: 203,
                   titleAR: "3. البيانات التقنية والتشغيلية",
                   titleEN: "3. Technical and Operational Data",
                   bodyAR: "قد تعالج معلومات تقنية لازمة لتشغيل الخدمة وتشخيص الأعطال وحماية المهام، مثل إصدار التطبيق ونظام التشغيل وحالة المهمة ومعرفات تشغيلية غير مخصصة لإظهار محتوى الملف للمستخدمين الآخرين وسجلات أخطاء محدودة عند الحاجة.",
                   bodyEN: "Technical information may be processed as needed to operate the service, diagnose failures, and protect tasks, such as app version, operating system, task status, operational identifiers not intended to expose file content to other users, and limited error logs where needed."),
            Clause(id: 204,
                   titleAR: "4. أغراض المعالجة",
                   titleEN: "4. Purposes of Processing",
                   bodyAR: "تستخدم البيانات لتنفيذ الوظيفة التي طلبتها، إنشاء النتيجة، المحافظة على استمرارية المهمة، التحقق من سلامة التحويل، اكتشاف الأعطال وإصلاحها، منع إساءة الاستخدام، حماية الخدمة، وتقديم الدعم عند طلبه. لا تستخدم الملفات لغرض مستقل لا يرتبط بتقديم الخدمة إلا إذا كان هناك أساس واضح ومشروع لذلك.",
                   bodyEN: "Data is used to perform the feature you requested, create the result, maintain task continuity, verify conversion integrity, detect and fix failures, prevent abuse, protect the service, and provide support when requested. Files are not used for an unrelated independent purpose unless there is a clear lawful basis for doing so."),
            Clause(id: 205,
                   titleAR: "5. المعالجة عبر مزودي الخدمة",
                   titleEN: "5. Service Providers",
                   bodyAR: "قد تعتمد بعض وظائف بصير على خدمات بنية تحتية أو معالجة سحابية أو ذكاء اصطناعي تعمل لحساب تقديم الخدمة. يرسل إليها فقط ما يلزم لتنفيذ المهمة وفق إعدادات الوظيفة المستخدمة، وتخضع المعالجة للضوابط التقنية والتعاقدية المطبقة على تشغيل الخدمة.",
                   bodyEN: "Some Basir features may rely on infrastructure, cloud-processing, or AI service providers used to deliver the service. Only information needed to perform the selected task is sent as required by that feature, subject to the technical and contractual controls applicable to service operation."),
            Clause(id: 206,
                   titleAR: "6. الاحتفاظ والحذف",
                   titleEN: "6. Retention and Deletion",
                   bodyAR: "تحتفظ الخدمة بالملفات والنتائج وبيانات المهمة للمدة اللازمة لإكمال المعالجة والاستئناف والتحقق التشغيلي، وقد تزال البيانات المؤقتة بعد انتهاء الحاجة إليها وفق إعدادات التشغيل ومتطلبات الأمان. لا ينبغي استخدام بصير كخدمة أرشفة دائمة للنسخة الأصلية الوحيدة من ملفاتك.",
                   bodyEN: "The service retains files, results, and task data for as long as needed to complete processing, resume work, and perform operational verification. Temporary data may be removed when no longer needed according to operational settings and security requirements. Basir should not be used as permanent archival storage for the only copy of your files."),
            Clause(id: 207,
                   titleAR: "7. مشاركة البيانات",
                   titleEN: "7. Data Sharing",
                   bodyAR: "لا يكشف بصير محتواك لمستخدمين آخرين لمجرد استخدام الخدمة. قد تتم مشاركة البيانات بالقدر اللازم مع مزودي الخدمة الذين يساعدون في تشغيل الوظائف المطلوبة، أو عند وجود التزام نظامي نافذ، أو لحماية الحقوق والأمن ومنع إساءة الاستخدام وفق ما يسمح به النظام.",
                   bodyEN: "Basir does not disclose your content to other users merely because you use the service. Data may be shared as necessary with service providers supporting requested features, where required by binding law, or to protect rights and security and prevent abuse as permitted by law."),
            Clause(id: 208,
                   titleAR: "8. أمن البيانات",
                   titleEN: "8. Data Security",
                   bodyAR: "تستخدم ضوابط تقنية وتشغيلية تهدف إلى حماية نقل البيانات وتخزينها والوصول إليها وتقليل الوصول غير المصرح به. لا توجد وسيلة إلكترونية خالية من المخاطر بصورة مطلقة، لذلك ينبغي تجنب رفع معلومات لا يلزم إرسالها للمهمة والاحتفاظ بنسخ آمنة من الملفات المهمة.",
                   bodyEN: "Technical and operational safeguards are used to protect data transmission, storage, and access and to reduce unauthorized access. No electronic method is completely risk-free, so avoid submitting information unnecessary for the task and keep secure copies of important files."),
            Clause(id: 209,
                   titleAR: "9. التحكم في المحتوى والنتائج",
                   titleEN: "9. Control of Content and Results",
                   bodyAR: "أنت تختار الملفات التي ترسلها والوظائف التي تطبق عليها. ويمكنك إدارة النسخ الموجودة على جهازك وفق أدوات النظام والتطبيق. إذا وفرت الخدمة لاحقًا أدوات مباشرة للحذف أو إدارة السجل، فتكون تلك الأدوات هي الوسيلة المفضلة لإدارة البيانات المرتبطة بحسابك أو جهازك.",
                   bodyEN: "You choose which files to submit and which features to apply. You can manage copies stored on your device using system and app controls. If direct deletion or history-management tools are provided later, those tools will be the preferred way to manage data associated with your account or device."),
            Clause(id: 210,
                   titleAR: "10. بيانات الآخرين والمحتوى الحساس",
                   titleEN: "10. Other People's Data and Sensitive Content",
                   bodyAR: "قبل إرسال مستند يحتوي على بيانات شخصية أو صحية أو مالية أو مهنية أو حكومية تخص شخصًا آخر، تأكد من أن لديك الصلاحية المناسبة وأن استخدام الخدمة يتفق مع الالتزامات النظامية أو التعاقدية المطبقة عليك.",
                   bodyEN: "Before submitting a document containing another person's personal, health, financial, professional, or government-related information, make sure you have appropriate authority and that use of the service complies with legal or contractual obligations that apply to you."),
            Clause(id: 211,
                   titleAR: "11. الأطفال والقُصّر",
                   titleEN: "11. Children and Minors",
                   bodyAR: "لا يقصد بصير جمع بيانات الأطفال دون حاجة مرتبطة بوظيفة مشروعة. إذا كنت تعالج بيانات قاصر، فيجب أن تكون لديك الصلاحية المناسبة وأن تراعي المتطلبات النظامية الخاصة بحماية القُصّر والبيانات الشخصية.",
                   bodyEN: "Basir is not intended to collect children's data without a legitimate feature-related need. If you process a minor's data, you must have appropriate authority and comply with applicable requirements protecting minors and personal data."),
            Clause(id: 212,
                   titleAR: "12. الاستفسارات وتحديث السياسة",
                   titleEN: "12. Questions and Policy Updates",
                   bodyAR: "يمكن استخدام قنوات الدعم الرسمية المتاحة داخل بصير للاستفسار عن الخصوصية أو الإبلاغ عن مشكلة متعلقة بالبيانات. قد تحدث هذه السياسة عند تغير وظائف الخدمة أو متطلبات الأمان أو الأنظمة، ويظهر تاريخ آخر تحديث داخل التطبيق.",
                   bodyEN: "Official support channels available in Basir may be used for privacy questions or to report a data-related issue. This Policy may be updated when service features, security requirements, or laws change, and the latest revision date is displayed in the app."),
        ]
    }

'''

if "private var privacyClauses: [Clause]" not in legal:
    anchor = "    private var usageClauses: [Clause] {"
    if anchor not in legal:
        raise SystemExit("R19 usage clauses anchor not found")
    legal = legal.replace(anchor, privacy_clauses + anchor, 1)

# Settings now exposes exactly two destinations: Terms of Use and Privacy Policy.
settings = settings.replace(
    'Label(l10n.t("شروط الاستخدام الكاملة", "Full Terms of Use"), systemImage: "doc.text")',
    'Label(l10n.t("شروط الاستخدام", "Terms of Use"), systemImage: "doc.text")',
)
settings = settings.replace(
    'InstitutionLegalDocumentView(kind: .usagePolicy, isArabic: l10n.isArabic)',
    'InstitutionLegalDocumentView(kind: .privacyPolicy, isArabic: l10n.isArabic)',
)
settings = settings.replace(
    'Label(l10n.t("سياسة الاستخدام الكاملة", "Full Usage Policy"), systemImage: "checkmark.shield")',
    'Label(l10n.t("سياسة الخصوصية", "Privacy Policy"), systemImage: "hand.raised.fill")',
)
# Idempotence for any intermediate UI-copy build that already removed "Full".
settings = settings.replace(
    'Label(l10n.t("سياسة الاستخدام", "Usage Policy"), systemImage: "checkmark.shield")',
    'Label(l10n.t("سياسة الخصوصية", "Privacy Policy"), systemImage: "hand.raised.fill")',
)

legal_path.write_text(legal, encoding="utf-8")
settings_path.write_text(settings, encoding="utf-8")

final_legal = legal_path.read_text(encoding="utf-8")
final_settings = settings_path.read_text(encoding="utf-8")
required = (
    (final_legal, "case privacyPolicy"),
    (final_legal, 'case .privacyPolicy: return isArabic ? "سياسة الخصوصية" : "Privacy Policy"'),
    (final_legal, "private var privacyClauses: [Clause]"),
    (final_legal, "return termsClauses + usageClauses.map"),
    (final_settings, "InstitutionLegalDocumentView(kind: .terms"),
    (final_settings, "InstitutionLegalDocumentView(kind: .privacyPolicy"),
    (final_settings, 'l10n.t("شروط الاستخدام", "Terms of Use")'),
    (final_settings, 'l10n.t("سياسة الخصوصية", "Privacy Policy")'),
)
for haystack, needle in required:
    if needle not in haystack:
        raise SystemExit(f"R19 legal/privacy verification missing: {needle}")

for forbidden in (
    "InstitutionLegalDocumentView(kind: .usagePolicy",
    "شروط الاستخدام الكاملة",
    "سياسة الاستخدام الكاملة",
    "Full Terms of Use",
    "Full Usage Policy",
):
    if forbidden in final_settings:
        raise SystemExit(f"R19 stale legal UI text remains: {forbidden}")

print("BASIR_CLIENT_LAYER=R19_TERMS_MERGED_WITH_USAGE_PLUS_PRIVACY")
