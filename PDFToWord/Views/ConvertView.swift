import SwiftUI
import UniformTypeIdentifiers

struct ConvertView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    introCard
                    fileCard

                    if appModel.isConverting {
                        progressCard
                    } else {
                        actionCard
                    }

                    if let record = appModel.currentRecord,
                       record.status == .completed,
                       let output = appModel.outputURL(for: record) {
                        resultCard(record: record, output: output)
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.text("PDFToWord"))
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { appModel.selectPDF(url) }
                case .failure(let error):
                    appModel.alertMessage = error.localizedDescription
                }
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.text("تحويل متخصص قابل للاستئناف"), systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Text(L10n.text("يحلل التطبيق كل صفحة بثلاث قراءات، ويحافظ على التنسيق الغني والجداول المدمجة والروابط والحواشي، ثم ينشئ ملف Word محليًا مع أوصاف بديلة للعناصر البصرية."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "doc.richtext")
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appModel.selectedPDF?.lastPathComponent ?? L10n.text("لم يُحدد ملف"))
                        .font(.headline)
                        .lineLimit(2)
                    if let count = appModel.selectedPageCount {
                        Text(L10n.format("عدد الصفحات: %d", count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.text("اختر ملف PDF من تطبيق الملفات"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Button {
                showingImporter = true
            } label: {
                Label(
                    appModel.selectedPDF == nil ? L10n.text("اختيار ملف PDF") : L10n.text("تغيير الملف"),
                    systemImage: "folder"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appModel.isConverting)
            .accessibilityHint(L10n.text("يفتح تطبيق الملفات لاختيار مستند PDF"))
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                appModel.hasAPIKey ? L10n.text("المفتاح موجود في Keychain") : L10n.text("مفتاح Gemini غير موجود"),
                systemImage: appModel.hasAPIKey ? "key.fill" : "key.slash"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(appModel.hasAPIKey ? Color.secondary : Color.red)

            Button {
                appModel.startConversion(options: settings.options)
            } label: {
                Label(L10n.text("بدء التحويل"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appModel.selectedPDF == nil || !appModel.hasAPIKey)
            .accessibilityHint(L10n.text("يرسل صفحات المستند إلى Gemini ثم ينشئ ملف Word داخل الجهاز"))

            Text(L10n.format("النموذج المستخدم: %@", settings.options.model))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ProgressView()
                Text(appModel.progress.status.localizedTitle)
                    .font(.headline)
            }

            ProgressView(value: appModel.progress.fraction)
                .accessibilityLabel(L10n.text("تقدم التحويل"))
                .accessibilityValue(L10n.format("النسبة المئوية: %d", Int(appModel.progress.fraction * 100)))

            Text(appModel.progress.message)
                .font(.subheadline)
                .accessibilityLiveRegion(.polite)
            if appModel.progress.totalPages > 0 {
                Text(L10n.format(
                    "الصفحات المحفوظة: %d من %d",
                    appModel.progress.currentPage,
                    appModel.progress.totalPages
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Button(L10n.text("إلغاء مع حفظ التقدم"), role: .destructive) {
                appModel.cancelConversion()
            }
            .buttonStyle(.bordered)
            .accessibilityHint(L10n.text("يوقف التحويل ويحتفظ بالصفحات المكتملة للاستئناف من السجل"))
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
        .accessibilityElement(children: .contain)
    }

    private func resultCard(record: ConversionJobRecord, output: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.text("ملف Word جاهز وتم فحص بنيته"), systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(output.lastPathComponent)
                .font(.subheadline)

            if let byteCount = record.outputByteCount {
                Text(L10n.format(
                    "الحجم المتحقق منه: %@",
                    ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let hash = record.outputSHA256, !hash.isEmpty {
                let shortHash = String(hash.prefix(12))
                Text(L10n.format("بصمة الملف: %@…", shortHash))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.format("أول اثني عشر رمزًا من بصمة سلامة الملف: %@", shortHash))
            }

            if let minimumQuality = record.minimumQualityScore {
                Label(
                    L10n.format("أدنى درجة قبول داخلية: %d%%", Int(minimumQuality * 100)),
                    systemImage: "shield.checkered"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if !record.normalizedHandwrittenPages.isEmpty {
                Label(
                    L10n.format(
                        "تم اكتشاف خط يدوي أو محتوى مختلط في الصفحات: %@",
                        L10n.pageList(record.normalizedHandwrittenPages)
                    ),
                    systemImage: "pencil.and.scribble"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if !record.normalizedFallbackPages.isEmpty {
                Label(
                    L10n.format(
                        "استُخدم مسار الحفظ الآمن في الصفحات: %@",
                        L10n.pageList(record.normalizedFallbackPages)
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            if !record.normalizedWarnings.isEmpty {
                Text(L10n.format("عدد تحذيرات الجودة المحفوظة: %d", record.normalizedWarnings.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ShareLink(item: output) {
                Label(L10n.text("مشاركة أو حفظ ملف Word"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint(L10n.text("يفتح ورقة المشاركة لاختيار Word أو تطبيق الملفات أو البريد"))
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
    }
}
