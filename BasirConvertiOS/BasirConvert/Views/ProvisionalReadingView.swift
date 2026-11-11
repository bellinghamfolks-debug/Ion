import SwiftUI

struct ReadingPreview: Decodable {
    struct Page: Decodable, Identifiable {
        var number: Int
        var status: String
        var text: String
        var id: Int { number }
    }
    var provisional: Bool
    var pages: [Page]
}

struct ProvisionalReadingView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var l10n: L10n
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let jobID: String
    let requestID: String
    @State private var preview: ReadingPreview?
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(l10n.t("قراءة أولية أثناء المعالجة", "Provisional reading during processing")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(l10n.t("معاينة نصية لأول ٢٠ صفحة منجزة بحد أقصى، قبل فحص الملف النهائي. قد تتغير النتيجة؛ ارجع إلى تقرير الجودة بعد الاكتمال. تتحدث المعاينة أثناء فتحها فقط.", "Text preview of up to the first 20 completed pages, before final validation. Content may change; review the quality report after completion. Updates run only while this screen is open."))
                        .font(.subheadline)
                    if let message { Text(message).foregroundStyle(BasirPalette.secondaryText) }
                    if preview?.pages.isEmpty != false { Text(l10n.t("لم تتوفر صفحات للقراءة الأولية بعد.", "No pages are available yet.")) }
                    ForEach(preview?.pages ?? []) { page in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(l10n.t("الصفحة \(page.number)", "Page \(page.number)")).font(.headline).accessibilityAddTraits(.isHeader)
                            Text(page.text.isEmpty ? l10n.t("لا يتوفر نص لهذه الصفحة في المعاينة. راجع نتيجتها النهائية.", "No preview text for this page. Review its final result.") : page.text)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }.glassSurface()
                    }
                }.appScreenContent()
            }.background(BasirPalette.background).navigationTitle(l10n.t("القراءة الأولية", "Provisional reading"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } } }
        }.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await reload()
                do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            }
        }
    }
    private func reload() async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do {
            preview = try await ProxyClient(configuration: settings.configuration).readingPreview(jobID: jobID, requestID: requestID)
            message = nil
        } catch is CancellationError { return }
        catch { message = l10n.t("المعاينة غير متاحة حاليًا. احتُفظ بما عُرض، وستُعاد المحاولة تلقائيًا. قد يحتاج الخادم إلى التحديث.", "Preview is unavailable. Displayed content is retained; retrying automatically. The server may need an update.") }
    }
}
