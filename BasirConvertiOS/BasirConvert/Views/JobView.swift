import SwiftUI

/// Task details, shown as an expandable sheet from the compact task bar or
/// the Tasks tab. It no longer covers the whole app while a task runs.
struct JobView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var library: OutputLibraryStore
    @State private var previewURL: URL?
    @State private var shareURL: URL?
    @State private var exportURL: URL?
    @State private var showCancelConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: BasirSpacing.l) {
                        header
                        switch viewModel.status {
                        case .running:
                            runningContent
                        case .queued, .waitingForNetwork:
                            waitingContent
                        case .paused:
                            pausedContent
                        case .completed:
                            completedContent(partial: false)
                        case .partial:
                            completedContent(partial: true)
                        case .failed, .cancelled:
                            failureContent
                        case .idle:
                            EmptyView()
                        }
                    }
                    .appScreenContent(bottomPadding: 28)
                }
            }
            .foregroundStyle(BasirPalette.primaryText)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t("إغلاق", "Close")) { viewModel.dismissJob() }
                        .fontWeight(.semibold)
                        .foregroundStyle(BasirPalette.accent)
                }
            }
        }
        .escapeToDismiss { viewModel.dismissJob() }
        .sheet(item: bindingURL($previewURL)) { QuickLookPreview(url: $0.url).ignoresSafeArea() }
        .sheet(item: bindingURL($shareURL)) { ActivityShareView(urls: [$0.url]) }
        .sheet(item: bindingURL($exportURL)) { ExportDocumentPicker(urls: [$0.url]) }
        .confirmationDialog(
            l10n.t("إلغاء هذه المهمة؟", "Cancel this task?"),
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(l10n.t("إلغاء المهمة", "Cancel task"), role: .destructive) {
                OperationFeedback.warningImpact()
                viewModel.cancel()
            }
            Button(l10n.t("متابعة المعالجة", "Keep processing"), role: .cancel) { }
        } message: {
            Text(l10n.t("سيتوقف العمل الجاري، وسيبقى الملف المصدر محفوظًا لإعادة المحاولة.",
                        "Current processing will stop. The source file will be kept for retry."))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: BasirSpacing.m) {
            Image(systemName: statusIcon)
                .font(.title)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BasirSpacing.xs) {
                Text(navigationTitle)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.sourceName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BasirPalette.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let metadata = viewModel.selectedJob?.sourceMetadata {
                    Text(metadataSummary(metadata))
                        .font(.caption)
                        .foregroundStyle(BasirPalette.tertiaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var runningContent: some View {
        let percent = JobStep.overallPercent(for: viewModel.progress)
        return VStack(alignment: .leading, spacing: BasirSpacing.l) {
            VStack(alignment: .leading, spacing: BasirSpacing.s) {
                HStack {
                    Text(JobStep.current(for: viewModel.progress)?.activeTitle(l10n) ?? navigationTitle)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text("\(percent)%").font(.headline.monospacedDigit())
                }
                ProgressView(value: Double(percent), total: 100)
                    .tint(BasirPalette.accent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(l10n.t("التقدم", "Progress"))
            .accessibilityValue(JobStep.spokenStatus(for: viewModel.progress, l10n: l10n))
            .accessibilityAddTraits(.updatesFrequently)

            JobStepTimeline(progress: viewModel.progress)

            if let detail = viewModel.progress.detail, !detail.isEmpty {
                Text(localizedDetail(detail))
                    .font(.subheadline)
                    .foregroundStyle(BasirPalette.secondaryText)
            }
            if viewModel.progress.totalBytes > 0 {
                Text("\(ByteCountFormatter.string(fromByteCount: viewModel.progress.transferredBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: viewModel.progress.totalBytes, countStyle: .file))")
                    .font(.footnote).foregroundStyle(BasirPalette.secondaryText)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                AdaptiveStack {
                    metric(l10n.t("الوقت المنقضي", "Elapsed"), format(viewModel.elapsedTime))
                    if let remaining = viewModel.estimatedRemaining {
                        metric(l10n.t("المتبقي تقديريًا", "Estimated left"), format(remaining))
                    }
                }
                .accessibilityElement(children: .combine)
            }
            AdaptiveStack {
                CardActionButton(title: l10n.t("إيقاف مؤقت", "Pause"), systemImage: "pause.fill", prominent: true) {
                    viewModel.pause()
                }
                CardActionButton(title: l10n.t("إلغاء", "Cancel"), systemImage: "stop.fill") {
                    showCancelConfirmation = true
                }
            }
            Text(l10n.t("تلميح: النقر مرتين بإصبعين يوقف المهمة أو يستأنفها من أي مكان.",
                        "Tip: a two-finger double-tap pauses or resumes the task from anywhere."))
                .font(.footnote)
                .foregroundStyle(BasirPalette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassSurface()
    }

    private var waitingContent: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            Text(viewModel.errorMessage ?? l10n.t("ستبدأ المهمة تلقائيًا عندما يصبح الاتصال مناسبًا.",
                                                   "The task will start automatically when the connection is suitable."))
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryActionButton(title: l10n.t("المحاولة الآن", "Try now"), systemImage: "arrow.clockwise") {
                viewModel.resume()
            }
        }
        .glassSurface(accent: BasirPalette.warning)
    }

    private var pausedContent: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            JobStepTimeline(progress: viewModel.progress)
            Text(l10n.t("تم حفظ تقدمك. عند الاستئناف، سيكمل بصير من آخر جزء انتهى منه.",
                        "Progress is saved. Basir will reuse completed pages when you resume."))
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryActionButton(title: l10n.t("استئناف المهمة", "Resume task"), systemImage: "play.fill") {
                viewModel.resume()
            }
            SecondaryActionButton(title: l10n.t("إلغاء المهمة", "Cancel task"), systemImage: "stop.circle") {
                showCancelConfirmation = true
            }
        }
        .glassSurface(accent: BasirPalette.warning)
    }

    private func completedContent(partial: Bool) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.l) {
            VStack(alignment: .leading, spacing: BasirSpacing.m) {
                if let result = viewModel.resultURL {
                    Label(result.lastPathComponent, systemImage: "doc.richtext.fill")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryActionButton(title: l10n.t("معاينة ملف Word", "Preview Word file"), systemImage: "eye.fill") {
                        previewURL = result
                    }
                    AdaptiveStack {
                        CardActionButton(title: l10n.t("مشاركة", "Share"), systemImage: "square.and.arrow.up") {
                            shareURL = result
                        }
                        CardActionButton(title: l10n.t("حفظ في الملفات", "Save to Files"), systemImage: "folder.badge.plus") {
                            exportURL = result
                        }
                    }
                }
                if let job = viewModel.selectedJob, !job.failedItems.isEmpty {
                    Text(l10n.t(
                        "صفحات حُفظت كصور موصوفة بعد تعذر قراءة نصها: \(pageRanges(job.failedItems))",
                        "Pages kept as described images because their text could not be read: \(pageRanges(job.failedItems))"
                    ))
                    .font(.footnote)
                    .foregroundStyle(BasirPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    SecondaryActionButton(title: l10n.t("إعادة محاولة هذه الصفحات", "Retry these pages"),
                                          systemImage: "arrow.clockwise.circle") { viewModel.retryFailedItems() }
                }
            }
            .glassSurface(accent: partial ? BasirPalette.warning : BasirPalette.success)

            if let job = viewModel.selectedJob {
                if let report = job.qualityReport {
                    QualityReportCard(report: report)
                }
                completionAccounting(job)
                Text(modelSummary(job))
                    .font(.caption)
                    .foregroundStyle(BasirPalette.tertiaryText)
            }
            helpLink
        }
    }

    private var failureContent: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.l) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(viewModel.status == .failed ? BasirPalette.danger : BasirPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryActionButton(title: l10n.t("إعادة المحاولة بنفس الملف", "Retry with the same file"),
                                systemImage: "arrow.clockwise") { viewModel.retry() }
            helpLink
        }
        .glassSurface(accent: viewModel.status == .failed ? BasirPalette.danger : BasirPalette.warning)
    }

    @ViewBuilder private var helpLink: some View {
        if let diagnostic = viewModel.diagnosticURL {
            ShareLink(item: diagnostic) {
                Label(l10n.t("مشاركة معلومات المساعدة", "Share support information"), systemImage: "lifepreserver")
                    .frame(minHeight: 44)
            }
            .tint(BasirPalette.accent)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(BasirPalette.tertiaryText)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var navigationTitle: String {
        switch viewModel.status {
        case .idle: return l10n.t("المهمة", "Task")
        case .queued: return l10n.t("بانتظار البدء", "Queued")
        case .waitingForNetwork: return l10n.t("بانتظار الشبكة", "Waiting for network")
        case .running: return l10n.t("جارٍ تنفيذ المهمة", "Working")
        case .paused: return l10n.t("متوقفة مؤقتًا", "Paused")
        case .partial: return l10n.t("نتيجة جزئية جاهزة", "Partial result ready")
        case .completed: return l10n.t("ملف Word جاهز", "Word file ready")
        case .failed: return l10n.t("لم تكتمل العملية", "Could not complete")
        case .cancelled: return l10n.t("أُلغيت المهمة", "Task cancelled")
        }
    }

    private var statusIcon: String {
        switch viewModel.status {
        case .running: return "hourglass.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        case .paused: return "pause.circle.fill"
        case .waitingForNetwork: return "wifi.slash"
        case .queued: return "clock.fill"
        case .idle: return "doc"
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .completed: return BasirPalette.success
        case .failed: return BasirPalette.danger
        case .partial, .paused, .waitingForNetwork: return BasirPalette.warning
        default: return BasirPalette.accent
        }
    }

    private func modelSummary(_ job: BasirJob) -> String {
        let requested = AIModelChoice(rawValue: job.options.effectivePreferredModel)?.title(l10n)
            ?? job.options.effectivePreferredModel
        if let executed = job.executedModel, !executed.isEmpty {
            return l10n.t("النموذج: \(requested) • نُفذ: \(executed)",
                          "Model: \(requested) • executed: \(executed)")
        }
        return l10n.t("النموذج المطلوب: \(requested)", "Requested model: \(requested)")
    }

    private func completionAccounting(_ job: BasirJob) -> some View {
        let sourceTotal = job.sourceMetadata?.itemCount ?? job.progress.total
        let retained = job.progress.succeeded
        let skipped = job.skippedBlankItems.count
        let accounted = retained + skipped
        let exact = sourceTotal <= 0 || accounted == sourceTotal
        return VStack(alignment: .leading, spacing: 5) {
            Text(l10n.t(
                "المصدر \(sourceTotal) • أُدرجت \(retained) • فارغة متخطاة \(skipped) • المحاسبة \(accounted)/\(sourceTotal)",
                "Source \(sourceTotal) • retained \(retained) • blank skipped \(skipped) • accounted \(accounted)/\(sourceTotal)"
            ))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(exact ? BasirPalette.secondaryText : BasirPalette.danger)
            .fixedSize(horizontal: false, vertical: true)

            if !job.skippedBlankItems.isEmpty {
                Text(l10n.t(
                    "الصفحات الفارغة التي تم تخطيها: \(pageRanges(job.skippedBlankItems))",
                    "Blank source pages skipped: \(pageRanges(job.skippedBlankItems))"
                ))
                .font(.caption)
                .foregroundStyle(BasirPalette.tertiaryText)
            }
            if !exact {
                Label(
                    l10n.t(
                        "تحذير: أرقام الصفحات لا تتطابق مع المصدر. لا تعتمد النتيجة.",
                        "Warning: page accounting does not match the source. Do not rely on this result."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(BasirPalette.danger)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pageRanges(_ values: [Int]) -> String {
        let pages = Array(Set(values)).sorted()
        guard let first = pages.first else { return "—" }
        var ranges: [String] = []
        var start = first
        var previous = first
        for page in pages.dropFirst() {
            if page == previous + 1 {
                previous = page
                continue
            }
            ranges.append(start == previous ? "\(start)" : "\(start)–\(previous)")
            start = page
            previous = page
        }
        ranges.append(start == previous ? "\(start)" : "\(start)–\(previous)")
        return ranges.joined(separator: l10n.isArabic ? "، " : ", ")
    }

    private func metadataSummary(_ metadata: DocumentMetadata) -> String {
        var parts = [metadata.humanReadableSize]
        if let count = metadata.itemCount { parts.append(l10n.t("\(count) صفحة أو عنصر", "\(count) page(s) or item(s)")) }
        if let width = metadata.pixelWidth, let height = metadata.pixelHeight { parts.append("\(width)×\(height)") }
        return parts.joined(separator: " • ")
    }

    private func localizedDetail(_ detail: String) -> String {
        if detail.hasPrefix("page "), let number = detail.split(separator: " ").last {
            return l10n.t("الصفحة \(number)", "Page \(number)")
        }
        if detail.hasPrefix("slide "), let number = detail.split(separator: " ").last {
            return l10n.t("الشريحة \(number)", "Slide \(number)")
        }
        return detail
    }

    private func format(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "—"
    }

    private func bindingURL(_ source: Binding<URL?>) -> Binding<StablePreviewItem?> {
        Binding<StablePreviewItem?>(
            get: { source.wrappedValue.map { StablePreviewItem(url: $0) } },
            set: { source.wrappedValue = $0?.url }
        )
    }
}
