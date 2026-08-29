#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
proxy_path = root / "BasirConvert/Services/ProxyClient.swift"
settings_path = root / "BasirConvert/Views/SettingsView.swift"
views_dir = root / "BasirConvert/Views"
legal_path = views_dir / "InstitutionLegalScreens.swift"

for path in (proxy_path, settings_path):
    if not path.is_file():
        raise SystemExit(f"R14 missing required source: {path}")

# ---------------------------------------------------------------------------
# 1) Selected-page quality accounting
# ---------------------------------------------------------------------------
proxy = proxy_path.read_text(encoding="utf-8")

old_source_block = '''        let expectedSourcePages: Int = {
            guard sourceURL.pathExtension.lowercased() == "pdf",
                  let metadata = try? DocumentInspector.inspect(sourceURL, includeChecksum: false),
                  let total = metadata.itemCount, total > 0 else { return 0 }
            return (try? PageSelectionParser.pages(from: options.pageSelection, total: total).count) ?? total
        }()
        logger.record("QUALITY sourcePages=\\(expectedSourcePages) selection=\\(options.pageSelection.isEmpty ? \"all\" : options.pageSelection)")
'''
new_source_block = '''        let sourceDocumentPages: Int = {
            guard sourceURL.pathExtension.lowercased() == "pdf",
                  let metadata = try? DocumentInspector.inspect(sourceURL, includeChecksum: false),
                  let total = metadata.itemCount, total > 0 else { return 0 }
            return total
        }()
        let expectedSourcePages: Int = {
            guard sourceDocumentPages > 0 else { return 0 }
            return (try? PageSelectionParser.pages(from: options.pageSelection, total: sourceDocumentPages).count)
                ?? sourceDocumentPages
        }()
        logger.record("QUALITY sourcePages=\\(sourceDocumentPages) selectedPages=\\(expectedSourcePages) selection=\\(options.pageSelection.isEmpty ? \"all\" : options.pageSelection)")
'''

if old_source_block in proxy:
    proxy = proxy.replace(old_source_block, new_source_block, 1)
elif "let sourceDocumentPages: Int" not in proxy:
    raise SystemExit("R14 selected-page source accounting anchor not found")

# The server quality manifest's source_pages describes the physical PDF, while
# expected_rendered_pages describes the requested selection after blank-page
# skipping. Comparing source_pages to the selected count incorrectly rejects
# valid non-contiguous selections such as pages 1 and 6 of a 16-page PDF.
old_guard = 'Self.integer(qualityMetrics["source_pages"]) == expectedSourcePages,'
new_guard = 'Self.integer(qualityMetrics["source_pages"]) == sourceDocumentPages,'
if old_guard in proxy:
    proxy = proxy.replace(old_guard, new_guard, 1)
elif new_guard not in proxy:
    raise SystemExit("R14 quality-manifest source_pages guard anchor not found")

# Keep the strict selected-page rendered count and exact identity/numbering
# checks. This is not a relaxation: missing, duplicated, renumbered, or extra
# selected pages still fail publication validation.
for required in (
    'Self.integer(qualityMetrics["source_pages"]) == sourceDocumentPages',
    'Self.integer(qualityMetrics["expected_rendered_pages"]) == expectedResultPages',
    'accountingExact == true',
    'numberingExact == true',
):
    if required not in proxy:
        raise SystemExit(f"R14 strict accounting invariant missing: {required}")

proxy_path.write_text(proxy, encoding="utf-8")

# ---------------------------------------------------------------------------
# 2) Full institution-facing Terms of Use + Usage Policy
# ---------------------------------------------------------------------------
legal_source = r'''import SwiftUI

enum InstitutionLegalDocumentKind {
    case terms
    case usagePolicy
}

struct InstitutionLegalDocumentView: View {
    let kind: InstitutionLegalDocumentKind
    let isArabic: Bool

    private struct Clause: Identifiable {
        let id: Int
        let titleAR: String
        let titleEN: String
        let bodyAR: String
        let bodyEN: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                Text(isArabic ? "آخر تحديث: 30 أغسطس 2026" : "Last updated: 30 August 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(introduction)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(clauses) { clause in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isArabic ? clause.titleAR : clause.titleEN)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(isArabic ? clause.bodyAR : clause.bodyEN)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch kind {
        case .terms: return isArabic ? "شروط الاستخدام" : "Terms of Use"
        case .usagePolicy: return isArabic ? "سياسة الاستخدام" : "Usage Policy"
        }
    }

    private var introduction: String {
        switch kind {
        case .terms:
            return isArabic
                ? "تنظم هذه الشروط استخدام تطبيق وخدمات بصير. باستخدامك للخدمة فإنك تقر بقراءة هذه الشروط وفهمها والموافقة عليها. إذا كنت تستخدم بصير نيابة عن جهة أو مؤسسة، فأنت تقر بأن لديك الصلاحية اللازمة لإلزام تلك الجهة بهذه الشروط."
                : "These Terms govern your use of the Basir application and services. By using the service, you acknowledge that you have read, understood, and agreed to these Terms. If you use Basir on behalf of an organization, you represent that you have authority to bind that organization to these Terms."
        case .usagePolicy:
            return isArabic
                ? "تهدف هذه السياسة إلى حماية المستخدمين والخدمة والغير، وتحدد الاستخدامات المسموح بها والمحظورة. تسري على جميع وظائف بصير، بما في ذلك تحويل المستندات وترجمتها وقراءتها وتحليل المحتوى ووصف العناصر البصرية وأي أدوات تضاف لاحقًا."
                : "This Policy protects users, the service, and third parties by defining permitted and prohibited uses. It applies to all Basir features, including document conversion, translation, reading, content analysis, visual description, and future tools."
        }
    }

    private var clauses: [Clause] {
        switch kind {
        case .terms: return termsClauses
        case .usagePolicy: return usageClauses
        }
    }

    private var termsClauses: [Clause] {
        [
            Clause(id: 1,
                   titleAR: "1. نطاق الخدمة",
                   titleEN: "1. Scope of the Service",
                   bodyAR: "يوفر بصير أدوات تقنية لمعالجة المحتوى، مثل تحويل الملفات، استخراج النص، الترجمة، إعادة بناء الجداول، إنشاء أوصاف وصولية للعناصر البصرية، وتنظيم النتائج. قد تختلف الوظائف المتاحة بحسب الإصدار والجهاز والمنطقة وحالة الاتصال وطبيعة الملف.",
                   bodyEN: "Basir provides technical tools for content processing, including file conversion, text extraction, translation, table reconstruction, accessible visual descriptions, and result organization. Available features may vary by version, device, region, connectivity, and file characteristics."),
            Clause(id: 2,
                   titleAR: "2. الأهلية والسلطة",
                   titleEN: "2. Eligibility and Authority",
                   bodyAR: "يجب أن تكون قادرًا قانونًا على قبول هذه الشروط. إذا كنت تتصرف لحساب جهة أخرى، فيجب أن تكون مخولًا باستخدام محتواها وإرساله للمعالجة وقبول هذه الشروط نيابة عنها. لا يجوز استخدام الخدمة بالمخالفة للأنظمة أو القيود النظامية المطبقة عليك.",
                   bodyEN: "You must be legally capable of accepting these Terms. If acting for another party, you must be authorized to use and submit its content for processing and to accept these Terms on its behalf. You may not use the service in violation of laws or restrictions applicable to you."),
            Clause(id: 3,
                   titleAR: "3. مسؤولية المستخدم عن المحتوى",
                   titleEN: "3. User Responsibility for Content",
                   bodyAR: "تبقى مسؤولًا عن الملفات والنصوص والصور والبيانات التي ترفعها أو تعالجها. يجب أن تملك الحقوق أو الأذونات اللازمة، وألا ترفع محتوى سريًا أو شخصيًا أو محميًا لا يحق لك معالجته. لا تنتقل ملكية محتواك إلى بصير لمجرد استخدام الخدمة.",
                   bodyEN: "You remain responsible for files, text, images, and data you upload or process. You must hold all required rights and permissions and must not submit confidential, personal, or protected material you are not authorized to process. Using the service does not transfer ownership of your content to Basir."),
            Clause(id: 4,
                   titleAR: "4. الترخيص التقني المحدود",
                   titleEN: "4. Limited Technical License",
                   bodyAR: "تمنح الجهة المشغلة لبصير إذنًا محدودًا ومؤقتًا بالوصول إلى المحتوى ومعالجته ونقله وتخزينه بالقدر اللازم لتنفيذ المهمة التي طلبتها، وتشغيل الخدمة، ومنع الإساءة، والتحقق من سلامة النتائج. لا يمنح هذا الإذن حقًا مستقلاً في استغلال محتواك لأغراض لا ترتبط بتقديم الخدمة.",
                   bodyEN: "You grant the operator of Basir a limited, temporary permission to access, process, transmit, and store content only as reasonably necessary to perform your requested task, operate the service, prevent abuse, and verify result integrity. This permission does not create an independent right to exploit your content for unrelated purposes."),
            Clause(id: 5,
                   titleAR: "5. المعالجة الآلية ودقة النتائج",
                   titleEN: "5. Automated Processing and Accuracy",
                   bodyAR: "تستخدم الخدمة تقنيات معالجة آلية متقدمة، وقد تنتج أخطاء في القراءة أو الترتيب أو الترجمة أو الجداول أو وصف الصور أو الأرقام أو الأسماء أو التنسيق. صُممت آليات تحقق وتقليل للأخطاء، لكنها لا تضمن التطابق المطلق في كل ملف. يجب مراجعة النتائج قبل الاعتماد عليها، خصوصًا في المستندات القانونية أو الطبية أو المالية أو الأكاديمية أو الرسمية.",
                   bodyEN: "The service uses advanced automated processing and may produce errors in reading order, translation, tables, visual descriptions, numbers, names, or formatting. Validation mechanisms are designed to reduce errors but cannot guarantee perfect fidelity for every file. Review results before relying on them, especially for legal, medical, financial, academic, or official documents."),
            Clause(id: 6,
                   titleAR: "6. عدم تقديم استشارة مهنية",
                   titleEN: "6. No Professional Advice",
                   bodyAR: "النتائج والمعلومات التي يقدمها بصير لأغراض تقنية ومعلوماتية ومساعدة الوصول. لا تُعد بذاتها استشارة قانونية أو طبية أو مالية أو محاسبية أو مهنية، ولا تحل محل مراجعة المختص المؤهل عندما يتطلب الأمر ذلك.",
                   bodyEN: "Basir outputs and information are provided for technical, informational, and accessibility assistance. They are not, by themselves, legal, medical, financial, accounting, or other professional advice and do not replace review by a qualified professional where appropriate."),
            Clause(id: 7,
                   titleAR: "7. الحساب والجهاز وأمن الوصول",
                   titleEN: "7. Account, Device, and Access Security",
                   bodyAR: "أنت مسؤول عن حماية جهازك وبيانات الوصول المرتبطة باستخدامك، وعن الأنشطة التي تتم من خلال جهازك أو حسابك ضمن حدود القانون. يجب إبلاغ الجهة المشغلة عند الاشتباه بوصول غير مصرح به أو إساءة استخدام تؤثر في الخدمة.",
                   bodyEN: "You are responsible for protecting your device and access credentials associated with your use, and for activity conducted through your device or account to the extent permitted by law. Report suspected unauthorized access or abuse that may affect the service."),
            Clause(id: 8,
                   titleAR: "8. الاستخدام المقبول",
                   titleEN: "8. Acceptable Use",
                   bodyAR: "يجب الالتزام بسياسة الاستخدام المرفقة بهذه الشروط. تعد سياسة الاستخدام جزءًا من هذه الشروط، ويجوز تقييد أو إيقاف الاستخدام عند وجود مخالفة جسيمة أو خطر أمني أو نظامي أو ضرر على المستخدمين أو الغير.",
                   bodyEN: "You must comply with the Usage Policy incorporated into these Terms. Access may be restricted or suspended for serious violations, security or legal risk, or harm to users or third parties."),
            Clause(id: 9,
                   titleAR: "9. الملكية الفكرية",
                   titleEN: "9. Intellectual Property",
                   bodyAR: "تظل حقوق بصير في التطبيق والواجهات والبرمجيات والتصميم والعلامات والمحتوى المملوك له محفوظة. لا تمنحك هذه الشروط حق نسخ التطبيق أو تفكيكه أو إعادة بيعه أو إنشاء خدمة منافسة منه إلا بالقدر الذي يسمح به النظام صراحة. تبقى حقوق أصحاب المحتوى الأصلي محفوظة لهم.",
                   bodyEN: "Rights in the Basir application, interfaces, software, design, marks, and owned materials remain reserved. These Terms do not grant permission to copy, reverse engineer, resell, or create a competing service from Basir except where expressly permitted by law. Rights in third-party source content remain with their respective owners."),
            Clause(id: 10,
                   titleAR: "10. الروابط والمحتوى الخارجي",
                   titleEN: "10. External Links and Content",
                   bodyAR: "قد تحتوي المستندات أو النتائج على روابط أو أسماء خدمات أو محتوى تابع لجهات أخرى. وجودها لا يعني اعتمادها أو ضمانها من بصير. يتحمل المستخدم مسؤولية تقييم المواقع أو الملفات أو الخدمات الخارجية قبل استخدامها.",
                   bodyEN: "Documents or outputs may contain links, service names, or third-party content. Their presence does not constitute endorsement or a guarantee by Basir. Users are responsible for evaluating external sites, files, and services before use."),
            Clause(id: 11,
                   titleAR: "11. توافر الخدمة والتغييرات",
                   titleEN: "11. Availability and Changes",
                   bodyAR: "نسعى إلى استمرارية الخدمة، لكن قد تحدث صيانة أو انقطاعات أو حدود سعة أو تغييرات تقنية. يجوز تحديث الوظائف أو تحسينها أو إيقاف وظيفة معينة عند الضرورة. لا يضمن بصير توفرًا متواصلًا دون انقطاع.",
                   bodyEN: "We aim for service continuity, but maintenance, outages, capacity limits, or technical changes may occur. Features may be updated, improved, or discontinued when necessary. Basir does not guarantee uninterrupted availability."),
            Clause(id: 12,
                   titleAR: "12. الحفظ والنسخ الاحتياطي",
                   titleEN: "12. Storage and Backups",
                   bodyAR: "لا ينبغي اعتبار بصير خدمة أرشفة دائمة أو نسخة احتياطية وحيدة. احتفظ بنسخة أصلية من ملفاتك وبالنتائج المهمة في مكان آمن. قد تُحذف الملفات المؤقتة أو النتائج وفق آليات التشغيل أو إعدادات الجهاز أو متطلبات الأمان.",
                   bodyEN: "Basir should not be treated as permanent archival storage or your sole backup. Keep original files and important outputs in a secure location. Temporary files or results may be removed according to operational processes, device settings, or security requirements."),
            Clause(id: 13,
                   titleAR: "13. الرسوم والميزات المدفوعة",
                   titleEN: "13. Fees and Paid Features",
                   bodyAR: "إذا أضيفت ميزات مدفوعة، فتعرض الأسعار والشروط المطبقة قبل الشراء أو الاشتراك. لا ينشأ التزام بالدفع إلا وفق العرض الذي وافق عليه المستخدم وآلية الدفع المتاحة. قد تخضع عمليات الشراء لشروط متجر التطبيقات أو قناة الدفع المستخدمة.",
                   bodyEN: "If paid features are introduced, applicable prices and terms will be presented before purchase or subscription. Payment obligations arise only under the offer accepted by the user and available payment method. Purchases may also be subject to the terms of the relevant app marketplace or payment channel."),
            Clause(id: 14,
                   titleAR: "14. التعليق والإنهاء",
                   titleEN: "14. Suspension and Termination",
                   bodyAR: "يجوز تقييد أو تعليق أو إنهاء الوصول عندما يكون ذلك لازمًا لحماية الخدمة أو المستخدمين أو الغير، أو لمنع إساءة استخدام أو مخالفة نظامية أو أمنية، أو عند الإخلال الجسيم بهذه الشروط. متى كان ذلك مناسبًا، تسعى الجهة المشغلة إلى اتخاذ إجراء متناسب مع طبيعة المخالفة.",
                   bodyEN: "Access may be restricted, suspended, or terminated where necessary to protect the service, users, or third parties; prevent abuse or legal/security violations; or address a material breach of these Terms. Where appropriate, the operator aims to take action proportionate to the nature of the violation."),
            Clause(id: 15,
                   titleAR: "15. حدود المسؤولية",
                   titleEN: "15. Limitation of Liability",
                   bodyAR: "إلى الحد الذي يسمح به النظام، تقدم الخدمة وفق حالتها المتاحة ولا تضمن خلو كل نتيجة من الخطأ. لا تتحمل الجهة المشغلة مسؤولية خسارة تنشأ فقط من اعتماد المستخدم على نتيجة غير مراجعة، أو من محتوى رفعه المستخدم دون حق، أو من أعطال خارجة عن السيطرة المعقولة. لا يستبعد هذا البند أي مسؤولية لا يجوز استبعادها نظامًا.",
                   bodyEN: "To the extent permitted by law, the service is provided as available and no guarantee is made that every output is error-free. The operator is not responsible for loss arising solely from reliance on unreviewed output, unauthorized user-submitted content, or events outside reasonable control. Nothing in this section excludes liability that cannot lawfully be excluded."),
            Clause(id: 16,
                   titleAR: "16. التعويض عن إساءة الاستخدام",
                   titleEN: "16. Responsibility for Misuse",
                   bodyAR: "يتحمل المستخدم، في الحدود التي يسمح بها النظام، المسؤولية عن المطالبات أو الأضرار الناتجة مباشرة عن استخدامه غير المشروع للخدمة أو انتهاكه المتعمد لحقوق الغير أو مخالفته الجوهرية لهذه الشروط.",
                   bodyEN: "To the extent permitted by law, users are responsible for claims or harm directly resulting from their unlawful use of the service, intentional infringement of third-party rights, or material breach of these Terms."),
            Clause(id: 17,
                   titleAR: "17. تحديث الشروط",
                   titleEN: "17. Changes to These Terms",
                   bodyAR: "قد تُحدّث هذه الشروط لتلائم تغييرات الخدمة أو المتطلبات النظامية أو الأمنية. يظهر تاريخ آخر تحديث داخل التطبيق. إذا كان التغيير جوهريًا، يجوز عرض إشعار مناسب قبل استمرار الاستخدام متى كان ذلك ممكنًا أو مطلوبًا.",
                   bodyEN: "These Terms may be updated to reflect service, legal, or security changes. The latest revision date is shown in the app. For material changes, an appropriate notice may be provided before continued use where feasible or required."),
            Clause(id: 18,
                   titleAR: "18. التواصل والشكاوى",
                   titleEN: "18. Contact and Complaints",
                   bodyAR: "يمكن استخدام قنوات الدعم الرسمية المتاحة داخل بصير للإبلاغ عن مشكلة تقنية أو أمنية، طلب مساعدة وصولية، الاعتراض على إجراء متعلق بالاستخدام، أو تقديم استفسار بشأن هذه الشروط. لا ترسل كلمات مرور أو مفاتيح وصول أو معلومات شديدة الحساسية ضمن بلاغات الدعم.",
                   bodyEN: "Use the official support channels available in Basir to report technical or security issues, request accessibility support, challenge an action related to use, or ask about these Terms. Do not send passwords, access keys, or highly sensitive information in support requests."),
            Clause(id: 19,
                   titleAR: "19. القانون الإلزامي وقابلية الفصل",
                   titleEN: "19. Mandatory Law and Severability",
                   bodyAR: "تطبق هذه الشروط مع مراعاة الأنظمة الإلزامية التي لا يجوز الاتفاق على مخالفتها. إذا تعذر تطبيق بند معين، يبقى باقي البنود نافذًا بالقدر الذي يسمح به النظام.",
                   bodyEN: "These Terms operate subject to mandatory laws that cannot be waived by agreement. If any provision is unenforceable, the remaining provisions continue to apply to the extent permitted by law."),
        ]
    }

    private var usageClauses: [Clause] {
        [
            Clause(id: 1,
                   titleAR: "1. الاستخدامات المشروعة",
                   titleEN: "1. Lawful Uses",
                   bodyAR: "يمكن استخدام بصير لأغراض مشروعة مثل الوصول إلى المستندات، الدراسة والبحث، الأعمال الإدارية والمهنية، الترجمة، تنظيم المحتوى، وفهم الملفات والصور. يجب أن تكون لديك صلاحية استخدام المحتوى الذي تعالجه.",
                   bodyEN: "Basir may be used for lawful purposes such as document accessibility, study and research, administrative and professional work, translation, content organization, and understanding files and images. You must be authorized to use the content you process."),
            Clause(id: 2,
                   titleAR: "2. الأنشطة غير القانونية",
                   titleEN: "2. Illegal Activity",
                   bodyAR: "يحظر استخدام الخدمة لتسهيل جريمة أو احتيال أو تزوير أو غسل أموال أو سرقة أو ابتزاز أو تهرب من متطلبات نظامية أو أي نشاط محظور بموجب الأنظمة المطبقة.",
                   bodyEN: "You may not use the service to facilitate crime, fraud, forgery, money laundering, theft, extortion, evasion of legal requirements, or other activity prohibited by applicable law."),
            Clause(id: 3,
                   titleAR: "3. الاحتيال والانتحال والخداع",
                   titleEN: "3. Fraud, Impersonation, and Deception",
                   bodyAR: "يحظر إنشاء أو تعديل مستندات بقصد تضليل الغير بشأن الهوية أو المؤهلات أو الدرجات أو السجلات أو العقود أو الفواتير أو الأدلة، أو انتحال شخص أو جهة، أو استخدام بصير في حملات تصيد أو خداع منظم.",
                   bodyEN: "You may not create or alter documents to deceive others about identity, qualifications, grades, records, contracts, invoices, or evidence; impersonate a person or organization; or use Basir for phishing or organized deception."),
            Clause(id: 4,
                   titleAR: "4. أمن الأنظمة والبرمجيات الضارة",
                   titleEN: "4. System Security and Malware",
                   bodyAR: "يحظر استخدام بصير لإنشاء أو توزيع برمجيات ضارة، سرقة بيانات اعتماد، تجاوز وسائل الحماية، استغلال الثغرات دون تصريح، تعطيل الأنظمة، شن هجمات حجب الخدمة، أو محاولة الوصول غير المصرح به إلى حسابات أو أجهزة أو شبكات.",
                   bodyEN: "You may not use Basir to create or distribute malware, steal credentials, bypass safeguards, exploit vulnerabilities without authorization, disrupt systems, conduct denial-of-service attacks, or gain unauthorized access to accounts, devices, or networks."),
            Clause(id: 5,
                   titleAR: "5. الخصوصية والبيانات الشخصية",
                   titleEN: "5. Privacy and Personal Data",
                   bodyAR: "يحظر جمع أو كشف أو نشر بيانات شخصية أو سرية للغير دون أساس مشروع أو إذن مناسب، بما في ذلك كلمات المرور والبيانات المالية والسجلات الخاصة والعناوين الدقيقة بقصد الإضرار. لا تستخدم الخدمة للمراقبة السرية أو التتبع غير المشروع أو التشهير القائم على بيانات مسربة.",
                   bodyEN: "You may not collect, expose, or publish another person's personal or confidential data without lawful basis or appropriate permission, including passwords, financial data, private records, or precise addresses used to cause harm. Do not use the service for unlawful covert surveillance, tracking, or harassment based on leaked data."),
            Clause(id: 6,
                   titleAR: "6. الاستغلال والإساءة إلى القُصّر",
                   titleEN: "6. Child Exploitation and Abuse",
                   bodyAR: "يحظر أي استخدام يتضمن استغلالًا جنسيًا للقُصّر أو محتوى يصور إساءتهم أو طلبه أو ترويجه أو تسهيل الوصول إليه أو استدراجهم أو تعريضهم لخطر. قد تُتخذ إجراءات فورية عند اكتشاف هذا النوع من الإساءة وفق ما يقتضيه النظام والسلامة.",
                   bodyEN: "Any use involving child sexual exploitation or abuse material, solicitation, promotion, facilitation, grooming, or endangerment of minors is prohibited. Immediate protective action may be taken where such abuse is detected, consistent with law and safety obligations."),
            Clause(id: 7,
                   titleAR: "7. التهديد والتحرش والعنف",
                   titleEN: "7. Threats, Harassment, and Violence",
                   bodyAR: "يحظر استخدام الخدمة لتهديد أشخاص محددين، تنسيق الاعتداء عليهم، التحريض المباشر على العنف، التحرش المستهدف، أو نشر معلومات لتسهيل أذى جسدي حقيقي. لا يشمل ذلك التناول التعليمي أو الإخباري أو الوقائي للمحتوى العنيف بصورة مشروعة.",
                   bodyEN: "You may not use the service to threaten identifiable people, coordinate attacks, directly incite violence, conduct targeted harassment, or publish information intended to facilitate real physical harm. Legitimate educational, news, or prevention-oriented discussion of violence is not prohibited by this clause."),
            Clause(id: 8,
                   titleAR: "8. الإرهاب والتطرف العنيف",
                   titleEN: "8. Terrorism and Violent Extremism",
                   bodyAR: "يحظر استخدام بصير لتقديم دعم تشغيلي أو تجنيد أو تمويل أو دعاية أو تعليمات تهدف إلى تمكين أعمال إرهابية أو جماعات متطرفة عنيفة. يسمح بالاستخدامات المشروعة ذات الطابع البحثي أو الصحفي أو الوقائي أو الحقوقي التي لا تسهل الضرر.",
                   bodyEN: "Basir may not be used to provide operational support, recruitment, financing, propaganda, or instructions intended to enable terrorism or violent extremist groups. Legitimate research, journalism, prevention, or human-rights work that does not facilitate harm remains permitted."),
            Clause(id: 9,
                   titleAR: "9. الأسلحة والمواد الخطرة",
                   titleEN: "9. Weapons and Dangerous Materials",
                   bodyAR: "يحظر استخدام الخدمة لتطوير أو تحسين أسلحة أو متفجرات أو سموم أو عوامل خطرة بقصد الإيذاء أو لتجاوز ضوابط السلامة. يجوز معالجة مواد تعليمية أو تنظيمية أو سلامة عامة عندما لا يكون الغرض تمكين الضرر.",
                   bodyEN: "You may not use the service to develop or improve weapons, explosives, poisons, or dangerous agents for harmful purposes or to bypass safety controls. Educational, regulatory, or public-safety material may be processed where it does not enable harm."),
            Clause(id: 10,
                   titleAR: "10. الملكية الفكرية وحقوق الغير",
                   titleEN: "10. Intellectual Property and Third-Party Rights",
                   bodyAR: "لا تستخدم بصير لنسخ أو توزيع أو إزالة حماية محتوى بما ينتهك حقوق النشر أو العلامات أو الأسرار التجارية أو حقوق قواعد البيانات أو التراخيص. تقع على المستخدم مسؤولية التحقق من حقه في تحويل أو ترجمة أو مشاركة المواد.",
                   bodyEN: "Do not use Basir to copy, distribute, or remove protections from content in violation of copyright, trademark, trade-secret, database, or licensing rights. Users are responsible for confirming their right to convert, translate, or share materials."),
            Clause(id: 11,
                   titleAR: "11. إساءة استخدام الخدمة والموارد",
                   titleEN: "11. Abuse of Service Resources",
                   bodyAR: "يحظر التحايل على حدود الاستخدام أو آليات الحماية، إرسال أحمال آلية مفرطة، إنشاء طلبات متكررة بقصد تعطيل الخدمة، محاولة استخراج أسرار النظام أو مفاتيح الوصول، إعادة بيع الوصول دون تصريح، أو استخدام حسابات متعددة للتحايل على القيود.",
                   bodyEN: "You may not circumvent usage limits or safeguards, send excessive automated load, submit repeated requests intended to disrupt the service, attempt to extract system secrets or access keys, resell access without authorization, or use multiple accounts to evade restrictions."),
            Clause(id: 12,
                   titleAR: "12. القرارات عالية الأثر",
                   titleEN: "12. High-Impact Decisions",
                   bodyAR: "لا يجوز الاعتماد على مخرجات بصير وحدها لاتخاذ قرار نهائي عالي الأثر بشأن توظيف شخص أو فصله أو قبوله التعليمي أو أهليته الائتمانية أو التأمينية أو حصوله على خدمة أساسية أو إجراء قانوني يؤثر في حقوقه. يجب وجود مراجعة بشرية مؤهلة وسياق مناسب عندما تكون النتيجة مؤثرة في حقوق الأفراد.",
                   bodyEN: "Basir outputs must not be the sole basis for a final high-impact decision about employment, termination, educational admission, credit or insurance eligibility, access to essential services, or legal action affecting a person's rights. Qualified human review and appropriate context are required when decisions materially affect individuals."),
            Clause(id: 13,
                   titleAR: "13. الاستخدامات القانونية والطبية والمالية",
                   titleEN: "13. Legal, Medical, and Financial Use",
                   bodyAR: "يجوز استخدام بصير للمساعدة في القراءة والتنظيم والبحث، لكن لا تعتمد على نتيجة آلية غير مراجعة لتشخيص طبي أو وصف علاج أو اتخاذ قرار استثماري أو ائتماني أو تقديم رأي قانوني نهائي. تحقق من المصدر واستعن بمختص مؤهل عندما تستلزم طبيعة المسألة ذلك.",
                   bodyEN: "Basir may assist with reading, organization, and research, but unreviewed automated output must not be treated as a medical diagnosis or treatment prescription, investment or credit decision, or final legal opinion. Verify source material and consult a qualified professional where the matter requires it."),
            Clause(id: 14,
                   titleAR: "14. النزاهة الأكاديمية والمهنية",
                   titleEN: "14. Academic and Professional Integrity",
                   bodyAR: "استخدم بصير بما يتفق مع سياسات جامعتك أو جهة عملك. يحظر تقديم محتوى مولد أو معدل على أنه عمل شخصي أصيل عندما تمنع القواعد ذلك، أو تزوير السجلات الأكاديمية أو المهنية أو نتائج الاختبارات.",
                   bodyEN: "Use Basir consistently with your school or workplace policies. You may not present generated or modified material as original personal work where rules prohibit it, or falsify academic or professional records or examination results."),
            Clause(id: 15,
                   titleAR: "15. حماية الوصول وذوي الإعاقة",
                   titleEN: "15. Accessibility and Disability Safety",
                   bodyAR: "لا تستخدم وظائف الوصول أو الوصف البصري بطريقة تعرض شخصًا للخطر. في البيئات الحرجة مثل الطرق أو الآلات أو الأدوية أو الطوارئ، يجب التحقق بوسيلة مناسبة وعدم افتراض أن الوصف أو القراءة الآلية خالية من الخطأ. نرحب بالإبلاغ عن أي خلل وصولي قد يسبب ضررًا.",
                   bodyEN: "Do not use accessibility or visual-description features in ways that put someone at risk. In safety-critical settings such as roads, machinery, medication, or emergencies, verify information through an appropriate method and do not assume automated reading or description is error-free. Accessibility defects that could cause harm should be reported."),
            Clause(id: 16,
                   titleAR: "16. المحتوى الحساس والمهني",
                   titleEN: "16. Sensitive and Professional Content",
                   bodyAR: "قبل رفع ملفات تحتوي على أسرار تجارية أو بيانات عملاء أو سجلات صحية أو معلومات حكومية أو مواد خاضعة لالتزام سرية، تأكد من أن لديك التفويض وأن استخدام الخدمة متوافق مع سياسات الجهة والمتطلبات النظامية المطبقة.",
                   bodyEN: "Before submitting trade secrets, client data, health records, government information, or material subject to confidentiality duties, confirm that you are authorized and that use of the service is consistent with organizational policy and applicable legal requirements."),
            Clause(id: 17,
                   titleAR: "17. الإبلاغ والإنفاذ",
                   titleEN: "17. Reporting and Enforcement",
                   bodyAR: "يجوز فحص مؤشرات إساءة الاستخدام بالقدر اللازم لحماية الخدمة والتحقيق في البلاغات. قد تشمل الإجراءات التحذير أو الحد من الوظائف أو تعليق الوصول أو إنهاءه، بحسب خطورة السلوك وتكراره والمخاطر. يمكن استخدام قنوات الدعم الرسمية للإبلاغ أو الاعتراض على إجراء.",
                   bodyEN: "Abuse signals may be reviewed as reasonably necessary to protect the service and investigate reports. Actions may include warnings, feature limits, suspension, or termination depending on severity, repetition, and risk. Official support channels may be used to report concerns or challenge an action."),
            Clause(id: 18,
                   titleAR: "18. التحديثات",
                   titleEN: "18. Policy Updates",
                   bodyAR: "قد تتغير هذه السياسة مع تطور وظائف بصير أو ظهور مخاطر أو متطلبات نظامية جديدة. يظهر تاريخ آخر تحديث داخل التطبيق، ويعني استمرار الاستخدام بعد نفاذ التحديث الالتزام بالسياسة المعدلة وفق ما يسمح به النظام.",
                   bodyEN: "This Policy may change as Basir evolves or as new risks or legal requirements emerge. The latest revision date is displayed in the app. Continued use after an update takes effect constitutes compliance with the revised Policy to the extent permitted by law."),
        ]
    }
}
'''

# User-facing legal text intentionally identifies Basir as the service itself
# and does not name infrastructure/model vendors.
for forbidden in ("Google", "Gemini", "جوجل", "قوقل", "جيمناي", "جيميني"):
    if forbidden.casefold() in legal_source.casefold():
        raise SystemExit(f"R14 legal text contains forbidden vendor reference: {forbidden}")

views_dir.mkdir(parents=True, exist_ok=True)
legal_path.write_text(legal_source, encoding="utf-8")

# Add a simple legal card to Settings without depending on provider-specific
# settings. SettingsView already supplies `l10n`, including `isArabic`.
settings = settings_path.read_text(encoding="utf-8")
if "InstitutionLegalDocumentView" not in settings:
    body_anchor = "                        feedbackCard\n"
    if body_anchor not in settings:
        raise SystemExit("R14 Settings legal-card body anchor not found")
    settings = settings.replace(body_anchor, body_anchor + "                        legalCard\n", 1)

    card = r'''
    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("القانونية والسياسات", "Legal and policies"), systemImage: "doc.text.fill")
            NavigationLink {
                InstitutionLegalDocumentView(kind: .terms, isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("شروط الاستخدام الكاملة", "Full Terms of Use"), systemImage: "doc.text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            NavigationLink {
                InstitutionLegalDocumentView(kind: .usagePolicy, isArabic: l10n.isArabic)
            } label: {
                Label(l10n.t("سياسة الاستخدام الكاملة", "Full Usage Policy"), systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
        }
        .glassSurface()
    }

'''
    function_anchor = "    private var feedbackCard: some View {"
    if function_anchor not in settings:
        raise SystemExit("R14 Settings feedbackCard function anchor not found")
    settings = settings.replace(function_anchor, card + function_anchor, 1)

settings_path.write_text(settings, encoding="utf-8")

final_proxy = proxy_path.read_text(encoding="utf-8")
final_settings = settings_path.read_text(encoding="utf-8")
final_legal = legal_path.read_text(encoding="utf-8")
checks = (
    (final_proxy, "let sourceDocumentPages: Int"),
    (final_proxy, 'qualityMetrics["source_pages"]) == sourceDocumentPages'),
    (final_proxy, 'qualityMetrics["expected_rendered_pages"]) == expectedResultPages'),
    (final_settings, "legalCard"),
    (final_settings, "InstitutionLegalDocumentView(kind: .terms"),
    (final_settings, "InstitutionLegalDocumentView(kind: .usagePolicy"),
    (final_legal, "شروط الاستخدام"),
    (final_legal, "سياسة الاستخدام"),
)
for haystack, needle in checks:
    if needle not in haystack:
        raise SystemExit(f"R14 verification missing: {needle}")

print("BASIR_CLIENT_LAYER=R14_SELECTED_PAGE_ACCOUNTING_PLUS_INSTITUTION_LEGAL")
